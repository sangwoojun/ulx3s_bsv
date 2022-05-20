import Connectable::*;
import FIFO::*;
import FIFOF::*;
import Vector::*;
import SimpleFloat::*;
import FloatingPoint::*;

typedef 33 ZfpComprTypeSz; // e = 9, block = bit_budget(5)*4 = 20, flag = (0 or 1)*4 = 4
typedef TSub#(ZfpComprTypeSz,9) CompressedBitsTotal;
typedef TDiv#(CompressedBitsTotal,4) CompressedBitsEach;
typedef TDiv#(TSub#(CompressedBitsTotal,4),4) BitBudget;

Integer total = 33;
Integer compressed_total = total - 9;
Integer compressed_each = compressed_total/4;
Integer budget = compressed_each - 1;

interface ZfpCompressIfc;
	method Action put(Bit#(32) data);
	method ActionValue#(Bit#(ZfpComprTypeSz)) get;
endinterface

function Bit#(32) int_to_uint(Bit#(32) t);
    return (t + 32'haaaaaaaa) ^ 32'haaaaaaaa;
endfunction

function Bit#(32) intShift(Bit#(32) t);
    Bit#(1) s;
    s = t[31];
    t = t >> 1;
    t[31] = s;
    return t;
endfunction

(* synthesize *)
module mkZfpCompress (ZfpCompressIfc);

	FIFO#(Bit#(32)) inputQ <- mkFIFO;
	
	FIFO#(Vector#(4,Bit#(32))) toLift_1 <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) toLift_2 <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) toLift_3 <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) toLift_4 <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) toConvertBits <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) toEncode <- mkFIFO;
	
	FIFO#(Bit#(9)) eQ <- mkSizedFIFO(32);
	FIFO#(Bit#(CompressedBitsTotal)) toGetResult <- mkFIFO;
	FIFO#(Bit#(ZfpComprTypeSz)) outputQ <- mkFIFO;
	
	Reg#(Bit#(3)) inputCnt <- mkReg(0);
	Reg#(Bit#(8)) expMax <- mkReg(0);
	Vector#(4,Reg#(Bit#(32))) inputBuffer <- replicateM(mkReg(0));
	rule getMaxExp;
		inputQ.deq;
		let d = inputQ.first;
		Vector#(4,Bit#(32)) in = replicate(0);
		Vector#(4,Bit#(32)) idata = replicate(0);
		Bit#(8) matrixExp = 0;
		Bit#(9) e = 0;
	
		if ( inputCnt ==  fromInteger(4) ) begin
			for ( Integer i = 0; i < 4; i = i + 1 ) begin
				in[i] = inputBuffer[i];
			end
			inputBuffer[0] <= d;
			inputCnt <= 1;
			
			e = zeroExtend(expMax) + fromInteger(127);

			for ( Integer i = 0; i < 4; i = i + 1 ) begin
				idata[i] = in[i] << ((32-2) - expMax);
			end

			matrixExp = truncateLSB(d<<1);
			expMax <= matrixExp;
			toLift_1.enq(idata);
			eQ.enq(e);
		end else begin
			matrixExp = truncateLSB(d<<1);

			if ( inputCnt == fromInteger(0) ) begin
				expMax <= matrixExp;
			end else begin
				if ( matrixExp > expMax ) expMax <= matrixExp;
			end

			inputBuffer[inputCnt] <= d;
			inputCnt <= inputCnt + 1;
		end
	endrule

	rule lift;
		toLift_1.deq;
		let in = toLift_1.first;
		in[0] = (in[0]+in[3]); in[0] = intShift(in[0]); in[3] = (in[3]-in[0]);
		in[2] = (in[2]+in[1]); 
		toLift_2.enq(in);
	endrule
	rule lift_2;
		toLift_2.deq;
		let in = toLift_2.first;
		in[2] = intShift(in[2]); in[1] = (in[1]-in[2]);
		in[0] = (in[0]+in[2]); in[0] = intShift(in[0]);
		toLift_3.enq(in);
	endrule
	rule lift_3;
		toLift_3.deq;
		let in = toLift_3.first;
		in[2] = (in[2]-in[0]);
		in[3] = (in[3]+in[1]); in[3] = intShift(in[3]); in[1] = (in[1]-in[3]);
		toLift_4.enq(in);
	endrule
	rule lift_4;
		toLift_4.deq;
		let in = toLift_4.first;
		in[3] = (in[3]+ intShift(in[1])); in[1] = (in[1] - (intShift(in[3])));
		toConvertBits.enq(in);
	endrule
	
	rule convertBits;
		toConvertBits.deq;
		Vector#(4,Bit#(32)) in = toConvertBits.first;
		for (Bit#(5)i = 0; i < 4; i = i + 1) begin
			in[i] = int_to_uint(in[i]);
		end
		toEncode.enq(in);
	endrule

	rule encode;
		toEncode.deq;
		Vector#(4,Bit#(32)) udata = toEncode.first;
		Vector#(4,Bit#(32)) udataCand_1 = replicate(0);
		Vector#(4,Bit#(32)) udataCand_2 = replicate(0);
		Bit#(CompressedBitsTotal) out = 0;
		
		for ( Bit#(5) i = 0; i < 4; i = i + 1 ) begin
			udataCand_1[i] = udata[i]>>((32-4)-budget);
		end

		for ( Bit#(5) i = 0; i < 4; i = i + 1 ) begin
			udataCand_2[i] = udata[i]>>(32-budget);
		end

		for ( Integer i = 0; i < 4; i = i+1 ) begin
			if ( (udata[i]>>28) == 0 ) begin
				out[i*compressed_each] = 0;
				out[budget+(i*compressed_each):(i*compressed_each)+1] = udataCand_1[i][4:0];
			end else begin
				out[i*compressed_each] = 1;
				out[budget+(i*compressed_each):(i*compressed_each)+1] = udataCand_2[i][4:0];
			end
		end
		toGetResult.enq(out);
	endrule

	rule getResult;
		toGetResult.deq;
		eQ.deq;
		Bit#(CompressedBitsTotal) d = toGetResult.first;
		Bit#(9) e = eQ.first;
		Bit#(ZfpComprTypeSz) comp = 0;

		comp[8:0] = e;
		comp[(total-1):9] = d;

		outputQ.enq(comp);
	endrule

	method Action put(Bit#(32) data);
		inputQ.enq(data);
	endmethod
	method ActionValue#(Bit#(ZfpComprTypeSz)) get;
		outputQ.deq;
		return outputQ.first;
	endmethod
endmodule
