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

	Reg#(Bit#(48)) memWriteOutputBuffer <- mkReg(0);
	Reg#(Bit#(2)) memWriteOutputBufferCnt <- mkReg(0);
	Reg#(Bit#(24)) memWriteOutputAddr <- mkReg(327680);
	Reg#(Bool) memWriteOutputDone <- mkReg(False);
	rule procMemWriteOutput; //327680 ~ 339967 (Memory Space for Output), 1st: inidx, 2nd: outidx, 3rd: half of float(2/2), 4th: half of float(1/2)
		if ( memWriteOutputBufferCnt > 0 ) begin
			memWriteOutputBufferCnt <= memWriteOutputBufferCnt - 1;
			mem.req(memWriteOutputAddr,truncate(memWriteOutputBuffer),True);
			memWriteOutputBuffer <= (memWriteOutputBuffer>>16);
			if ( memWriteOutputAddr + 1 == fromInteger(344064) ) begin
				memWriteOutputDone <= True;
				$write("Finished saving output\n");
			end
		end else begin
			let r <- nn.dataOut; //tpl_1 = result value, tpl_2 = input idx, tpl_3 = output idx
			mem.req(memWriteOutputAddr,zeroExtend(tpl_2(r)),True); //input idx first
			memWriteOutputBuffer <= {pack(tpl_1(r)), zeroExtend(tpl_3(r))};
			memWriteOutputBufferCnt <= 3;
		end
		memWriteOutputAddr <= memWriteOutputAddr + 1;
	endrule

	Reg#(Bit#(24)) memReadOutputAddr <- mkReg(327680);
	FIFO#(Bit#(16)) memReadOutputQ <- mkSizedBRAMFIFO(64);
	rule procMemReadOutputReq( memWriteOutputDone ); // && (outputCntUp - outputCntDn < 64) );
		if ( memReadOutputAddr + 1 == memWriteOutputAddr ) memReadOutputAddr <= 0;
		else memReadOutputAddr <= memReadOutputAddr + 1;
		mem.req(memReadOutputAddr,?,False);
	endrule
	rule procMemReadOutputResp( memWriteOutputDone );
		let d <- mem.readResp;
		memReadOutputQ.enq(d);
	endrule

	Reg#(Bit#(16)) outputBuffer <- mkReg(0); // for sending output value (float)
	Reg#(Bit#(3)) outputBufferCnt <- mkReg(0);
	Reg#(Bit#(32)) resultDataCount <- mkReg(0);
	Reg#(Bit#(32)) lastCycle <- mkReg(0);
	Reg#(Bit#(32)) lastEmitted <- mkReg(0);
	rule serializeOutput;
		if ( outputBufferCnt > 0 ) begin
			outputBufferCnt <= outputBufferCnt - 1;
			if ( outputBufferCnt == fromInteger(5) ) begin
				memReadOutputQ.deq;
				serialtxQ.enq(truncate(memReadOutputQ.first));
			end else begin
				if ( (outputBufferCnt == fromInteger(4)) || (outputBufferCnt == fromInteger(2)) ) begin
					memReadOutputQ.deq;
					let d = memReadOutputQ.first;
					serialtxQ.enq(truncate(d)); //could relay 8 bits per one cycle to host
					outputBuffer <= (d>>8);
				end else begin
					serialtxQ.enq(truncate(outputBuffer));
				end
			end 
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
			memReadOutputQ.deq;
			serialtxQ.enq(truncate(memReadOutputQ.first)); // input idx first
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
				if ( memWriteInputAddr + 1 == fromInteger(327680) ) begin
					memWriteDone <= True;
					$write("Finished saving input and weight values\n");
				end
			end else begin
				memWriteInputQ.deq;
				let d = memWriteInputQ.first;
				mem.req(memWriteInputAddr,truncate(d),True);
				memWriteInputBuffer <= tagged Valid truncate(d>>16);
			end
		end else begin
			memWriteInputIdxQ.deq;
			let d = memWriteInputIdxQ.first;
			mem.req(memWriteInputAddr, d, True);
			memWriteInputIdxDone <= True;
		end
		memWriteInputAddr <= memWriteInputAddr + 1;
	endrule

	FIFO#(Bit#(16)) memReadWeightQ <- mkSizedBRAMFIFO(128);
	FIFO#(Bit#(16)) memReadInputQ <- mkSizedBRAMFIFO(192);
	FIFO#(Bit#(1)) memReadDstQ <- mkFIFO;

	Reg#(Bit#(24)) memReadWeightAddr <- mkReg(0);
	Reg#(Bit#(24)) memReadInputAddr <- mkReg(131072);

	Reg#(Bit#(8)) weightCntUp <- mkReg(0);
	Reg#(Bit#(8)) weightCntDn <- mkReg(0);
	Reg#(Bit#(8)) inputCntUp <- mkReg(0);
	Reg#(Bit#(8)) inputCntDn <- mkReg(0);

	Reg#(Bit#(8)) cntW <- mkReg(0);
	Reg#(Bit#(8)) cntI <- mkReg(0);
	
	Reg#(Bit#(1)) memReadDst <- mkReg(0);

	rule procMemReadWeightReq( (memReadDst == 0) && (weightCntUp - weightCntDn < 128) && memWriteDone );
		if ( memReadWeightAddr + 1 == memWriteWeightAddr ) memReadWeightAddr <= 0;
		else memReadWeightAddr <= memReadWeightAddr + 1;
		mem.req(memReadWeightAddr,?,False);
		if ( cntW + 1 == fromInteger(64) ) begin
			memReadDst <= 1;
			cntW <= 0;
		end else begin
			cntW <= cntW + 1;
		end
		memReadDstQ.enq(0);
	endrule
	rule procMemReadInputReq( (memReadDst == 1) && (inputCntUp - inputCntDn < 192) );
		if ( memReadInputAddr + 1 == memWriteInputAddr ) memReadInputAddr <= fromInteger(131072);
		else memReadInputAddr <= memReadInputAddr + 1;
		mem.req(memReadInputAddr,?,False);
		if ( cntI + 1 == fromInteger(96) ) begin
			memReadDst <= 0;
			cntI <= 0;
		end else begin
			cntI <= cntI + 1;
		end
		memReadDstQ.enq(1);
	endrule
	rule procMemReadResp;
		let d <- mem.readResp;
		memReadDstQ.deq;
		if ( memReadDstQ.first == 0 ) begin
			memReadWeightQ.enq(d);
			weightCntUp <= weightCntUp + 1;
		end else begin
			memReadInputQ.enq(d);
			inputCntUp <= inputCntUp + 1;
		end
	endrule

	Reg#(Maybe#(Bit#(16))) memReadWeightBuffer <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(16))) memReadInputBuffer <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(16))) memReadInputIdxBuffer <- mkReg(tagged Invalid);
	rule serializeWeight;
		if ( isValid(memReadWeightBuffer) ) begin
			memReadWeightQ.deq;
			let d = memReadWeightQ.first;
			nn.weightIn(unpack({d,fromMaybe(?,memReadWeightBuffer)}));
			memReadWeightBuffer <= tagged Invalid;
			weightCntDn <= weightCntDn + 1;
		end else begin
			memReadWeightQ.deq;
			let d = memReadWeightQ.first;
			memReadWeightBuffer <= tagged Valid d;
			weightCntDn <= weightCntDn + 1;
		end
	endrule
	rule serializeInput;
		if ( isValid(memReadInputIdxBuffer) ) begin
			if ( isValid(memReadInputBuffer) ) begin
				memReadInputQ.deq;
				let d = memReadInputQ.first;
				nn.dataIn(unpack({d,fromMaybe(?,memReadInputBuffer)}), truncate(fromMaybe(?,memReadInputIdxBuffer)));
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
