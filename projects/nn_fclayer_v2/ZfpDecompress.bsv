import Connectable::*;
import FIFO::*;
import FIFOF::*;
import Vector::*;

typedef 33 ZfpComprTypeSz; // e = 9, block = bit_budget(5)*4 = 20, flag = (0 or 1)*4 = 4
typedef Bit#(ZfpComprTypeSz) ZfpComprType;
typedef TSub#(ZfpComprTypeSz,9) CompressedBitsTotal;
typedef TDiv#(CompressedBitsTotal,4) CompressedBitsEach;
typedef TDiv#(TSub#(CompressedBitsTotal,4),4) BitBudget;

interface ZfpDecompressIfc;
	method Action put(ZfpComprType);
	method ActionValue#(Vector#(4,Bit#(32))) get;
endinterface

function Bit#(9) get_e(Bit#(ZfpComprTypeSz) buffer);
	Bit#(9) e = 0;
	e = truncate(buffer);
	return e;
endfunction
function Bit#(CompressedBitsTotal) get_d(Bit#(ZfpComprTypeSz) buffer);
	Bit#(CompressedBitsTotal) d = 0;
	e = truncateLSB(buffer);
	return e;
endfunction
function Bit#(32) uint_to_int(Bit#(32) t);
	Bit#(32) d = 64'haaaaaaaa;
	t = t ^ d;
	t = t - d;
	return t;
endfunction
function Bit#(32)intShiftR(Bit#(32) t);
	Bit#(1) s = t[31];
	t = t >> 1;
	t[31] = s;
	return t;
endfunction

