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
import FloatingPoint::*;

import NnFc::*;
import ZfpDecompress::*;
import ZfpCompress::*;

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

	ZfpCompressIfc compressorO <- mkZfpCompress;
	ZfpDecompressIfc decompressorW <- mkZfpDecompress;
	ZfpDecompressIfc decompressorI <- mkZfpDecompress;
	NnFcIfc nn <- mkNnFc;

	Reg#(Maybe#(Bit#(8))) inputDst <- mkReg(tagged Invalid);
	rule recvInputDst(!isValid(inputDst));
		Bit#(8) charin = serialrxQ.first();
		serialrxQ.deq;
		inputDst <= tagged Valid charin;
	endrule
	Reg#(Bit#(40)) inputBuffer <- mkReg(0);
	Reg#(Bit#(40)) weightBuffer <- mkReg(0);  
	Reg#(Bit#(3)) inputBufferCnt <- mkReg(0);
	Reg#(Bit#(3)) weightBufferCnt <- mkReg(0);
	FIFO#(Bit#(32)) memWriteWeightQ <- mkFIFO; //FIFO for storing weight values to memory
	FIFO#(Bit#(32)) memWriteInputQ <- mkFIFO; //FIFO for storing input values to memory
	rule recvInputFloat(isValid(inputDst));
		Bit#(8) charin = serialrxQ.first();
		serialrxQ.deq;
		let id = fromMaybe(?,inputDst);
	
		if ( id != 8'hff ) begin
			Bit#(40) nv_1 = (inputBuffer>>8)|(zeroExtend(charin)<<32);
			inputBuffer <= nv_1;
			inputDst <= tagged Invalid;
			if ( inputBufferCnt == 4 ) begin
				memWriteInputQ.enq(truncate(nv_1));
				inputBufferCnt <= 0;
			end else begin
				inputBufferCnt <= inputBufferCnt + 1;
			end
		end else begin
			Bit#(40) nv_2 = (weightBuffer>>8)|(zeroExtend(charin)<<32);
			weightBuffer <= nv_2;
			inputDst <= tagged Invalid;
			if ( weightBufferCnt == 4 ) begin
				memWriteWeightQ.enq(truncate(nv_2));
				Bit#(9) test = truncate(nv_2);
				weightBufferCnt <= 0;
			end else begin
				weightBufferCnt <= weightBufferCnt + 1;
			end
		end
	endrule

	rule putOutputtoComp;
		let out <- nn.dataOut; // tpl_1 = Float, tpl_2 = input idx, tpl_3 = output idx
		compressorO.put(pack(tpl_1(out)));
	endrule
	Reg#(Maybe#(Bit#(16))) memWriteOutputBuffer <- mkReg(tagged Invalid);
	Reg#(Bit#(24)) memWriteOutputAddr <- mkReg(8523776);
	Reg#(Bool) memWriteOutputDone <- mkReg(False);
	rule procMemWriteOutput; //8523776 ~ 8654847 (Memory Space for Output)
		if ( isValid(memWriteOutputBuffer) ) begin
			memWriteOutputBuffer <= tagged Invalid;
			mem.req(memWriteOutputAddr,fromMaybe(?,memWriteOutputBuffer),True);
			if ( memWriteOutputAddr + 1 == fromInteger(8654848) ) begin
				memWriteOutputDone <= True;
				$write("Finished saving output\n");
			end
		end else begin
			let r <- compressorO.get; 
			mem.req(memWriteOutputAddr,truncate(r),True);
			memWriteOutputBuffer <= tagged Valid truncate(r>>16);
		end
		memWriteOutputAddr <= memWriteOutputAddr + 1;
	endrule

	Reg#(Bit#(24)) memReadOutputAddr <- mkReg(8523776);
	FIFO#(Bit#(16)) memReadOutputQ <- mkSizedBRAMFIFO(64);
	rule procMemReadOutputReq( memWriteOutputDone );
		if ( memReadOutputAddr + 1 == memWriteOutputAddr ) memReadOutputAddr <= 0;
		else memReadOutputAddr <= memReadOutputAddr + 1;
		mem.req(memReadOutputAddr,?,False);
	endrule
	rule procMemReadOutputResp( memWriteOutputDone );
		let d <- mem.readResp;
		memReadOutputQ.enq(d);
	endrule
	
	Reg#(Bit#(8)) memReadOutputBuffer <- mkReg(0); 
	Reg#(Bit#(3)) memReadOutputBufferCnt <- mkReg(0);
	rule serializeOutput;
		if ( memReadOutputBufferCnt > 0 ) begin
			serialtxQ.enq(memReadOutputBuffer);
			memReadOutputBufferCnt <= 0;
		end else begin
			memReadOutputQ.deq;
			let d = memReadOutputQ.first;
			serialtxQ.enq(truncate(d));
			memReadOutputBuffer <= truncateLSB(d);
			memReadOutputBufferCnt <= memReadOutputBufferCnt + 1;
		end
	endrule


	Reg#(Maybe#(Bit#(16))) memWriteWeightBuffer <- mkReg(tagged Invalid);
	Reg#(Maybe#(Bit#(16))) memWriteInputBuffer <- mkReg(tagged Invalid);
	Reg#(Bit#(24)) memWriteWeightAddr <- mkReg(0);
	Reg#(Bit#(24)) memWriteInputAddr <- mkReg(8390656);
	Reg#(Bool) memWriteWeightDone <- mkReg(False);
	Reg#(Bool) memWriteDone <- mkReg(False);
	rule procMemWriteWeight; //0 ~ 8390655 (Memory Space for Weight & bias)
		if ( isValid(memWriteWeightBuffer) ) begin
			memWriteWeightBuffer <= tagged Invalid;	
			mem.req(memWriteWeightAddr,fromMaybe(?,memWriteWeightBuffer),True);
			if ( memWriteWeightAddr + 1 == fromInteger(8390656) ) begin
				memWriteWeightDone <= True;
				$write("Finished saving weight and bias values\n");
			end
		end else begin
			memWriteWeightQ.deq;
			let d = memWriteWeightQ.first;
			mem.req(memWriteWeightAddr,truncate(d),True);
			memWriteWeightBuffer <= tagged Valid truncate(d>>16);
		end
		memWriteWeightAddr <= memWriteWeightAddr + 1;
		//$write("%d\n", memWriteWeightAddr);
	endrule
	rule procMemWriteInput;//8390656 ~ 8521727 (Memory Space for Input)
		if ( isValid(memWriteInputBuffer) ) begin
			memWriteInputBuffer <= tagged Invalid;
			mem.req(memWriteInputAddr,fromMaybe(?,memWriteInputBuffer),True);
			if ( memWriteInputAddr + 1 == fromInteger(8523776) ) begin
				memWriteDone <= True;
				$write("Finished saving input values\n");
			end
		end else begin
			memWriteInputQ.deq;
			let d = memWriteInputQ.first;
			mem.req(memWriteInputAddr,truncate(d),True);
			memWriteInputBuffer <= tagged Valid truncate(d>>16);
		end
		memWriteInputAddr <= memWriteInputAddr + 1;
	endrule

	FIFO#(Bit#(16)) memReadWeightQ <- mkSizedBRAMFIFO(128);
	FIFO#(Bit#(16)) memReadInputQ <- mkSizedBRAMFIFO(128);
	FIFO#(Bit#(1)) memReadDstQ <- mkSizedBRAMFIFO(64);

	Reg#(Bit#(24)) memReadWeightAddr <- mkReg(0);
	Reg#(Bit#(24)) memReadInputAddr <- mkReg(8390656);

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
		//$write("weight stack: %d\n", (weightCntUp - weightCntDn));
	endrule
	rule procMemReadInputReq( (memReadDst == 1) && (inputCntUp - inputCntDn < 128) );
		if ( memReadInputAddr + 1 == memWriteInputAddr ) memReadInputAddr <= fromInteger(8390656);
		else memReadInputAddr <= memReadInputAddr + 1;
		mem.req(memReadInputAddr,?,False);
		if ( cntI + 1 == fromInteger(64) ) begin
			memReadDst <= 0;
			cntI <= 0;
		end else begin
			cntI <= cntI + 1;
		end
		memReadDstQ.enq(1);
		//$write("input stack: %d\n", (inputCntUp - inputCntDn));
	endrule
	Reg#(Bit#(32)) memReadCnt <- mkReg(0);
	rule procMemReadResp;
		let d <- mem.readResp;
		memReadDstQ.deq;
		memReadCnt <= memReadCnt + 1;

		if ( (memReadCnt&32'h7ffff) == 0 ) begin
			$write( "Debug Mem Read: %d cycles -- %d mem Reads\n", cycleCount, memReadCnt );
		end

		if ( memReadDstQ.first == 0 ) begin
			memReadWeightQ.enq(d);
			weightCntUp <= weightCntUp + 1;
		end else begin
			memReadInputQ.enq(d);
			inputCntUp <= inputCntUp + 1;
		end
	endrule

	Reg#(Bit#(32)) memReadWeightBuffer <- mkReg(0);
	Reg#(Bit#(2)) memReadWeightBufferCnt <- mkReg(0);
	rule putWeighttoDecomp;
		memReadWeightQ.deq;
		weightCntDn <= weightCntDn + 1;
		let d = memReadWeightQ.first;
		Bit#(32) nv = (memReadWeightBuffer>>16)|(zeroExtend(d)<<16);
		memReadWeightBuffer <= nv;

		if ( memReadWeightBufferCnt == 1 ) begin
			memReadWeightBufferCnt <= 0;
			decompressorW.put(zeroExtend(nv));
		end else begin
			memReadWeightBufferCnt <= memReadWeightBufferCnt + 1;
		end
	endrule

	Reg#(Bit#(32)) memReadInputBuffer <- mkReg(0);
	Reg#(Bit#(2)) memReadInputBufferCnt <- mkReg(0);
	rule putInputtoDecomp;
		memReadInputQ.deq;
		inputCntDn <= inputCntDn + 1;
		let d = memReadInputQ.first;
		Bit#(32) nv = (memReadInputBuffer>>16)|(zeroExtend(d)<<16);
		memReadInputBuffer <= nv;

		if ( memReadInputBufferCnt == 1 ) begin
			memReadInputBufferCnt <= 0;
			decompressorI.put(zeroExtend(nv));
		end else begin
			memReadInputBufferCnt <= memReadInputBufferCnt + 1;
		end
	endrule

	rule serializeWeight;
		let d <- decompressorW.get;
		nn.weightIn(unpack(d));
	endrule
	Reg#(Bit#(8)) inputIdxCycle <- mkReg(0);
	rule serializeInput;
		let d <- decompressorI.get;
		nn.dataIn(unpack(d),inputIdxCycle);
		if ( inputIdxCycle == 63 ) inputIdxCycle <= 0;
		else inputIdxCycle <= inputIdxCycle + 1;
		
	endrule
	
	method ActionValue#(Bit#(8)) serial_tx;
		serialtxQ.deq;
		return serialtxQ.first();
	endmethod
	method Action serial_rx(Bit#(8) d);
		serialrxQ.enq(d);
	endmethod
endmodule
