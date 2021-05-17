import Clocks :: *;
import Vector::*;
import FIFO::*;
import Uart::*;
import BRAMSubWord::*;
import PLL::*;
import Sdram::*;

import HwMain::*;


interface TopIfc;
	(* always_ready *)
	method Bit#(1) ftdi_rxd;
	(* always_enabled, always_ready, prefix = "", result = "serial_txd" *)
	method Action ftdi_tx(Bit#(1) ftdi_txd);
	(* always_enabled, always_ready, prefix = "", result = "led" *)
	method Bit#(8) led;
	
`ifndef BSIM
	(* always_ready, prefix = "" *)
	interface Ulx3sSdramPinsIfc sdram_pins; 
`endif
endinterface

(* no_default_clock, no_default_reset*)
module mkTop#(Clock clk_25mhz)(TopIfc);
	PLLIfc pll <- mkPllFast(clk_25mhz);
	Reset rst_target = pll.rst_100mhz;
	Clock clk_target = pll.clk_100mhz;
	
	Reset rst_null = noReset();
	UartIfc uart <- mkUart(217, clocked_by clk_25mhz, reset_by rst_null); //115200 baud on 25 mhz
	SyncFIFOIfc#(Bit#(8)) serialToMainQ <- mkSyncFIFO(4,clk_25mhz, rst_null, clk_target);
	SyncFIFOIfc#(Bit#(8)) mainToSerialQ <- mkSyncFIFO(4,clk_target, rst_target, clk_25mhz);
	
	Ulx3sSdramIfc mem <- mkUlx3sSdram(pll.clk_100mhz, 100, clocked_by clk_target, reset_by rst_target);

	HwMainIfc main <- mkHwMain(mem.user, clocked_by clk_target, reset_by rst_target);

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



	method Bit#(1) ftdi_rxd;
		return uart.serial_txd;
	endmethod
	method Action ftdi_tx(Bit#(1) ftdi_txd);
		uart.serial_rx(ftdi_txd);
	endmethod
`ifndef BSIM
	interface sdram_pins = mem.pins;
`endif
	method Bit#(8) led;
		return uartInWord;
	endmethod
endmodule

module mkTop_bsim(Empty);
	Clock curclk <- exposeCurrentClock;
	Ulx3sSdramIfc mem <- mkUlx3sSdram(curclk, 100);
	HwMainIfc main <- mkHwMain(mem.user);
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
