import Clocks :: *;
import Vector::*;
import FIFO::*;
import Uart::*;
import BRAMSubWord::*;
import PLL::*;

import Mult18x18D::*;
import SimpleFloat::*;

interface HwMainIfc;
	method ActionValue#(Bit#(8)) serial_tx;
	method Action serial_rx(Bit#(8) rx);
endinterface

module mkHwMain(HwMainIfc);
	Reg#(Bool) processorStart <- mkReg(False);

	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;


	Reg#(Maybe#(Bit#(8))) serialCmd <- mkReg(tagged Invalid);


	Mult18x18DIfc mult <- mkMult18x18D;

	Reg#(Bit#(96)) floatInBuffer <- mkReg(0);
	Reg#(Bit#(4)) floatInCnt <- mkReg(0);
	FIFO#(Bit#(32)) addQ <- mkFIFO;
	FloatTwoOp fmult <- mkFloatMult;
	FloatTwoOp fadd <- mkFloatAdd;


	FIFO#(Bit#(8)) serialrxQ <- mkFIFO;
	FIFO#(Bit#(8)) serialtxQ <- mkFIFO;
	Reg#(Bit#(8)) datbuf <- mkReg(0);


	rule procUartIn;
		Bit#(8) charin = serialrxQ.first();
		serialrxQ.deq;

		/*
		let n = charin - 48;
		datbuf <= n;
		mult.put(zeroExtend(n), zeroExtend(datbuf));
		*/
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

	method ActionValue#(Bit#(8)) serial_tx;
		serialtxQ.deq;
		return serialtxQ.first();
	endmethod
	method Action serial_rx(Bit#(8) d);
		serialrxQ.enq(d);
	endmethod
endmodule

interface TopIfc;
	(* always_ready *)
	method Bit#(1) ftdi_rxd;
	(* always_enabled, always_ready, prefix = "", result = "serial_txd" *)
	method Action ftdi_tx(Bit#(1) ftdi_txd);
	(* always_enabled, always_ready, prefix = "", result = "led" *)
	method Bit#(8) led;
endinterface

(* no_default_clock, no_default_reset*)
module mkTop#(Clock clk_25mhz)(TopIfc);
	PLLIfc pll <- mkPllFast(clk_25mhz);
	Reset rst_target = pll.rst_100mhz;
	Clock clk_target = pll.clk_100mhz;
	
	Reset rst_null = noReset();
	UartIfc uart <- mkUart(2604, clocked_by clk_25mhz, reset_by rst_null);
	SyncFIFOIfc#(Bit#(8)) serialToMainQ <- mkSyncFIFO(4,clk_25mhz, rst_null, clk_target);
	SyncFIFOIfc#(Bit#(8)) mainToSerialQ <- mkSyncFIFO(4,clk_target, rst_target, clk_25mhz);

	HwMainIfc main <- mkHwMain(clocked_by clk_target, reset_by rst_target);

	Reg#(Bit#(8)) uartInWord <- mkReg(0, clocked_by clk_25mhz, reset_by rst_null);
	rule relayUartIn;
		Bit#(8) d <- uart.user.get;
		serialToMainQ.enq(d);
		uartInWord <= d;
	endrule
	rule relayUartIn2;
		serialToMainQ.deq;
		main.serial_rx(serialToMainQ.first);
	endrule

	rule relayUartOut;
		let d <- main.serial_tx;
		mainToSerialQ.enq(d);
	endrule
	rule relayUartOut2;
		mainToSerialQ.deq;
		uart.user.send(mainToSerialQ.first);
	endrule

	/*
	Reg#(Bit#(32)) clkcount <- mkReg(0, clocked_by clk_25mhz, reset_by rst_null);
	Reg#(Bit#(8)) secondcount <- mkReg(0, clocked_by clk_25mhz, reset_by rst_null); 
	rule incclk;
		if ( clkcount >= 25000000 ) begin
			clkcount <= 0;
			secondcount <= secondcount + 1;
		end
		else clkcount <= clkcount + 1;
	endrule
	*/


	method Bit#(1) ftdi_rxd;
		return uart.serial_txd;
	endmethod
	method Action ftdi_tx(Bit#(1) ftdi_txd);
		uart.serial_rx(ftdi_txd);
	endmethod
	method Bit#(8) led;
		return uartInWord;
	endmethod
endmodule

module mkTop_bsim(Empty);
	HwMainIfc main <- mkHwMain;
	UartUserIfc uart <- mkUart_bsim;
	rule relayUartIn;
		let d <- uart.get;
		main.serial_rx(d);
	endrule
	rule relayUartOut;
		let d <- main.serial_tx;
		//$write( "uart sending serial\n" );
		uart.send(d);
	endrule
endmodule
