import Clocks :: *;
import Vector::*;
import FIFO::*;
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
	//Reg#(Bit#(24)) memWriteOffset <- mkReg(0);
	Reg#(Bool) memWriteDone <- mkReg(False);
	FIFO#(Bit#(32)) memWriteQ <- mkFIFO;
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
				nn.dataIn(unpack(nv), id);
				memWriteDone <= True;
			end else begin
				memWriteQ.enq(nv);
				// write to mem
				//$write( "Writing %x to mem %d\n", nv, memWriteOffset );
				//memWriteOffset <= memWriteOffset + 1;
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



	Reg#(Maybe#(Bit#(16))) memWriteBuffer <- mkReg(tagged Invalid);
	Reg#(Bit#(24)) memWriteAddr <- mkReg(0);
	rule procMemWrite;
		if ( isValid(memWriteBuffer) ) begin
			memWriteBuffer <= tagged Invalid;
			mem.req(memWriteAddr,fromMaybe(?,memWriteBuffer),True);
		end else begin
			memWriteQ.deq;
			let d = memWriteQ.first;
			mem.req(memWriteAddr,truncate(d),True);
			memWriteBuffer <= tagged Valid truncate(d>>16);
		end
		memWriteAddr <= memWriteAddr + 1;
	endrule

	Reg#(Bit#(24)) memReadAddr <- mkReg(0);
	(* descending_urgency = "procMemWrite, procMemRead" *)
	rule procMemRead (memWriteDone);
		if ( memReadAddr + 1 == memWriteAddr ) memReadAddr <= 0;
		else memReadAddr <= memReadAddr + 1;
		mem.req(memReadAddr,?,False);
	endrule

	Reg#(Maybe#(Bit#(16))) memReadBuffer <- mkReg(tagged Invalid);
	rule procMemReadResp;
		let d <- mem.readResp;
		if ( isValid(memReadBuffer) ) begin
			nn.weightIn(unpack({d,fromMaybe(?,memReadBuffer)}));
			memReadBuffer <= tagged Invalid;
		end else begin
			memReadBuffer <= tagged Valid d;
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
