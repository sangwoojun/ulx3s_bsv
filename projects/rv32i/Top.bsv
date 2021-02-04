import Clocks :: *;
import Vector::*;
import FIFO::*;
import Uart::*;
import BRAMSubWord::*;

import Defines::*;
import Processor::*;

interface HwMainIfc;
	method ActionValue#(Bit#(8)) serial_tx;
	method Action serial_rx(Bit#(8) rx);
endinterface

module mkHwMain(HwMainIfc);
	Reg#(Bool) processorStart <- mkReg(False);
	ProcessorIfc proc <- mkProcessor;
	Reg#(Bit#(12)) imembytes <- mkReg(0);
	BRAMSubWord4Ifc#(12) imem <- mkBRAMSubWord; // 4KB
	Reg#(Bit#(12)) dmembytes <- mkReg(0);
	BRAMSubWord4Ifc#(12) dmem <- mkBRAMSubWord; // 4KB

	rule relayImemReq (processorStart);
		let req <- proc.iMemReq;
		imem.req(truncate(req.addr), req.word, req.bytes, req.write);
	endrule
	FIFO#(Bit#(8)) serialtxQ <- mkFIFO;
	rule relayDmemReq (processorStart);
		let req <- proc.dMemReq;
		if ( 0 == (req.addr>>12)) begin
			if ( req.write) begin
				serialtxQ.enq(truncate(req.word));
				//$write("Writing!  %x(%d) %x\n", req.addr,req.bytes, req.word);
			end else begin
				//$write("Reading!  %x(%d) %x\n", req.addr,req.bytes, req.word);
			end
		end else begin
			dmem.req(truncate(req.addr), req.word, req.bytes, req.write); // truncating address should work automatically
			//$write("Reading!  %x(%d) %x\n", req.addr,req.bytes, req.word);
		end
	endrule




	Reg#(Maybe#(Bit#(8))) serialCmd <- mkReg(tagged Invalid);

	rule procimemread;
		let d <- imem.resp;
		proc.iMemResp(d);
		//$write( "imem resp %x\n", d );
	endrule
	rule procdmemread;
		let d <- dmem.resp;
		proc.dMemResp(d);
		//$write( "dmem resp %x\n",d );
	endrule

	FIFO#(Bit#(8)) serialrxQ <- mkFIFO;
	rule procSerialRx;
		let d = serialrxQ.first;
		serialrxQ.deq;

		if ( !isValid(serialCmd) ) begin
			serialCmd <= tagged Valid d;
		end else begin
			serialCmd <= tagged Invalid;
			Bit#(8) cmd = fromMaybe(?, serialCmd);
			if ( cmd[0] == 0 ) begin // mem IO
				if ( cmd[1] == 0 ) begin // imem
					//if ( cmd[2] == 0 ) begin // mem write
						imembytes <= imembytes + 1;
						imem.req(imembytes, zeroExtend(d), 0, True); // write 1 byte to bwoff
					//end else begin // mem read
					//	imem.req(imembytes, zeroExtend(d), 0, False); // read 1 byte from bwoff
					//end
				end else begin // dmem
					//if ( cmd[2] == 0 ) begin // mem write
						dmembytes <= dmembytes + 1;
						dmem.req(dmembytes, zeroExtend(d), 0, True); // write 1 byte to bwoff
					//end else begin // mem read
					//	dmem.req(dmembytes, zeroExtend(d), 0, False); // read 1 byte from bwoff
					//end
				end 
			end
			else begin // non-mem cmd, or mem cmd issued when processor started...
				$write( "Processor starting\n" );
				processorStart <= True;
			end
		end
	endrule

	method ActionValue#(Bit#(8)) serial_tx;
		serialtxQ.deq;
		return serialtxQ.first;
	endmethod
	method Action serial_rx(Bit#(8) d);
		serialrxQ.enq(d);
	endmethod
endmodule

interface TopIfc;
	(* always_ready *)
	method Bit#(1) ftdi_txd;
	(* always_enabled, always_ready, prefix = "", result = "serial_rxd" *)
	method Action ftdi_rx(Bit#(1) ftdi_rxd);
endinterface

(* no_default_clock, no_default_reset*)
module mkTop#(Clock clk_25mhz)(TopIfc);
	Reset rst_null = noReset();
	UartIfc uart <- mkUart(2604, clocked_by clk_25mhz, reset_by rst_null);

	HwMainIfc main <- mkHwMain(clocked_by clk_25mhz, reset_by rst_null);

	rule relayUartIn;
		Bit#(8) d <- uart.user.get;
		main.serial_rx(d);
	endrule
	rule relllll;
		let d <- main.serial_tx;
		uart.user.send(d);
	endrule


	method Bit#(1) ftdi_txd;
		return uart.serial_txd;
	endmethod
	method Action ftdi_rx(Bit#(1) ftdi_rxd);
		uart.serial_rx(ftdi_rxd);
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
