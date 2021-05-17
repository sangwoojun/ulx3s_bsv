import Clocks :: *;
import Vector::*;
import FIFO::*;
import Uart::*;
import BRAMSubWord::*;
import PLL::*;
import Sdram::*;

import Mult18x18D::*;
import SimpleFloat::*;

interface HwMainIfc;
	method ActionValue#(Bit#(8)) serial_tx;
	method Action serial_rx(Bit#(8) rx);

endinterface

module mkHwMain#(Ulx3sSdramUserIfc mem) (HwMainIfc);
	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;

	FIFO#(Bit#(8)) serialrxQ <- mkFIFO;
	FIFO#(Bit#(8)) serialtxQ <- mkFIFO;


	Reg#(Bit#(64)) sdramCmd <- mkReg(0);
	Reg#(Bit#(8)) sdramCmdCnt <- mkReg(0);
	rule procUartIn;
		Bit#(8) charin = serialrxQ.first();
		serialrxQ.deq;

		let nd = (sdramCmd<<8)|zeroExtend(charin);
		if ( sdramCmdCnt + 1 >= 6 ) begin
			sdramCmdCnt <= 0;
			sdramCmd <= 0;
			Bit#(24) addr = truncate(nd);
			Bit#(16) data = truncate(nd>>24);
			Bool isWrite = (nd[40] == 1);
			mem.req(addr,data,isWrite);
			//$write("Req addr %x data %x write %s\n", addr, data, isWrite?"yes":"no");
		end else begin
			sdramCmd <= nd;
			sdramCmdCnt <= sdramCmdCnt + 1;
		end
	endrule
	Reg#(Bit#(8)) sdramReadOutBuf <- mkReg(0);
	Reg#(Bool) sdramReadOutBuffered <- mkReg(False);
	rule relaySdramread;
		if ( sdramReadOutBuffered ) begin
			serialtxQ.enq(sdramReadOutBuf);
			sdramReadOutBuffered <= False;
		end else begin
			let d <- mem.readResp;
			serialtxQ.enq(truncate(d>>8));
			sdramReadOutBuf <= truncate(d);
			sdramReadOutBuffered <= True;
		end
	endrule



/*
	Reg#(Bit#(96)) floatInBuffer <- mkReg(0);
	Reg#(Bit#(4)) floatInCnt <- mkReg(0);
	FIFO#(Bit#(32)) addQ <- mkFIFO;
	FloatTwoOp fmult <- mkFloatMult;
	FloatTwoOp fadd <- mkFloatAdd;

	rule procUartIn;
		Bit#(8) charin = serialrxQ.first();
		serialrxQ.deq;

		let nd = (floatInBuffer<<8)|zeroExtend(charin);
		if ( floatInCnt == 11 ) begin
			fmult.put(unpack(truncate(nd)), unpack(truncate(nd>>32)));
			addQ.enq(truncate(nd>>64));
			floatInCnt <= 0;
			floatInBuffer <= 0;
		end else begin
			floatInCnt <= floatInCnt + 1;
			floatInBuffer <= nd;
		end
	endrule
	rule procAdd;
		let nd_ <- fmult.get;
		addQ.deq;
		fadd.put(nd_, unpack(addQ.first));
	endrule

	Reg#(Bit#(32)) floatOut <- mkReg(0);
	Reg#(Bit#(2)) floatOutCnt <- mkReg(0);
	rule outputCnt;
		if ( floatOutCnt == 0 ) begin
			let nd_ <- fadd.get;
			//let nd_ <- fmult.get;
			Bit#(32) nd = pack(nd_);
			floatOut <= {nd[23:0],0};
			serialtxQ.enq(nd[31:24]);
			floatOutCnt <= 3;
		end else begin
			floatOutCnt <= floatOutCnt - 1;
			Bit#(32) nd = floatOut;
			floatOut <= {nd[23:0],0};
			serialtxQ.enq(nd[31:24]);
		end
	endrule
	*/

	method ActionValue#(Bit#(8)) serial_tx;
		serialtxQ.deq;
		return serialtxQ.first();
	endmethod
	method Action serial_rx(Bit#(8) d);
		serialrxQ.enq(d);
	endmethod
endmodule
