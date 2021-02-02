// import Common::*;
import Defines::*;
import Decode::*;
//import ALU::*;

typedef struct {
	IType           iType;
	RIndx   dst;
	Bool writeDst;
	Word            data;
	Word            addr;
	Word            nextPC;
} ExecInst deriving (Bits, Eq, FShow);


// ALU
///////////////////////////////////////////////////////////////////////////


function Word alu(Word a, Word b, AluFunc func);

	Word res = case (func)
		Add:    (a + b);
		Sub:    (a - b);
		And:    (a & b);
		Or:     (a | b);
		Xor:    (a ^ b);
		Slt:    (signedLT(a, b) ? 1 : 0);
		Sltu:   ((a < b) ? 1 : 0);
		Sll:    (a << b[4:0]);
		Srl:    (a >> b[4:0]);
		Sra:    signedShiftRight(a, b[4:0]);
	endcase;
	return res;
endfunction


function Bool aluBr(Word a, Word b, BrFunc brFunc);
	Bool res = case (brFunc)
		Eq:     (a == b);
		Neq:    (a != b);
		Lt:     signedLT(a, b);
		Ltu:    (a < b);
		Ge:     signedGE(a, b);
		Geu:    (a >= b);
		AT:     True;
		NT:     False;
	endcase;
	return res;
endfunction


function ExecInst exec( DecodedInst dInst, Word rVal1, Word rVal2, Word pc );
	let imm = dInst.imm;
	let brFunc = dInst.brFunc;
	let aluFunc = dInst.aluFunc;
	Word data = ?;
	Word nextPc = pc+4;
	Word addr = 0;
	case (dInst.iType) matches
		OP: begin data = alu(rVal1, rVal2, aluFunc); nextPc = pc+4; end
		OPIMM: begin data = alu(rVal1, imm, aluFunc); nextPc = pc+4; end
		BRANCH: begin nextPc = aluBr(rVal1, rVal2, brFunc) ? pc+imm : pc+4; end
		LUI: begin data = imm; end
		JAL: begin data = pc+4; nextPc = pc+imm; end
		JALR: begin data = pc+4; nextPc = (rVal1+imm) & ~1; end
		LOAD: begin addr = rVal1+imm; nextPc = pc+4; end
		STORE: begin data = rVal2; addr = rVal1+imm; nextPc = pc+4; end
		AUIPC: begin data = pc+imm; nextPc = pc+4; end
	endcase
	ExecInst eInst = ?;
	eInst.iType = dInst.iType;
	eInst.dst = dInst.dst;
	eInst.writeDst = dInst.writeDst;
	eInst.data = data;
	eInst.addr = addr;
	eInst.nextPC = nextPc;
	return eInst;
endfunction
