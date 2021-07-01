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
	FIFO#(Tuple3#(Bit#(8),Bit#(8),Bit#(16))) partialSumIdxQ2 <- mkSizedBRAMFIFO(256);
	FIFO#(Tuple3#(Bit#(8),Bit#(8),Bit#(16))) partialSumIdxQ1 <- mkFIFO;
	FIFO#(Float) partialSumQ <- mkSizedBRAMFIFO(256);
	FIFO#(Float) partialSumQ2 <- mkFIFO;

	Reg#(Bit#(8)) lastInputIdx <- mkReg(0);
	Reg#(Bit#(8)) curOutputIdx <- mkReg(zeroExtend(peIdx));
	Reg#(Bit#(128)) curMacIdx <- mkReg(0);


	Reg#(Bit#(32)) procStartCycle <- mkReg(0);
	Reg#(Bit#(32)) procCnt <- mkReg(0);

	rule enqMac;
		inputQ.deq;
		Float inf = tpl_1(inputQ.first);
		Bit#(8) ini = tpl_2(inputQ.first);
		weightQ.deq;
		Float wf = weightQ.first;
		//if ( peIdx == fromInteger(0) ) begin
		//	lastInputIdx <= lastInputIdx + 1;
		//	$write( "ini: %d\n", ini );
		//	$write( "curOutputIdx: %d\n", curOutputIdx );
		//	$write( "curMacIdx: %d\n", (curMacIdx>>5) );
		//	$write( "cnt: %d\n", lastInputIdx );
		//end

		partialSumIdxQ1.enq(tuple3(ini,curOutputIdx,truncate(curMacIdx>>8)));
		if ( (curMacIdx + 1)>>8 >= fromInteger(inputDim) ) begin
			curMacIdx <= 0;
			let nextOutIdx = curOutputIdx + fromInteger(valueOf(PeWays));
			if ( nextOutIdx >= fromInteger(outputDim) ) begin
				curOutputIdx <= zeroExtend(peIdx);
			end else begin
				curOutputIdx <= curOutputIdx + fromInteger(valueOf(PeWays));
			end
		end else begin
			if ( (curOutputIdx + fromInteger(valueOf(PeWays))) >= fromInteger(outputDim) ) begin
				curOutputIdx <= zeroExtend(peIdx);
				curMacIdx <= curMacIdx + 1;
			end else begin
				curMacIdx <= curMacIdx + 1;
				curOutputIdx <= curOutputIdx + fromInteger(valueOf(PeWays));
			end
		end
		fmult.put(inf, wf);

		if ( procStartCycle == 0 ) procStartCycle <= cycleCount;
		procCnt <= procCnt + 1;

		if ( (procCnt & 32'h1ffff) == 32'h1ffff ) begin
			Bit#(32) procCycles = cycleCount - procStartCycle;
			Bit#(32) dutyCycle = procCycles/procCnt;
			$write( "PE %d -- OPs: %d Cycles: %d -> %d Cycles per OP\n", peIdx, procCnt, procCycles, dutyCycle );
		end

		
		if ( curMacIdx < 256 ) begin
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
	rule filterDoneResults;
		partialSumIdxQ2.deq;
		let psi = partialSumIdxQ2.first;
		partialSumQ.deq;
		let ps = partialSumQ.first;
		if (tpl_3(psi)+1 == fromInteger(inputDim) ) begin
			outputQ.enq(tuple3(ps, tpl_1(psi), tpl_2(psi)));
			//$write( "Row done %d %d\n", tpl_1(psi), tpl_2(psi) );
		end else begin
			partialSumQ2.enq(ps);
		end
	endrule

	Reg#(Tuple2#(Float,Bit#(8))) inputReplicateReg <- mkReg(?);
	Reg#(Bit#(8)) inputReplicateCnt <- mkReg(0);
	Reg#(Bit#(32)) cnt <- mkReg(0);
	Reg#(Bit#(32)) cnt_t <- mkReg(0);

	FIFO#(Float) weightInQ <- mkFIFO(); //mkSizedBRAMFIFO(4096)
	FIFO#(Float) weightStoreQ <- mkSizedBRAMFIFO(5);
	FIFO#(Tuple2#(Float,Bit#(8))) inputInQ <- mkFIFO(); //mkSizedBRAMFIFO(65536)
	rule relayInputIn;
		if ( inputReplicateCnt == 0 ) begin
			inputInQ.deq;
			inputQ.enq(inputInQ.first);
			inputReplicateReg <= inputInQ.first;
			inputReplicateCnt <= 3;
		end else begin
			inputReplicateCnt <= inputReplicateCnt - 1;
			inputQ.enq(inputReplicateReg);
		end
	endrule
	rule relayWeightIn;
		if ( cnt_t == 0 ) begin
			if ( cnt + 1 >= fromInteger(4) ) begin
				cnt <= 0;
				cnt_t <= cnt_t + 1;
				weightInQ.deq;
				weightQ.enq(weightInQ.first);
				weightStoreQ.enq(weightInQ.first);
			end else begin
				cnt <= cnt + 1;
				weightInQ.deq;
				weightQ.enq(weightInQ.first);
				weightStoreQ.enq(weightInQ.first);
			end
		end else begin
			if ( cnt_t + 1 >= fromInteger(64) ) begin
				if ( cnt + 1 >= fromInteger(4) ) begin
					cnt <= 0;
					cnt_t <= 0;
					weightStoreQ.deq;
					weightQ.enq(weightStoreQ.first);
				end else begin
					cnt <= cnt + 1;
					weightStoreQ.deq;
					weightQ.enq(weightStoreQ.first);
				end
			end else begin
				if ( cnt + 1 >= fromInteger(4) ) begin
					cnt <= 0;
					cnt_t <= cnt_t + 1;
					weightStoreQ.deq;
					weightQ.enq(weightStoreQ.first);
					weightStoreQ.enq(weightStoreQ.first);
				end else begin
					cnt <= cnt + 1;
					weightStoreQ.deq;
					weightQ.enq(weightStoreQ.first);
					weightStoreQ.enq(weightStoreQ.first);
				end
			end
		end
	endrule
	method Action putInput(Float v, Bit#(8) input_idx);
		inputInQ.enq(tuple2(v,input_idx));
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

module mkNnFc(NnFcIfc);
	Vector#(PeWays, MacPeIfc) pes;
	Vector#(PeWays, FIFO#(Float)) weightInQs <- replicateM(mkFIFO);
	Vector#(PeWays, FIFO#(Tuple2#(Float,Bit#(8)))) dataInQs  <- replicateM(mkFIFO);
	Vector#(PeWays, FIFO#(Tuple3#(Float,Bit#(8),Bit#(8)))) resultOutQs  <- replicateM(mkFIFO);

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
			Bit#(PeWaysLog) target_w = truncate(weightInIdx);
			if ( target_w == fromInteger(i) ) begin
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


	FIFO#(Float) testQ <- mkFIFO;
	Reg#(Bit#(16)) weightcntcheck <- mkReg(0);
	Reg#(Bit#(16)) inputcntcheck <- mkReg(0);
	method Action dataIn(Float value, Bit#(8) input_idx);
		dataInQs[0].enq(tuple2(value,input_idx));
		//$write( "Input cnt: %d\n", inputcntcheck );
		inputcntcheck <= inputcntcheck + 1;
	endmethod
	method Action weightIn(Float weight);
		weightInQs[0].enq(weight);
		//$write( "weight cnt: %d\n", weightcntcheck );
		weightcntcheck <= weightcntcheck + 1;
	endmethod
	method ActionValue#(Tuple3#(Float, Bit#(8), Bit#(8))) dataOut;
		resultOutQs[0].deq;
		return resultOutQs[0].first;
	endmethod
endmodule
