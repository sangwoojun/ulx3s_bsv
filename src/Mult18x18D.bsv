package Mult18x18D;

interface Mult18x18DIfc;
	method Action puta(Bit#(18) puta);
	method Action putb(Bit#(18) putbb);
	method Bit#(36) dataout;
endinterface

import "BVI" mult18x18d =
module mkMult18x18DImport#(Clock clk, Reset rstn) (Mult18x18DIfc);
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

endpackage: Mult18x18D
