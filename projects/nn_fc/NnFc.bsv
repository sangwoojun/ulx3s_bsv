import FIFO::*;
import FIFOF::*;
import Vector::*;
import BRAMFIFO::*;

import SimpleFloat::*;
import FloatingPoint::*;


interface MacPeIfc;
	method Action putInput(Float v, Bit#(8) input_idx);
	method Action putWeight(Float w);
	method ActionValue#(Tuple3#(Float, Bit#(8), Bit#(8))) resultGet;
	method Bool resultExist;
endinterface

typedef 4 PeWaysLog;
typedef TExp#(PeWaysLog) PeWays;

Integer inputDim = 1024;
Integer outputDim = 64;

module mkMacPe#(Bit#(PeWaysLog) peIdx) (MacPeIfc);
	Reg#(Bit#(32)) cycleCount <- mkReg(0);
	rule incCycleCount;
		cycleCount <= cycleCount + 1;
	endrule

	FIFO#(Float) weightQ <- mkFIFO;
	FIFO#(Tuple2#(Float,Bit#(8))) inputQ <- mkFIFO;
	FIFOF#(Tuple3#(Float, Bit#(8), Bit#(8))) outputQ <- mkFIFOF;


	FloatTwoOp fmult <- mkFloatMult;
	FloatTwoOp fadd <- mkFloatAdd;
	FIFO#(Float) addForwardQ <- mkSizedFIFO(4);
	FIFO#(Tuple3#(Bit#(8),Bit#(8),Bit#(16))) partialSumIdxQ3 <- mkFIFO1;
	FIFO#(Tuple3#(Bit#(8),Bit#(8),Bit#(16))) partialSumIdxQ2 <- mkSizedBRAMFIFO(128);
	FIFO#(Tuple3#(Bit#(8),Bit#(8),Bit#(16))) partialSumIdxQ1 <- mkFIFO1;
	FIFO#(Float) partialSumQ <- mkSizedBRAMFIFO(128);
	FIFO#(Float) partialSumQ2 <- mkFIFO;

	Reg#(Bit#(8)) lastInputIdx <- mkReg(0);
	Reg#(Bit#(8)) curOutputIdx <- mkReg(zeroExtend(peIdx));
	Reg#(Bit#(12)) curMacIdx <- mkReg(0);
	rule enqMac;
		inputQ.deq;
		Float inf = tpl_1(inputQ.first);
		Bit#(8) ini = tpl_2(inputQ.first);
		weightQ.deq;
		Float wf = weightQ.first;

		partialSumIdxQ1.enq(tuple3(ini,curOutputIdx,zeroExtend(curMacIdx)));
		if ( curMacIdx + 1 >= fromInteger(inputDim) ) begin
			curMacIdx <= 0;
			let nextOutIdx = curOutputIdx + fromInteger(valueOf(PeWays));
			if ( nextOutIdx >= fromInteger(outputDim) ) begin
				curOutputIdx <= zeroExtend(peIdx);
			end else begin
				curOutputIdx <= curOutputIdx + fromInteger(valueOf(PeWays));
			end
		end else begin
			curMacIdx <= curMacIdx + 1;
		end
		fmult.put(inf, wf);
		
		if ( curMacIdx == 0 ) begin
			addForwardQ.enq(unpack(0)); // float '0'
		end else begin
			partialSumQ2.deq;
			addForwardQ.enq(partialSumQ2.first);
		end
	endrule

	rule enqAdd;
		let mr <- fmult.get;
		fadd.put(mr,addForwardQ.first);
		addForwardQ.deq;
	endrule
		

	rule relayMacResult;
		let d <- fadd.get;
		partialSumQ.enq(d);
	endrule

	rule relayPartialIdx;
		partialSumIdxQ1.deq;
		partialSumIdxQ2.enq(partialSumIdxQ1.first);
	endrule
	rule relayPartialIdx2;
		partialSumIdxQ2.deq;
		partialSumIdxQ3.enq(partialSumIdxQ2.first);
	endrule
	rule filterDoneResults;
		partialSumIdxQ3.deq;
		let psi = partialSumIdxQ3.first;

		partialSumQ.deq;
		let ps = partialSumQ.first;
		if (tpl_3(psi)+1 == fromInteger(inputDim) ) begin
			outputQ.enq(tuple3(ps, tpl_1(psi), tpl_2(psi)));
			//$write( "Row done %d %d\n", tpl_1(psi), tpl_2(psi) );
		end else begin
			partialSumQ2.enq(ps);
		end
	endrule



	FIFO#(Float) weightInQ <- mkFIFO;
	rule relayWeightIn;
		weightInQ.deq;
		weightQ.enq(weightInQ.first);
	endrule
	method Action putInput(Float v, Bit#(8) input_idx);
		inputQ.enq(tuple2(v,input_idx));
	endmethod
	method Action putWeight(Float w);
		weightInQ.enq(w);
	endmethod
	method ActionValue#(Tuple3#(Float, Bit#(8), Bit#(8))) resultGet;
		outputQ.deq;
		return outputQ.first;
	endmethod
	method Bool resultExist;
		return outputQ.notEmpty;
	endmethod
endmodule



interface NnFcIfc;
	method Action dataIn(Float value, Bit#(8) input_idx);
	method Action weightIn(Float weight);
	method ActionValue#(Tuple3#(Float, Bit#(8), Bit#(8))) dataOut;
endinterface

(* synthesize *)
module mkNnFc(NnFcIfc);
	Vector#(PeWays, MacPeIfc) pes;
	Vector#(PeWays, FIFO#(Float)) weightInQs <- replicateM(mkFIFO1);
	Vector#(PeWays, FIFO#(Tuple2#(Float,Bit#(8)))) dataInQs  <- replicateM(mkFIFO1);
	Vector#(PeWays, FIFO#(Tuple3#(Float,Bit#(8),Bit#(8)))) resultOutQs  <- replicateM(mkFIFO1);

	for (Integer i = 0; i < valueOf(PeWays); i=i+1 ) begin
		pes[i] <- mkMacPe(fromInteger(i));

		Reg#(Bit#(16)) weightInIdx <- mkReg(0);
		rule forwardWeights;
			weightInQs[i].deq;
			let w = weightInQs[i].first;
			if ( i < valueOf(PeWays)-1 ) begin
				weightInQs[i+1].enq(w);
			end
		
			weightInIdx <= weightInIdx + 1;
			Bit#(PeWaysLog) target = truncate(weightInIdx);
			if ( target == fromInteger(i) ) begin
				//$write( "Weight in %d\n", target );
				pes[i].putWeight(w);
			end
		endrule
		rule forwardInput;
			dataInQs[i].deq;
			let d = dataInQs[i].first;
			if ( i < valueOf(PeWays)-1 ) begin
				dataInQs[i+1].enq(d);
			end
			pes[i].putInput(tpl_1(d), tpl_2(d));
		endrule
		rule forwardResult;
			if ( pes[i].resultExist ) begin
				let d <- pes[i].resultGet;
				resultOutQs[i].enq(d);
			end else if ( i < valueOf(PeWays)-1 ) begin
				resultOutQs[i+1].deq;
				resultOutQs[i].enq(resultOutQs[i+1].first);
			end
		endrule
	end


	method Action dataIn(Float value, Bit#(8) input_idx);
		dataInQs[0].enq(tuple2(value,input_idx));
	endmethod
	method Action weightIn(Float weight);
		weightInQs[0].enq(weight);
		//$write( "Received weight %x\n", weight );
	endmethod
	method ActionValue#(Tuple3#(Float, Bit#(8), Bit#(8))) dataOut;
		resultOutQs[0].deq;
		return resultOutQs[0].first;
	endmethod
endmodule
