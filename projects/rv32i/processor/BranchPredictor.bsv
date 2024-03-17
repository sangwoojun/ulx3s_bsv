import Vector::*;
import Defines::*;

interface BranchPredictorIfc;
	method Word getNextPc(Word curpc);
	method Action setPrediction(Word curpc, Word nextpc);
endinterface

typedef 4 TableSize;

module mkBranchPredictor(BranchPredictorIfc);
	Reg#(Vector#(TableSize, Bool)) bht <- mkReg(replicate(False));
	Reg#(Vector#(TableSize, Word)) btb <- mkReg(replicate(0));
	method Word getNextPc(Word curpc);
		Word r = curpc + 4;
		Bit#(TLog#(TableSize)) idx = truncate(curpc);
		if ( bht[idx] ) r = btb[idx];

		return curpc + 4;
	endmethod
	method Action setPrediction(Word curpc, Word nextpc);
		Bit#(TLog#(TableSize)) idx = truncate(curpc);
		bht[idx] <= True;
		btb[idx] <= nextpc;
	endmethod
endmodule
