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

interface ZfpDecompressIfc;
	method Action put(Bit#(ZfpComprTypeSz) data);
	method ActionValue#(Bit#(32)) get;
endinterface

function Bit#(9) get_e(Bit#(ZfpComprTypeSz) buffer);
	Bit#(9) e = 0;
	e = truncate(buffer);
	return e;
endfunction
function Bit#(CompressedBitsTotal) get_d(Bit#(ZfpComprTypeSz) buffer);
	Bit#(CompressedBitsTotal) d = 0;
	d = truncateLSB(buffer);
	return d;
endfunction
function Bit#(32) uint_to_int(Bit#(32) t);
	Bit#(32) d = 32'haaaaaaaa;
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

	FIFO#(Bit#(ZfpComprTypeSz)) inputQ <- mkFIFO;
	FIFO#(Bit#(9)) eQ <- mkFIFO;
	
	FIFO#(Vector#(4,Bit#(32))) udataQ <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) toUnblock_1 <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) toUnblock_2 <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) toUnblock_3 <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) toUnblock_4 <- mkFIFO;
	FIFO#(Vector#(4,Bit#(32))) toConvertNega <- mkFIFO;
	
	FIFO#(Bit#(1)) signQ <- mkSizedFIFO(20);
	FIFO#(Bit#(32)) toGetResult <- mkFIFO;
	FIFO#(Bit#(32)) outputQ <- mkFIFO;

	rule decompFirst;
		inputQ.deq;
		Bit#(9) e = get_e(inputQ.first);
		Bit#(CompressedBitsTotal) comprTotal = get_d(inputQ.first);
		
		Bit#(TMul#(CompressedBitsEach,3)) toSecondStep = truncateLSB(comprTotal);
		Bit#(TMul#(CompressedBitsEach,2)) toThirdStep = truncateLSB(comprTotal);
		Bit#(CompressedBitsEach) toFourthStep = truncateLSB(comprTotal);

		Bit#(CompressedBitsEach) comprFirst = truncate(comprTotal);
		Bit#(CompressedBitsEach) comprSecond = truncate(toSecondStep);
		Bit#(CompressedBitsEach) comprThird = truncate(toThirdStep);
		Bit#(CompressedBitsEach) comprFourth = truncate(toFourthStep);

		Bit#(1) flagFirst = truncate(comprFirst);
		Bit#(1) flagSecond = truncate(comprSecond);
		Bit#(1) flagThird = truncate(comprThird);
		Bit#(1) flagFourth = truncate(comprFourth);

		Bit#(BitBudget) comprFirstDataTmp = truncateLSB(comprFirst);
		Bit#(BitBudget) comprSecondDataTmp = truncateLSB(comprSecond);
		Bit#(BitBudget) comprThirdDataTmp = truncateLSB(comprThird);
		Bit#(BitBudget) comprFourthDataTmp = truncateLSB(comprFourth);

		Bit#(32) comprFirstData = zeroExtend(comprFirstDataTmp);
		Bit#(32) comprSecondData = zeroExtend(comprSecondDataTmp);
		Bit#(32) comprThirdData = zeroExtend(comprThirdDataTmp);
		Bit#(32) comprFourthData = zeroExtend(comprFourthDataTmp);

		Bit#(32) udataFirst = 0;
		Bit#(32) udataSecond = 0;
		Bit#(32) udataThird = 0;
		Bit#(32) udataFourth = 0;

		Vector#(4,Bit#(32)) udata = replicate(0);

		if ( flagFirst == 0 ) begin
			udataFirst = comprFirstData << (32 - valueof(BitBudget) - 4);
			udata[0] = udataFirst;
		end else begin
			udataFirst = comprFirstData << (32 - valueof(BitBudget));
			udata[0] = udataFirst;
		end
		if ( flagSecond == 0 ) begin
			udataSecond = comprSecondData << (32 - valueof(BitBudget) - 4);
			udata[1] = udataSecond;
		end else begin
			udataSecond = comprSecondData << (32 - valueof(BitBudget));
			udata[1] = udataSecond;
		end
		if ( flagThird == 0 ) begin
			udataThird = comprThirdData << (32 - valueof(BitBudget) - 4);
			udata[2] = udataThird;
		end else begin
			udataThird = comprThirdData << (32 - valueof(BitBudget));
			udata[2] = udataThird;
		end
		if ( flagFourth == 0 ) begin
			udataFourth = comprFourthData << (32 - valueof(BitBudget) - 4);
			udata[3] = udataFourth;
		end else begin
			udataFourth = comprFourthData << (32 - valueof(BitBudget));
			udata[3] = udataFourth;
		end

		eQ.enq(e);
		udataQ.enq(udata);
	endrule
	
	rule convert;
		udataQ.deq;
		Vector#(4,Bit#(32)) d = udataQ.first;
		for (Bit#(3) i = 0; i < 4; i = i + 1) begin
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
	
	Reg#(Bit#(2)) convertNegaCycle <- mkReg(0);
	Vector#(4,Reg#(Bit#(32))) convertNegaBuffer <- replicateM(mkReg(0));
	rule convertNega;
		if ( convertNegaCycle == 0 ) begin
			toConvertNega.deq;
			Vector#(4,Bit#(32)) d = toConvertNega.first;
			Bit#(1) sign = 0;
			if ( d[0][31] == 1 ) begin
				d[0] = -d[0];
				sign = 1;
			end else begin
				sign = 0;
			end
			for ( Bit#(3) i = 0; i < 4; i = i+1 ) begin
				convertNegaBuffer[i] <= d[i];
			end
			convertNegaCycle <= convertNegaCycle + 1;
			toGetResult.enq(d[0]);
			signQ.enq(sign);
		end else begin
			let i = convertNegaCycle;
			let d = convertNegaBuffer[i];
			Bit#(1) sign = 0;
			if (d[31] == 1) begin
				d = -d;
				sign = 1;
			end else begin
				sign = 0;
			end
			if ( i == 3 ) convertNegaCycle <= 0;
			else convertNegaCycle <= convertNegaCycle + 1;
			toGetResult.enq(d);
			signQ.enq(sign);
		end
	endrule
	
	Reg#(Bit#(9)) eBuffer <- mkReg(0);
	Reg#(Bit#(2)) getResultCycle <- mkReg(0);
	rule getResult;
		toGetResult.deq;
		signQ.deq;
		if ( getResultCycle == 0 ) begin
			eQ.deq;
			let e = eQ.first;
			eBuffer <= e;
			Bit#(9) expMax = e - 127;
			//$write("%d\n", expMax);
			Bit#(32) d = toGetResult.first;
			Bit#(32) decomp = 0;
			Bit#(32) tmp = 0;
			Bit#(1) sign = signQ.first;
		
			if ( expMax == fromInteger(385) ) begin
				//$write("came in to zero case\n");
				tmp = d >> (127 + (32 - 2));
				decomp[30:0] = tmp[30:0];
				decomp[31] = sign;
				//Float value = unpack(decomp[i]);
				//$write("%d\n", value);
				//$write("sign bit is %d\n", sign[i]);
			end else begin
				if ( expMax < 30 ) begin
					//$write("came in to normal case_1\n");
					tmp = d >> ((32 - 2) - expMax);
					decomp[30:0] = tmp[30:0];
					decomp[31] = sign;
					//Float value = unpack(decomp[i]);
					//$write("%d\n", value);
					//$write("sign bit is %d\n", sign[i]);
				end else begin
					//$write("came in to normal case_2\n");
					tmp = d << (expMax - (32 - 2));
					decomp[30:0] = tmp[30:0];
					decomp[31] = sign;
					//Float value = unpack(decomp[i]);
					//$write("%d\n", value);
				end
			end
			getResultCycle <= getResultCycle + 1;
			outputQ.enq(decomp);
		end else begin
			let e = eBuffer;
			Bit#(9) expMax = e - 127;
			//$write("%d\n", expMax);
			Bit#(32) d = toGetResult.first;
			Bit#(32) decomp = 0;
			Bit#(32) tmp = 0;
			Bit#(1) sign = signQ.first;
		
			if ( expMax == fromInteger(385) ) begin
				//$write("came in to zero case\n");
				tmp = d >> (127 + (32 - 2));
				decomp[30:0] = tmp[30:0];
				decomp[31] = sign;
				//Float value = unpack(decomp[i]);
				//$write("%d\n", value);
				//$write("sign bit is %d\n", sign[i]);
			end else begin
				if ( expMax < 30 ) begin
					//$write("came in to normal case_1\n");
					tmp = d >> ((32 - 2) - expMax);
					decomp[30:0] = tmp[30:0];
					decomp[31] = sign;
					//Float value = unpack(decomp[i]);
					//$write("%d\n", value);
					//$write("sign bit is %d\n", sign[i]);
				end else begin
					//$write("came in to normal case_2\n");
					tmp = d << (expMax - (32 - 2));
					decomp[30:0] = tmp[30:0];
					decomp[31] = sign;
					//Float value = unpack(decomp[i]);
					//$write("%d\n", value);
				end
			end
			if ( getResultCycle == 3 ) getResultCycle <= 0;
			else getResultCycle <= getResultCycle + 1;
			outputQ.enq(decomp);
		end
	endrule
	
	method Action put(Bit#(ZfpComprTypeSz) data);
		inputQ.enq(data);
	endmethod
	method ActionValue#(Bit#(32)) get;
		outputQ.deq;
		return outputQ.first;
	endmethod
endmodule
