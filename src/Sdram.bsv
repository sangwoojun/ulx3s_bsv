package Sdram;

import FIFO::*;

(* always_enabled, always_ready *)
interface Ulx3sSdramPinsIfc;
	//output sdram_csn,       // chip select
	(* prefix = "", result = "sdram_csn" *)
	method Bit#(1) sdram_csn();
	//output sdram_clk,       // clock to SDRAM
	(* prefix = "", result = "sdram_clk" *)
	method Bit#(1) sdram_clk();
	//output sdram_cke,       // clock enable to SDRAM	
	(* prefix = "", result = "sdram_cke" *)
	method Bit#(1) sdram_cke();

	//output sdram_rasn,      // SDRAM RAS
	(* prefix = "", result = "sdram_rasn" *)
	method Bit#(1) sdram_rasn();

	//output sdram_casn,      // SDRAM CAS
	(* prefix = "", result = "sdram_casn" *)
	method Bit#(1) sdram_casn();

	//output sdram_wen,       // SDRAM write-enable
	(* prefix = "", result = "sdram_wen" *)
	method Bit#(1) sdram_wen();

	//output [12:0] sdram_a,  // SDRAM address bus
	(* prefix = "", result = "sdram_a" *)
	method Bit#(13) sdram_a();

	//output [1:0] sdram_ba,  // SDRAM bank-address
	(* prefix = "", result = "sdram_ba" *)
	method Bit#(2) sdram_ba();

	//output [1:0] sdram_dqm, // byte select
	(* prefix = "", result = "sdram_dqm" *)
	method Bit#(2) sdram_dqm();

	//inout [15:0] sdram_d,   // data bus to/from SDRAM	
	(* prefix = "XX_sdram_d_XX" *)
	interface Inout#(Bit#(16)) sdram_d;
endinterface

interface Ulx3sSdramUserIfc;
	method Action req(Bit#(24) addr, Bit#(16) data, Bool write);
	method ActionValue#(Bit#(16)) readResp;
endinterface

interface Ulx3sSdramIfc;
`ifndef BSIM
	(* prefix="" *)
	interface Ulx3sSdramPinsIfc pins;
`endif
	interface Ulx3sSdramUserIfc user;
endinterface


typedef enum {IDLE, REFRESH1, REFRESH2, CONFIG, RDWR, RWREADY, ACKWAIT, WAIT} ControllerState deriving (Eq,Bits);



(* synthesize *)
module mkUlx3sSdram (Ulx3sSdramIfc);
	FIFO#(Bit#(16)) readRespQ <- mkFIFO;
	FIFO#(Tuple3#(Bit#(24),Bit#(16), Bool)) reqQ <- mkFIFO;


	Reg#(ControllerState) state <- mkReg(IDLE);
	Reg#(Bit#(8)) delay <- mkReg(0);

	Inout16Ifc xx_inout16_XX <- mkInout16;

	rule controllerFSM;
		case (state)
			IDLE: begin
			end
			REFRESH1: begin
			end
			REFRESH2: begin
			end
			CONFIG: begin
			end
			RDWR: begin
			end
			RWREADY: begin
			end
			ACKWAIT: begin
			end
			WAIT: begin
			end
		endcase
	endrule








	interface Ulx3sSdramPinsIfc pins;
		method Bit#(2) sdram_dqm();
			return 0;
		endmethod
		interface sdram_d = xx_inout16_XX.inout_pins;
	endinterface
	interface Ulx3sSdramUserIfc user;
		method Action req(Bit#(24) addr, Bit#(16) data, Bool write);
			reqQ.enq(tuple3(addr,data,write));
		endmethod
		method ActionValue#(Bit#(16)) readResp;
			readRespQ.deq;
			return readRespQ.first;
		endmethod
	endinterface
endmodule

interface Inout16Ifc;
	interface Inout#(Bit#(16)) inout_pins;

	method Action write(Bit#(16) data);
	method Bit#(16) read;
endinterface

import "BVI" inout16 =
module mkInout16 (Inout16Ifc);
	default_clock no_clock;
	default_reset no_reset;

	ifc_inout inout_pins(inout_pins);

	method write(write_data) enable(write_req);
	method read_data read;
endmodule

endpackage: Sdram
