import Clocks :: *;
import Vector::*;
import FIFO::*;
import BRAMFIFO::*;
import Uart::*;
import BRAMSubWord::*;
import PLL::*;
import Sdram::*;

import Mult18x18D::*;
import SimpleFloat::*;

import NnFc::*;


interface HwMainIfc;
	method ActionValue#(Bit#(8)) serial_tx;
	method Action serial_rx(Bit#(8) rx);
endinterface

module mkHwMain#(Ulx3sSdramUserIfc mem) (HwMainIfc);
	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;
	
	Reg#(Bit#(32)) cycleCount <- mkReg(0);
	rule incCycleCount;
		cycleCount <= cycleCount + 1;
	endrule

	FIFO#(Bit#(8)) serialrxQ <- mkFIFO;
	FIFO#(Bit#(8)) serialtxQ <- mkFIFO;

	NnFcIfc nn <- mkNnFc;

	Reg#(Maybe#(Bit#(8))) inputDst <- mkReg(tagged Invalid);
	rule recvInputDst(!isValid(inputDst));
		Bit#(8) charin = serialrxQ.first();
		serialrxQ.deq;
		inputDst <= tagged Valid charin;
	endrule
	Reg#(Bit#(32)) inputBuffer <- mkReg(0);
	Reg#(Bit#(2)) inputBufferCnt <- mkReg(0);
	FIFO#(Bit#(32)) memWriteWeightQ <- mkFIFO; //FIFO for storing weight values to memory
	FIFO#(Bit#(32)) memWriteInputQ <- mkFIFO; //FIFO for storing input values to memory
	FIFO#(Bit#(16)) memWriteInputIdxQ <- mkFIFO; //FIFO for storing input values' index to memory
	rule recvInputFloat(isValid(inputDst));
		Bit#(8) charin = serialrxQ.first();
		serialrxQ.deq;
		Bit#(32) nv = (inputBuffer>>8)|(zeroExtend(charin)<<24);
		inputBuffer <= nv;

		if ( inputBufferCnt == 3 ) begin
			inputBufferCnt <= 0;
			inputDst <= tagged Invalid;
			let id = fromMaybe(?,inputDst);
			if ( id != 8'hff ) begin
				memWriteInputQ.enq(nv);
				memWriteInputIdxQ.enq(zeroExtend(id));
			end else begin
				memWriteWeightQ.enq(nv);
			end
		end else begin
			inputBufferCnt <= inputBufferCnt + 1;
		end
	endrule

	Reg#(Bit#(40)) outputBuffer <- mkReg(0); // {float,outidx}, inidx is sent immediately
	Reg#(Bit#(3)) outputBufferCnt <- mkReg(0);
	Reg#(Bit#(32)) resultDataCount <- mkReg(0);
	Reg#(Bit#(32)) lastCycle <- mkReg(0);
	Reg#(Bit#(32)) lastEmitted <- mkReg(0);
	rule serializeOutput;
		if ( outputBufferCnt > 0 ) begin
			outputBufferCnt <= outputBufferCnt - 1;
			serialtxQ.enq(truncate(outputBuffer));
			outputBuffer <= (outputBuffer>>8);
		end else begin
			if ( resultDataCount == 0 ) begin
				lastCycle <= cycleCount;
				lastEmitted <= resultDataCount;
			end
			else if (((resultDataCount + 1)&32'hff) == 0 ) begin
				$write( "Emitting %d elements over %d cycles\n", resultDataCount-lastEmitted, cycleCount-lastCycle );
				lastCycle <= cycleCount;
				lastEmitted <= resultDataCount;
			end
			resultDataCount <= resultDataCount + 1;
			let r <- nn.dataOut;
			serialtxQ.enq(tpl_2(r)); // input idx first
			outputBuffer <= {pack(tpl_1(r)),tpl_3(r)};
			outputBufferCnt <= 5;
		end
	endrule



	Reg#(Maybe#(Bit#(16))) memWriteWeightBuffer <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(16))) memWriteInputBuffer <- mkReg(tagged Invalid);
	Reg#(Bit#(24)) memWriteWeightAddr <- mkReg(0);
	Reg#(Bit#(24)) memWriteInputAddr <- mkReg(131072);
	Reg#(Bool) memWriteInputIdxDone <- mkReg(False);
	Reg#(Bool) memWriteDone <- mkReg(False);
	rule procMemWriteWeight; //0 ~ 131071 (Memory Space for Weight)
		if ( isValid(memWriteWeightBuffer) ) begin
			memWriteWeightBuffer <= tagged Invalid;
			mem.req(memWriteWeightAddr,fromMaybe(?,memWriteWeightBuffer),True);
			//$write("Stored weight address: %d\n", memWriteWeightAddr);
		end else begin
			memWriteWeightQ.deq;
			let d = memWriteWeightQ.first;
			mem.req(memWriteWeightAddr,truncate(d),True);
			memWriteWeightBuffer <= tagged Valid truncate(d>>16);
		end
		memWriteWeightAddr <= memWriteWeightAddr + 1;
	endrule

	rule procMemWriteInput;//131072 ~ 327679 (Memory Space for Input)
		if ( memWriteInputIdxDone ) begin
			if ( isValid(memWriteInputBuffer) ) begin
				memWriteInputBuffer <= tagged Invalid;
				mem.req(memWriteInputAddr,fromMaybe(?,memWriteInputBuffer),True);
				memWriteInputIdxDone <= False;
				//$write("write input");
				//$write("Stored input address: %d\n", memWriteInputAddr);
				if ( memWriteInputAddr + 1 == fromInteger(327680) ) begin
					memWriteDone <= True;
					$write("Storing task finish!\n");
				end
			end else begin
				memWriteInputQ.deq;
				let d = memWriteInputQ.first;
				mem.req(memWriteInputAddr,truncate(d),True);
				memWriteInputBuffer <= tagged Valid truncate(d>>16);
				//$write("write input");
			end
		end else begin
			memWriteInputIdxQ.deq;
			let d = memWriteInputIdxQ.first;
			mem.req(memWriteInputAddr, d, True);
			//$write("write input: %d", d);
			memWriteInputIdxDone <= True;
		end
		memWriteInputAddr <= memWriteInputAddr + 1;
		//$write("address: %d\n", memWriteInputAddr);
	endrule

	FIFO#(Bit#(16)) memReadWeightQ <- mkSizedBRAMFIFO(256);
	FIFO#(Bit#(16)) memReadInputQ <- mkSizedBRAMFIFO(192);
	FIFO#(Bit#(1)) memReadDstQ <- mkFIFO;

	Reg#(Bit#(24)) memReadWeightAddr <- mkReg(0);
	Reg#(Bit#(24)) memReadInputAddr <- mkReg(131072);

	Reg#(Bit#(24)) weightCntUp <- mkReg(0);
	Reg#(Bit#(24)) weightCntDn <- mkReg(0);
	Reg#(Bit#(24)) inputCntUp <- mkReg(0);
	Reg#(Bit#(24)) inputCntDn <- mkReg(0);

	Reg#(Bit#(16)) cntW <- mkReg(0);
	Reg#(Bit#(16)) cntI <- mkReg(0);
	
	Reg#(Bit#(1)) memReadDst <- mkReg(0);

	rule procMemReadWeightReq( (memReadDst == 0) && (weightCntUp - weightCntDn < 256) && memWriteDone );
		if ( memReadWeightAddr + 1 == memWriteWeightAddr ) memReadWeightAddr <= 0;
		else memReadWeightAddr <= memReadWeightAddr + 1;
		mem.req(memReadWeightAddr,?,False);
		if ( cntW + 1 == fromInteger(128) ) begin
			memReadDst <= 1;
			cntW <= 0;
		end else begin
			cntW <= cntW + 1;
		end
		memReadDstQ.enq(0);
		//$write("Read Address(weight): %d\n", memReadWeightAddr);
		//$write("The number of stacked FIFO for Weight: %d\n", (weightCntUp-weightCntDn));
	endrule
	rule procMemReadInputReq( (memReadDst == 1) && (inputCntUp - inputCntDn < 192) );
		if ( memReadInputAddr + 1 == memWriteInputAddr ) memReadInputAddr <= 0;
		else memReadInputAddr <= memReadInputAddr + 1;
		mem.req(memReadInputAddr,?,False);
		if ( cntI + 1 == fromInteger(192) ) begin
			memReadDst <= 0;
			cntI <= 0;
		end else begin
			cntI <= cntI + 1;
		end
		memReadDstQ.enq(1);
		//$write("Read Address(input): %d\n", memReadInputAddr);
		//$write("The number of stacked FIFO for Input: %d\n", (inputCntUp-inputCntDn));

	endrule
	rule procMemReadResp;
		let d <- mem.readResp;
		memReadDstQ.deq;
		if ( memReadDstQ.first == 0 ) begin
			memReadWeightQ.enq(d);
			//$write("Response for weight: %d\n", cntW);
			weightCntUp <= weightCntUp + 1;
		end else begin
			memReadInputQ.enq(d);
			//$write("Response for input: %d\n", cntI);
			inputCntUp <= inputCntUp + 1;
		end
	endrule

	Reg#(Maybe#(Bit#(16))) memReadWeightBuffer <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(16))) memReadInputBuffer <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(16))) memReadInputIdxBuffer <- mkReg(tagged Invalid);
	rule procMemReadWeightResp;
		if ( isValid(memReadWeightBuffer) ) begin
			memReadWeightQ.deq;
			let d = memReadWeightQ.first;
			nn.weightIn(unpack({d,fromMaybe(?,memReadWeightBuffer)}));
			//$write("read weight: %d\n", unpack({d,fromMaybe(?,memReadWeightBuffer)}));
			memReadWeightBuffer <= tagged Invalid;
			weightCntDn <= weightCntDn + 1;
		end else begin
			memReadWeightQ.deq;
			let d = memReadWeightQ.first;
			memReadWeightBuffer <= tagged Valid d;
			weightCntDn <= weightCntDn + 1;
		end
	endrule
	rule procMemReadRespInputResp;
		if ( isValid(memReadInputIdxBuffer) ) begin
			if ( isValid(memReadInputBuffer) ) begin
				memReadInputQ.deq;
				let d = memReadInputQ.first;
				nn.dataIn(unpack({d,fromMaybe(?,memReadInputBuffer)}), truncate(fromMaybe(?,memReadInputIdxBuffer)));
				//$write("read input and index: %d, %d\n", unpack({d,fromMaybe(?,memReadInputBuffer)}), fromMaybe(?,memReadInputIdxBuffer));
				memReadInputBuffer <= tagged Invalid;
				memReadInputIdxBuffer <= tagged Invalid;
				inputCntDn <= inputCntDn + 1;
			end else begin
				memReadInputQ.deq;
				let d = memReadInputQ.first;
				memReadInputBuffer <= tagged Valid d;
				inputCntDn <= inputCntDn + 1;
			end
		end else begin
			memReadInputQ.deq;
			let d = memReadInputQ.first;
			//$write("input: %d\n", d);
			memReadInputIdxBuffer <= tagged Valid d;
			inputCntDn <= inputCntDn + 1;
		end
	endrule
	
	method ActionValue#(Bit#(8)) serial_tx;
		serialtxQ.deq;
		return serialtxQ.first();
	endmethod
	method Action serial_rx(Bit#(8) d);
		serialrxQ.enq(d);
	endmethod
endmodule
