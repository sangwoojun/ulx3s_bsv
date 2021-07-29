////////////////////////////////////////////////////////////////////////////////
// Sang-Woo Jun, 2021
////////////////////////////////////////////////////////////////////////////////
// Implements simplified floating point operations for Lattice ECP5
// Fractions are truncated to most significant 18 bits, 
// for efficiency with the 18x18D multipliers on the ECP5
// Subnormal numbers are ignored
// NaN, Inf, etc are all ignored
////////////////////////////////////////////////////////////////////////////////




package SimpleFloat;

import FIFO::*;
import FloatingPoint::*;
import Mult18x18D::*;

interface FloatTwoOp;
	method Action put(Float a, Float b);
	method ActionValue#(Float) get;
endinterface



module mkFloatMult(FloatTwoOp);
	Mult18x18DIfc mult18 <- mkMult18x18D;
	FIFO#(Tuple3#(Bit#(1),Bit#(9),Bool)) signExpZeroQ <- mkSizedFIFO(6);
	FIFO#(Bit#(32)) outQ <- mkFIFO;
	rule procMultResult;
		Bit#(36) mres <- mult18.get;
		signExpZeroQ.deq;
		Bit#(1) sign = tpl_1(signExpZeroQ.first); 
		Bit#(9) expsum = tpl_2(signExpZeroQ.first); 
		Bool isZero = tpl_3(signExpZeroQ.first);
		Bit#(18) newfrac;
		Bit#(8) newexp;
		if ( mres[35] != 0 ) begin
			newfrac = truncate(mres>>17);
			newexp = truncate(expsum-126);
		end else begin
			newfrac = truncate(mres>>16);
			newexp = truncate(expsum-127);
		end

		
		if ( isZero ) outQ.enq(0);
		else outQ.enq({sign,newexp,newfrac,0});
	endrule
	method Action put(Float a, Float b);
		Bit#(32) bina = pack(a);
		Bit#(32) binb = pack(b);
		Bit#(18) fraca = zeroExtend(bina[22:6])|(1<<17);
		Bit#(18) fracb = zeroExtend(binb[22:6])|(1<<17);
		mult18.put(fraca, fracb);
		Bit#(1) newsign = bina[31] ^ binb[31];
		Bit#(8) expa = bina[30:23];
		Bit#(8) expb = binb[30:23];
		Bool isZero = (expa==0)||(expb==0);
		Bit#(9) expsum = zeroExtend(bina[30:23])+zeroExtend(binb[30:23]);
		signExpZeroQ.enq(tuple3(newsign,expsum,isZero));
	endmethod
	method ActionValue#(Float) get;
		outQ.deq;
		return unpack(outQ.first);
	endmethod
endmodule

