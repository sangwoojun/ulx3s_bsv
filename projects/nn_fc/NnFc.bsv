import FIFO::*;
import FIFOF::*;
import Vector::*;

import SimpleFloat::*;
import FloatingPoint::*;
interface NnFcIfc;
	method Action dataIn(Float value, Bit#(8) input_idx);
	method ActionValue#(Tuple3#(Float, Bit#(8), Bit#(8))) dataOut;
endinterface

module mkNnFc(NnFcIfc);
	FIFO#(Float) testQ <- mkFIFO;
	method Action dataIn(Float value, Bit#(8) input_idx);
		testQ.enq(value);
	endmethod
	method ActionValue#(Tuple3#(Float, Bit#(8), Bit#(8))) dataOut;
		testQ.deq;
		return tuple3(testQ.first,0,0);
	endmethod
endmodule
