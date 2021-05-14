package Sdram;

import FIFO::*;
import FIFOF::*;
import Vector::*;


// TODO clock either needs to be shifted, or commands need to be held for longer



import "BDPI" function Action bdpiWriteSdram(Bit#(32) addr, Bit#(32) data);
import "BDPI" function ActionValue#(Bit#(32)) bdpiReadSdram(Bit#(32) addr);

function Bit#(2) extract_bank_address(Bit#(24) data);
	return data[10:9];
endfunction

(* always_enabled, always_ready *)
interface Ulx3sSdramPinsIfc;
	//output sdram_csn,       // chip select
	(* prefix = "", result = "sdram_csn" *)
	method Bit#(1) sdram_csn();
	interface Clock sdram_clk;

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


typedef enum {IDLE, REFRESH1, REFRESH2, CONFIG, RDWR, READREADY, WAIT} ControllerState deriving (Eq,Bits);
Bit#(4) command_NOP  = 4'b1000;
Bit#(4) command_PRECHARGE = 4'b0001;
Bit#(4) command_AUTOREFRESH = 4'b0100;
Bit#(4) command_MODESET = 4'b0000;
Bit#(4) command_READ = 4'b0110;
Bit#(4) command_WRITE   = 4'b0010;
Bit#(4) command_ACTIVATE  = 4'b0101;

Bit#(4) delay_tRP = 3;
Bit#(4) delay_tMRD = 2;
Bit#(4) delay_tRCD = 3;
Bit#(4) delay_tRC = 9;
Bit#(4) delay_CL = 3;

Bit#(13) addr_MODE = 13'b000_1_00_011_0_000;


module mkUlx3sSdram#(Clock sdram_clk, Integer clock_mhz) (Ulx3sSdramIfc);
	Clock curclk <- exposeCurrentClock;

	FIFOF#(Bit#(16)) readRespQ <- mkFIFOF;
	FIFOF#(Tuple3#(Bit#(24),Bit#(16), Bool)) reqQ <- mkFIFOF;

	Integer init_cycles = 100 * clock_mhz;
	Integer rf_cycles  =   clock_mhz * 78 / 10;


	Reg#(Bit#(4)) command_out <- mkReg(command_NOP);
	// 11 during init, 00 after
	Reg#(Bit#(2)) dqm <- mkReg(2'b11);
	Reg#(Bit#(13)) addr_out <- mkReg(0);


	Reg#(ControllerState) state <- mkReg(IDLE);
	Reg#(ControllerState) state_next <- mkReg(IDLE);

`ifndef BSIM
	Inout16Ifc xx_inout16_XX <- mkInout16(curclk);
`endif

	Reg#(Bit#(16)) counter <- mkReg(0);
	// wait for chip to finish command
	Reg#(Bit#(4)) delay <- mkReg(0);

	Reg#(Bool) cur_cmd_isRead <- mkReg(False);
	Reg#(Bit#(24)) cur_cmd_address <- mkReg(0);
	Reg#(Bit#(16)) cur_cmd_wdata <- mkReg(0);

	Reg#(Bit#(4)) open_bank <- mkReg(0);
	Reg#(Vector#(4,Bit#(13))) open_rows <- mkReg(replicate(0));

	// wait for SDRAM chip to init
	rule init( dqm != 0 && state == IDLE );
		if ( counter + 1 >= fromInteger(init_cycles) ) begin
			counter <= 0;
			state <= REFRESH1;
		end else counter <= counter + 1;
	endrule

	rule controllerFSM ( state != IDLE || dqm == 0 );
		// wait until we have to refresh again
		if ( state == REFRESH2 ) counter <= 0;
		else counter <= counter + 1;

		case (state)
			IDLE: begin
				if ( counter >= fromInteger(rf_cycles) ) state <= REFRESH1;
				else if ( reqQ.notEmpty ) begin
					reqQ.deq;
					let r = reqQ.first;
					let raddr = tpl_1(r);
					let wdata = tpl_2(r);
					cur_cmd_address <= raddr;
					cur_cmd_wdata <= wdata;
					cur_cmd_isRead <= !tpl_3(r);
					state <= RDWR;
				end
			end
			RDWR: begin
				Bit#(2) bank = extract_bank_address(cur_cmd_address);
				Bit#(13) row = cur_cmd_address[23:11];
				Bit#(9) col = cur_cmd_address[8:0];
				//$write( "Sdram rdwr" );

				if ( open_bank[bank] == 0 ) begin
					command_out <= command_ACTIVATE;
					addr_out <= row;
					open_bank[bank] <= 1;
					open_rows[bank] <= row;
					delay <= delay_tRCD -2;
					state_next <= RDWR;
					state <= WAIT;
					//TODO FIXME: mark prev bank closed
				end else if ( open_rows[bank] != row ) begin
					command_out <= command_PRECHARGE;
					addr_out[10] <= 0;
					open_bank[bank] <= 0; // TODO I don't think it has to be closed?
					delay <= delay_tRP-2;
					state_next <= RDWR;
					state <= WAIT;
				end else begin
					if ( cur_cmd_isRead ) command_out <= command_READ;
					else command_out <= command_WRITE;
					addr_out <= {0,col};
					delay <= delay_CL-1; 
					state <= WAIT;
					if ( cur_cmd_isRead ) begin
						state_next <= READREADY;
						//$write( "Read\n" );
					end else begin
						//$write( "Write\n" );
						state_next <= IDLE;
`ifndef BSIM
						xx_inout16_XX.write(cur_cmd_wdata);
`else
						bdpiWriteSdram(zeroExtend(cur_cmd_address), zeroExtend(cur_cmd_wdata));
`endif
					end
				end
			end
			REFRESH1: begin
				command_out <= command_PRECHARGE;
				delay <= delay_tRP-2;
				addr_out[10] <= 1;
				open_bank <= 0;
				if ( dqm != 0 ) state_next <= CONFIG;
				else state_next <= REFRESH2;
				state <= WAIT;

				//$write( "Sdram refresh1\n" );
				//$fflush();
			end
			REFRESH2: begin
				command_out <= command_AUTOREFRESH;
				dqm <= 0;
				delay <= delay_tRC-2;

				if ( dqm != 0 ) state_next <= REFRESH2; // repeat again
				else state_next <= IDLE;
				state <= WAIT;
				//$write( "Sdram refresh2\n" );
			end
			CONFIG: begin
				command_out <= command_MODESET;
				addr_out <= addr_MODE;
				delay <= delay_tMRD-2;
				state_next <= REFRESH2;
				state <= WAIT;
				//$write( "Sdram config\n" );
			end
			READREADY: begin
				if ( readRespQ.notFull ) begin
`ifndef BSIM
					let d = xx_inout16_XX.read;
					readRespQ.enq(d);
`else
					let d <- bdpiReadSdram(zeroExtend(cur_cmd_address));
					readRespQ.enq(truncate(d));
`endif
					//$write( "Read data %x\n", d );
					state <= IDLE;
				end
			end
			WAIT: begin
				if ( delay != 0 ) delay <= delay - 1;
				else state <= state_next;
			end
		endcase
	endrule






`ifndef BSIM
	interface Ulx3sSdramPinsIfc pins;
		interface sdram_clk = sdram_clk;
		method Bit#(1) sdram_csn();
			return command_out[3];
		endmethod
		method Bit#(1) sdram_wen();
			return command_out[2];
		endmethod
		method Bit#(1) sdram_rasn();
			return command_out[1];
		endmethod
		method Bit#(1) sdram_casn();
			return command_out[0];
		endmethod
		method Bit#(2) sdram_dqm();
			return dqm;
		endmethod
		method Bit#(13) sdram_a();
			return addr_out;
		endmethod
		method Bit#(2) sdram_ba();
			Bit#(2) bank = extract_bank_address(cur_cmd_address);
			
			if ( state == CONFIG ) return 0;
			else return bank;
		endmethod
		interface sdram_d = xx_inout16_XX.inout_pins;
	endinterface
`endif

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
module mkInout16#(Clock curclk) (Inout16Ifc);
	default_clock no_clock;
	default_reset no_reset;
	
	input_clock (clk) = curclk;

	ifc_inout inout_pins(inout_pins);

	method write(write_data) enable(write_req) clocked_by(curclk);
	method read_data read;

	schedule (
		write, read
	) CF (
		write, read
	);
endmodule

endpackage: Sdram
