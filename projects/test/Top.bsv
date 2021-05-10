import Clocks :: *;
import Vector::*;
import FIFO::*;
import Uart::*;
import BRAMSubWord::*;
import PLL::*;

import Mult18x18D::*;

interface HwMainIfc;
	method ActionValue#(Bit#(8)) serial_tx;
	method Action serial_rx(Bit#(8) rx);
endinterface

module mkHwMain(HwMainIfc);
	Reg#(Bool) processorStart <- mkReg(False);

	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;


	Reg#(Maybe#(Bit#(8))) serialCmd <- mkReg(tagged Invalid);


	Vector#(32, Mult18x18DIfc) mults <- replicateM(mkMult18x18DImport(curclk, currst));


	FIFO#(Bit#(8)) serialrxQ <- mkFIFO;
	FIFO#(Bit#(8)) serialtxQ <- mkFIFO;
	/*
	rule procSerialRx;
		let d = serialrxQ.first;
		serialrxQ.deq;
		mult1.puta( zeroExtend(d) );
		mult1.putb( zeroExtend(d>>2) );
		serialtxQ.enq(d);
	endrule
	*/
	for(Integer i = 0; i <31; i=i+1 ) begin
		rule ma;
			let d = mults[i].dataout;
			mults[i+1].puta(truncate(d>>2));
			mults[i+1].putb(truncate(d));
		endrule
	end

	method ActionValue#(Bit#(8)) serial_tx;
		let d = mults[31].dataout;
		return truncate(d);
	endmethod
	method Action serial_rx(Bit#(8) d);
		mults[0].puta(zeroExtend(d));
		mults[0].putb(zeroExtend(d>>4));
	endmethod
endmodule

interface TopIfc;
	(* always_ready *)
	method Bit#(1) ftdi_rxd;
	(* always_enabled, always_ready, prefix = "", result = "serial_txd" *)
	method Action ftdi_tx(Bit#(1) ftdi_txd);
endinterface

(* no_default_clock, no_default_reset*)
module mkTop#(Clock clk_25mhz)(TopIfc);
	PLLIfc pll <- mkPllFast(clk_25mhz);
	Reset rst_target = pll.rst_125mhz;
	Clock clk_target = pll.clk_125mhz;
	
	Reset rst_null = noReset();
	UartIfc uart <- mkUart(2604, clocked_by clk_25mhz, reset_by rst_null);
	SyncFIFOIfc#(Bit#(8)) serialToMainQ <- mkSyncFIFO(4,clk_25mhz, rst_null, clk_target);
	SyncFIFOIfc#(Bit#(8)) mainToSerialQ <- mkSyncFIFO(4,clk_target, rst_target, clk_25mhz);

	HwMainIfc main <- mkHwMain(clocked_by clk_target, reset_by rst_target);

	rule relayUartIn;
		Bit#(8) d <- uart.user.get;
		serialToMainQ.enq(d);
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


	method Bit#(1) ftdi_rxd;
		return uart.serial_txd;
	endmethod
	method Action ftdi_tx(Bit#(1) ftdi_txd);
		uart.serial_rx(ftdi_txd);
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
