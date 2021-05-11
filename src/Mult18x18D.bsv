package Mult18x18D;

import FIFO::*;
import FIFOF::*;

interface Mult18x18DImportIfc;
	method Action puta(Bit#(18) puta);
	method Action putb(Bit#(18) putb);
	method Bit#(36) dataout;
endinterface

import "BVI" mult18x18d =
module mkMult18x18DImport#(Clock clk, Reset rstn) (Mult18x18DImportIfc);
	default_clock no_clock;
	default_reset no_reset;

	input_clock (clk) = clk;
	input_reset (rstn) = rstn;

	method dataout dataout;
	method puta(dataax) enable((*inhigh*) dataax_EN) reset_by(no_reset) clocked_by(clk);
	method putb(dataay) enable((*inhigh*) dataay_EN) reset_by(no_reset) clocked_by(clk);
	schedule (
		dataout, puta, putb
	) CF (
		dataout, puta, putb
	);
endmodule

interface Mult18x18DIfc;
	method Action put(Bit#(18) a, Bit#(18) b);
	method ActionValue#(Bit#(36)) get;
endinterface

module mkMult18x18D(Mult18x18DIfc);
	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;
	Mult18x18DImportIfc multin <- mkMult18x18DImport(curclk, currst);
	FIFOF#(Bit#(36)) outQ <- mkFIFOF;
	Wire#(Bit#(1)) validWire <- mkDWire(0);
	Reg#(Bit#(4)) validMap <- mkReg(0);
	rule enqValid;
		validMap <= (validMap<<1)|zeroExtend(validWire);
		if ( validMap[2] == 1 ) begin
			if( outQ.notFull ) outQ.enq(multin.dataout);
		end
	endrule


	Reg#(Bit#(3)) dataInFlightUp <- mkReg(0);
	Reg#(Bit#(3)) dataInFlightDn <- mkReg(0);
	method Action put(Bit#(18) a, Bit#(18) b) if ( dataInFlightUp-dataInFlightDn < 4 );
		multin.puta(a);
		multin.putb(b);
		validWire <= 1;
		dataInFlightUp <= dataInFlightUp + 1;
	endmethod
	method ActionValue#(Bit#(36)) get;
		outQ.deq;
		dataInFlightDn <= dataInFlightDn + 1;
		return outQ.first;
	endmethod
endmodule

endpackage: Mult18x18D