typedef struct {Bit#(18) frac;Bit#(8) expo;Bit#(1) sign;} FloatParts deriving (Bits,Eq);

module mkFloatAdd(FloatTwoOp);
	FIFO#(Tuple2#(Bit#(32),Bit#(32))) inQ <- mkFIFO;
	FIFO#(Tuple4#(Bool,Bit#(8),FloatParts,FloatParts)) inProcQ <- mkFIFO;
	FIFO#(Tuple3#(Bool,FloatParts,FloatParts)) calcQ <- mkFIFO;
	FIFO#(Tuple3#(Bit#(1),Bit#(8),Bit#(19))) normalizeQ <- mkFIFO;
	FIFO#(Tuple3#(Bit#(1),Bit#(8),Bit#(19))) normalizeQ1 <- mkFIFO;
	FIFO#(Tuple3#(Bit#(1),Bit#(8),Bit#(19))) normalizeQ2 <- mkFIFO;
	FIFO#(Tuple3#(Bit#(1),Bit#(8),Bit#(19))) normalizeQ3 <- mkFIFO;
	FIFO#(Tuple3#(Bit#(1),Bit#(8),Bit#(19))) normalizeQ4 <- mkFIFO;
	FIFO#(Bit#(32)) outQ <- mkFIFO;

	rule procIn;
		inQ.deq;
		let d_ = inQ.first;
		let bina = tpl_1(d_);
		let binb = tpl_2(d_);

		Bit#(18) fraca = zeroExtend(bina[22:6])|(1<<17);
		Bit#(18) fracb = zeroExtend(binb[22:6])|(1<<17);
		Bit#(8) expa = bina[30:23];
		Bit#(8) expb = binb[30:23];
		Bit#(1) signa = bina[31];
		Bit#(1) signb = binb[31];

		Bool alarger = ((expa>expb) || (expa==expb&&fraca>fracb));
		Bit#(8) expdiff = (expa>expb)?(expa-expb):(expb-expa);
		//Bit#(5) expshift = truncate(expdiff);
		//if ( expdiff > 18 ) expshift = 5'b11111;
		inProcQ.enq(tuple4(alarger,expdiff,
			FloatParts{frac:fraca, expo:expa, sign:signa},
			FloatParts{frac:fracb, expo:expb, sign:signb}
			));

	endrule
	rule calcFrac;
		inProcQ.deq;
		let d_ = inProcQ.first;
		Bool alarger = tpl_1(d_);
		Bit#(8) expshift = tpl_2(d_);
		let ta = (tpl_3(d_));
		let tb = (tpl_4(d_));
		let fraca = ta.frac;
		let fracb = tb.frac;
		let expa = ta.expo;
		let expb = tb.expo;
		let signa = ta.sign;
		let signb = tb.sign;
		fraca = (alarger?fraca:(fraca>>expshift));
		fracb = (alarger?(fracb>>expshift):fracb);
		calcQ.enq(tuple3(alarger,
			FloatParts{frac:fraca, expo:expa, sign:signa},
			FloatParts{frac:fracb, expo:expb, sign:signb}
			));
	endrule
	rule calcFrac2;
		calcQ.deq;
		let d_ = calcQ.first;
		Bool alarger = tpl_1(d_);
		let ta = (tpl_2(d_));
		let tb = (tpl_3(d_));
		let fraca = ta.frac;
		let fracb = tb.frac;
		let expa = ta.expo;
		let expb = tb.expo;
		let signa = ta.sign;
		let signb = tb.sign;
		Bit#(19) newfrac;
		Bit#(8) newexp = alarger?expa:expb;
		Bit#(1) newsign = alarger?signa:signb;
		if ( signa == signb ) begin
			newfrac = zeroExtend(fraca)+zeroExtend(fracb);
		end else begin
			newfrac = (fraca>fracb)?zeroExtend(fraca-fracb):zeroExtend(fracb-fraca);
		end

		normalizeQ.enq(tuple3(newsign,newexp,newfrac));
	endrule

	rule normalize;
		normalizeQ.deq;
		let d_ = normalizeQ.first;
		let newsign = tpl_1(d_);
		let newexp = tpl_2(d_);
		let newfrac = tpl_3(d_);
		
		if ( newfrac[18] == 1 ) begin
			newfrac = newfrac>>1;
			newexp = newexp + 1;
		end
		normalizeQ1.enq(tuple3(newsign,newexp, newfrac));
	endrule
	rule normalize1;
		normalizeQ1.deq;
		let d_ = normalizeQ1.first;
		let newsign = tpl_1(d_);
		let newexp = tpl_2(d_);
		let newfrac = tpl_3(d_);

		if ( newfrac[17:9] == 0 && newfrac != 0 ) begin
			newfrac = newfrac << 9;
			newexp = newexp - 9;
		end
		normalizeQ2.enq(tuple3(newsign,newexp, newfrac));
	endrule
	rule normalize2;
		normalizeQ2.deq;
		let d_ = normalizeQ2.first;
		let newsign = tpl_1(d_);
		let newexp = tpl_2(d_);
		let newfrac = tpl_3(d_);
		if ( newfrac[17:14] == 0 && newfrac != 0 ) begin
			newfrac = newfrac << 5;
			newexp = newexp - 5;
		end
		normalizeQ3.enq(tuple3(newsign,newexp, newfrac));
	endrule
	rule normalize3;
		normalizeQ3.deq;
		let d_ = normalizeQ3.first;
		let newsign = tpl_1(d_);
		let newexp = tpl_2(d_);
		let newfrac = tpl_3(d_);
		if ( newfrac[17:16] == 0 && newfrac != 0 ) begin
			newfrac = newfrac << 2;
			newexp = newexp - 2;
		end
		normalizeQ4.enq(tuple3(newsign,newexp, newfrac));
	endrule
	rule normalize4;
		normalizeQ4.deq;
		let d_ = normalizeQ4.first;
		let newsign = tpl_1(d_);
		let newexp = tpl_2(d_);
		let newfrac = tpl_3(d_);
		if ( newfrac[17] == 0 && newfrac != 0 ) begin
			newfrac = newfrac << 1;
			newexp = newexp - 1;
		end
		Bit#(17) newfrace = truncate(newfrac);
		outQ.enq({newsign,newexp,newfrace,0});
	endrule



	method Action put(Float a, Float b);
		Bit#(32) bina = pack(a);
		Bit#(32) binb = pack(b);
		inQ.enq(tuple2(bina,binb));

	endmethod
	method ActionValue#(Float) get;
		outQ.deq;
		return unpack(outQ.first);
	endmethod
endmodule

endpackage: SimpleFloat
