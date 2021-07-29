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

interface Mult18x18DBSIMIfc;
	method Action puta(Bit#(18) puta);
	method Action putb(Bit#(18) putb);
	method ActionValue#(Bit#(36)) dataout;
endinterface
module mkMult18x18DBSIM(Mult18x18DBSIMIfc);
	FIFO#(Bit#(18)) aQ <- mkSizedFIFO(4);
	FIFO#(Bit#(18)) bQ <- mkSizedFIFO(4);
	method Action puta(Bit#(18) a);
		aQ.enq(a);
	endmethod
	method Action putb(Bit#(18) b);
		bQ.enq(b);
	endmethod
	method ActionValue#(Bit#(36)) dataout;
		aQ.deq;
		bQ.deq;
		return zeroExtend(aQ.first)*zeroExtend(bQ.first);
	endmethod
endmodule

interface Mult18x18DIfc;
	method Action put(Bit#(18) a, Bit#(18) b);
	method ActionValue#(Bit#(36)) get;
endinterface


module mkMult18x18D(Mult18x18DIfc);
	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;
`ifdef BSIM
	Mult18x18DBSIMIfc multin <- mkMult18x18DBSIM();
`else
	Mult18x18DImportIfc multin <- mkMult18x18DImport(curclk, currst);
`endif
	FIFOF#(Bit#(36)) outQ <- mkSizedFIFOF(4);
	Wire#(Bit#(1)) validWire <- mkDWire(0);
	Reg#(Bit#(4)) validMap <- mkReg(0);
	Wire#(Bit#(18)) wireA <- mkDWire(0);
	Wire#(Bit#(18)) wireB <- mkDWire(0);
	rule enqValid;

`ifdef BSIM
		if ( validWire != 0 ) begin
			multin.puta(wireA);
			multin.putb(wireB);
		end
`else
		multin.puta(wireA);
		multin.putb(wireB);
`endif

		validMap <= (validMap<<1)|zeroExtend(validWire);
		if ( validMap[2] == 1 ) begin
`ifdef BSIM
			let outd <- multin.dataout;
`else
			let outd = multin.dataout;
`endif
			if( outQ.notFull ) outQ.enq(outd);
		end
	endrule


	Reg#(Bit#(3)) dataInFlightUp <- mkReg(0);
	Reg#(Bit#(3)) dataInFlightDn <- mkReg(0);
	method Action put(Bit#(18) a, Bit#(18) b) if ( dataInFlightUp-dataInFlightDn < 5 );
		wireA <= a;
		wireB <= b;
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