(* synthesize *)
module mkZfpDecompress (ZfpDecompressIfc);

	FIFO#(ZfpComprType) inputQ <- mkFIFO;
	FIFO#(Bit#(32)) outputQ <- mkFIFO;
	FIFO#(Bit#(9)) eQ <- mkFIFO;
	FIFO#(Bit#(TMul#(CompressedBitsEach,3))) toDecompSecond <- mkFIFO;
	FIFO#(Bit#(TMul#(CompressedBitsEach,2))) toDecompThird <- mkFIFO;
	FIFO#(Bit#(CompressedBitsEach)) toDecompForth <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) udataQ <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) toUnblock_1 <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) toUnblock_2 <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) toUnblock_3 <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) toUnblock_4 <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) toConvertNega <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) signQ <- mkSizedFIFO(20);
	FIFO#(Vector#(4,Bit#(32))) toGetResult <- mkFIFO;

	Reg#(Bit(2)) inputCycle <- mkReg(0);	

	Vector#(4,Reg#(Bit#(32))) udata <- replicateM(mkReg(0));

	rule decompFirst(inputCycle == 0);
		inputQ.deq;
		Bit#(9) e = get_e(inputQ.first);
		Bit#(CompressedBitsTotal) comprTotal = get_d(inputQ.first);
		Bit#(TMul#(CompressedBitsEach,3)) toSecondStep = truncateLSB(comprTotal);
		Bit#(CompressedBitsEach) comprFirst = truncate(comprTotal);
		Bit#(1) flagFirst = truncate(comprFirst);
		Bit#(BitBudget) comprFirstData = truncateLSB(comprFirst);
		Bit#(32) udataFirst = 0;
		if ( flagFirst == 0 ) begin
			udataFirst = comprFirstData << (32 - BitBudget - 4);
			udata[0] <= udataFirst
		end else begin
			udataFirst = comprFirstData << (32 - BitBudget - 4);
			udata[0] <= udataFirst
		end
		inputCycle <= 1;
		eQ.enq(e);
		toDecompSecond.enq(toSecondStep);
	endrule
	
	rule decompSecond(inputCycle == 1);
		toDecompSecond.deq;
		let d = toDecompSecond.first;
		Bit#(TMul#(CompressedBitsEach,2)) toThirdStep = truncateLSB(d);
		Bit#(CompressedBitsEach) comprSecond = truncate(d);
		Bit#(1) flagSecond = truncate(comprSecond);
		Bit#(BitBudget) comprSecondData = truncateLSB(comprSecond);
		Bit#(32) udataSecond = 0;
		if ( flagSecond == 0 ) begin
			udataSecond = comprSecondData << (32 - BitBudget - 4);
			udata[1] <= udataSecond
		end else begin
			udata = comprFirstData << (32 - BitBudget - 4);
			udata[1] <= udataSecond
		end
		inputCycle <= 2;
		toDecompThird.enq(toThirdStep);
	endrule

	rule decompThird(inputCycle == 2);
		toDecompThird.deq;
		let d = toDecompThird.first;
		Bit#(CompressedBitsEach) toForthStep = truncateLSB(d);
		Bit#(CompressedBitsEach) comprThird = truncate(d);
		Bit#(1) flagThird = truncate(comprThird);
		Bit#(BitBudget) comprThirdData = truncateLSB(comprThird);
		Bit#(32) udataThird = 0;
		if ( flagThird == 0 ) begin
			udataThird = comprSecondData << (32 - BitBudget - 4);
			udata[2] <= udataThird
		end else begin
			udata = comprFirstData << (32 - BitBudget - 4);
			udata[2] <= udataThird
		end
		inputCycle <= 3;
		toDecompForth.enq(toForthStep);
	endrule

	rule decompForth(inputCycle == 3);
		toDecompForth.deq;
		let d = toDecompForth.first;
		Bit#(CompressedBitsEach) comprForth = truncate(d);
		Bit#(1) flagForth = truncate(comprThird);
		Bit#(BitBudget) comprForthData = truncateLSB(comprForth);
		Bit#(32) udataForth = 0;
		if ( flagForth == 0 ) begin
			udataForth = comprSecondData << (32 - BitBudget - 4);
			udata[3] <= udataForth
		end else begin
			udataForth = comprFirstData << (32 - BitBudget - 4);
			udata[3] <= udataForth
		end
		inputCycle <= 4;
	endrule
	
	rule gather_all(inputCycle == 4);
        	udataQ.enq(udata);
		inputCycle <= 0;
		for (Bit#(2) i = 0; i < 4; i = i + 1) begin
			udata[i] <= 0;
		end
	endrule
	
	rule convert;
		udataQ.deq;
		Vector#(4,Bit#(32)) d = udataQ.first;
		for (Bit#(2) i = 0; i < 4; i = i + 1) begin
			d[i] = uint_to_int(d[i]);
		end
		toUnblock_1.enq(d);
	endrule
	
	rule unblock_1;
		toUnblock_1.deq;
		Vector#(4,Bit#(32)) d = toUnblock_1.first;
		d[1] = d[1] + intShiftR(d[3]); d[3] = d[3] - intShiftR(d[1]);
		toUnblock_2.enq(d);
	endrule
	
	rule unblock_2;
		toUnblock_2.deq;
		Vector#(4,Bit#(32)) d = toUnblock_2.first;
		d[1] = d[1] + d[3]; d[3]= d[3] << 1; d[3] = d[3] - d[1];
		d[2] = d[2] + d[0]; d[0]= d[0] << 1; d[0] = d[0] - d[2];
		toUnblock_3.enq(d);
	endrule
	
	rule unblock_3;
		toUnblock_3.deq;
		Vector#(4,Bit#(32)) d = toUnblock_3.first;
		d[1] = d[1] + d[2]; d[2]= d[2] << 1; d[2] = d[2] - d[1];
		toUnblock_4.enq(d);
	endrule
	
	rule unblock_4;
		toUnblock_4.deq;
		Vector#(4,Bit#(32)) d = toUnblock_4.first;
		d[3] = d[3] + d[0]; d[0]= d[0] << 1; d[0] = d[0] - d[3];
		toConvertNega.enq(d);
	endrule
	
	rule convertNega;
		toConvertNega.deq;
		Vector#(4,Bit#(32)) d = toConvertNega.first;
		Vector#(4,Bit#(1)) sign = replicate(0);
		
		for (Bit#(4) i = 0; i < 4; i = i + 1) begin
			if (d[i][31] == 1) begin
				d[i] = -d[i];
				sign[i] = 1;
			end else begin
				sign[i] = 0;
			end
		end
		toGetResult.enq(d);
		signQ.enq(sign);
	endrule
	
	rule getResult;
		toGetResult.deq;
		signQ.deq;
		eQ.deq;

		let e = eQ.first;
		int expMax = e - 127;

		Vector#(4,Bit#(32)) d = toGetResult.first;
		Vector#(4,Bit#(32)) decomp = replicate(0);
		Vector#(4,Bit#(1)) sign = signQ.first;
		
		for (Bit#(4) i = 0; i < 4; i = i +1) begin
			decomp[i][30:0] = d[i] << (expMax - (32 -2));
			decomp[i][31] = sign[i];
			$display("out is %b ",decomp[i]);
		end
		outputQ.enq(decomp);
	endrule
	
	method Action put(Bit#(48) data);
		inputQ.enq(data);
	endmethod
	method ActionValue#(Vector#(4,Bit#(64))) get;
		outputQ.deq;
		return outputQ.first;
	endmethod
endmodule
