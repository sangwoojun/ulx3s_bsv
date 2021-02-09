import Defines::*;

typedef enum { OP, OPIMM, BRANCH, LUI, JAL, JALR, LOAD, STORE, AUIPC, Unsupported} IType deriving (Bits, Eq, FShow);
typedef enum {Eq, Neq, Lt, Ltu, Ge, Geu, AT, NT} BrFunc deriving (Bits, Eq, FShow);
typedef enum {Add, Sub, And, Or, Xor, Slt, Sltu, Sll, Srl, Sra, Mul} AluFunc deriving (Bits, Eq, FShow);
typedef enum {ImmI, ImmS, ImmB, ImmU, ImmJ, NoImm} ImmType deriving (Bits, Eq, FShow);

// Opcode
Bit#(7) opOpImm  = 7'b0010011;
Bit#(7) opOp     = 7'b0110011;
Bit#(7) opLui    = 7'b0110111;
Bit#(7) opJal    = 7'b1101111;
Bit#(7) opJalr   = 7'b1100111;
Bit#(7) opBranch = 7'b1100011;
Bit#(7) opLoad   = 7'b0000011;
Bit#(7) opStore  = 7'b0100011;
Bit#(7) opAuipc  = 7'b0010111;
Bit#(7) opSystem = 7'b1110011;

// funct3 - ALU
Bit#(3) fnADD   = 3'b000;
Bit#(3) fnSLL   = 3'b001;
Bit#(3) fnSLT   = 3'b010;
Bit#(3) fnSLTU  = 3'b011;
Bit#(3) fnXOR   = 3'b100;
Bit#(3) fnSR    = 3'b101;
Bit#(3) fnOR    = 3'b110;
Bit#(3) fnAND   = 3'b111;
// funct3 - Branch
Bit#(3) fnBEQ   = 3'b000;
Bit#(3) fnBNE   = 3'b001;
Bit#(3) fnBLT   = 3'b100;
Bit#(3) fnBGE   = 3'b101;
Bit#(3) fnBLTU  = 3'b110;
Bit#(3) fnBGEU  = 3'b111;
// funct3 - Load
Bit#(3) fnLW    = 3'b010;
Bit#(3) fnLB    = 3'b000;
Bit#(3) fnLH    = 3'b001;
Bit#(3) fnLBU   = 3'b100;
Bit#(3) fnLHU   = 3'b101;
// funct3 - Store
Bit#(3) fnSW    = 3'b010;
Bit#(3) fnSB    = 3'b000;
Bit#(3) fnSH    = 3'b001;
// funct3 - Multiply
Bit#(3) fnMUL   = 3'b000;
// funct3 - CSR
Bit#(3) fnCSRRS = 3'b010;


typedef struct {
	IType iType;
	AluFunc aluFunc;
	BrFunc brFunc;
	Bool writeDst;
	RIndx dst;
	RIndx src1;
	RIndx src2;
	Word imm;
	SizeType size;
	Bool extendSigned;
} DecodedInst deriving (Bits, Eq, FShow);

function DecodedInst decode(Bit#(32) inst);
	let opcode = inst[6:0];
	let funct3 = inst[14:12];
	let funct7 = inst[31:25];
	let dst     = inst[11:7];
	let src1    = inst[19:15];
	let src2    = inst[24:20];
	let csr    = inst[31:20];

	Word immI = signExtend(inst[31:20]);
	Word immS = signExtend({ inst[31:25], inst[11:7] });
	Word immB = signExtend({ inst[31], inst[7], inst[30:25], inst[11:8], 1'b0});
	Word immU = signExtend({ inst[31:12], 12'b0 });
	Word immJ = signExtend({ inst[31], inst[19:12], inst[20], inst[30:21], 1'b0});

	DecodedInst dInst = ?;
	dInst.iType = Unsupported;
	dInst.dst = 0;
	dInst.writeDst = False;
	dInst.src1 = 0;
	dInst.src2 = 0;
	case(opcode)
		opOp: begin
			if (funct7 == 7'b0000000) begin
				case (funct3)
					fnADD:  dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: src2, imm: ?, brFunc: ?, aluFunc: Add,  iType: OP, size: ?, extendSigned: ? };
				fnSLT:  dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: src2, imm: ?, brFunc: ?, aluFunc: Slt,  iType: OP, size: ?, extendSigned: ? };
				fnSLTU: dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: src2, imm: ?, brFunc: ?, aluFunc: Sltu, iType: OP, size: ?, extendSigned: ? };
				fnXOR:  dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: src2, imm: ?, brFunc: ?, aluFunc: Xor,  iType: OP, size: ?, extendSigned: ? };
				fnOR:   dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: src2, imm: ?, brFunc: ?, aluFunc: Or,   iType: OP, size: ?, extendSigned: ? };
				fnAND:  dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: src2, imm: ?, brFunc: ?, aluFunc: And,  iType: OP, size: ?, extendSigned: ? };
				fnSLL:  dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: src2, imm: ?, brFunc: ?, aluFunc: Sll,  iType: OP, size: ?, extendSigned: ? };
				fnSR:   dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: src2, imm: ?, brFunc: ?, aluFunc: Srl,  iType: OP, size: ?, extendSigned: ? };
				endcase
			end else if (funct7 == 7'b0100000) begin
				case (funct3)
					fnADD:  dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: src2, imm: ?, brFunc: ?, aluFunc: Sub,  iType: OP, size: ?, extendSigned: ? };
					fnSR:   dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: src2, imm: ?, brFunc: ?, aluFunc: Sra,  iType: OP, size: ?, extendSigned: ? };
				endcase
			end
			else if (funct7 == 7'b0000001) begin
				//case (funct3)
				// case fnMUL: 
				//endcase
			end
		end
		opOpImm: begin
			case (funct3)
				fnADD:  dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: 0, imm: immI, brFunc: ?, aluFunc: Add,  iType: OPIMM, size: ?, extendSigned: ? };
				fnSLT:  dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: 0, imm: immI, brFunc: ?, aluFunc: Slt,  iType: OPIMM, size: ?, extendSigned: ? };
				fnSLTU: dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: 0, imm: immI, brFunc: ?, aluFunc: Sltu, iType: OPIMM, size: ?, extendSigned: ? };
				fnXOR:  dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: 0, imm: immI, brFunc: ?, aluFunc: Xor,  iType: OPIMM, size: ?, extendSigned: ? };
				fnOR:   dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: 0, imm: immI, brFunc: ?, aluFunc: Or,   iType: OPIMM, size: ?, extendSigned: ? };
				fnAND:  dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: 0, imm: immI, brFunc: ?, aluFunc: And,  iType: OPIMM, size: ?, extendSigned: ? };
				fnSLL:  begin
					if (funct7 == 7'b0000000) begin
						dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: 0, imm: immI, brFunc: ?, aluFunc: Sll, iType: OPIMM, size: ?, extendSigned: ? };
					end
				end
				fnSR: begin
					if (funct7 == 7'b0000000) begin
						dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: 0, imm: immI, brFunc: ?, aluFunc: Srl, iType: OPIMM, size: ?, extendSigned: ? };
					end else if (funct7 == 7'b0100000) begin
						dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: 0, imm: immI, brFunc: ?, aluFunc: Sra, iType: OPIMM, size: ?, extendSigned: ? };
					end
				end
			endcase
		end
		opBranch: begin
			case(funct3)
				fnBEQ:  dInst = DecodedInst { dst: 0, writeDst: False, src1: src1, src2: src2, imm: immB, brFunc: Eq,  aluFunc: ?, iType: BRANCH, size: ?, extendSigned: ? };
				fnBNE:  dInst = DecodedInst { dst: 0, writeDst: False, src1: src1, src2: src2, imm: immB, brFunc: Neq, aluFunc: ?, iType: BRANCH, size: ?, extendSigned: ? };
				fnBLT:  dInst = DecodedInst { dst: 0, writeDst: False, src1: src1, src2: src2, imm: immB, brFunc: Lt,  aluFunc: ?, iType: BRANCH, size: ?, extendSigned: ? };
				fnBGE:  dInst = DecodedInst { dst: 0, writeDst: False, src1: src1, src2: src2, imm: immB, brFunc: Ge,  aluFunc: ?, iType: BRANCH, size: ?, extendSigned: ? };
				fnBLTU: dInst = DecodedInst { dst: 0, writeDst: False, src1: src1, src2: src2, imm: immB, brFunc: Ltu, aluFunc: ?, iType: BRANCH, size: ?, extendSigned: ? };
				fnBGEU: dInst = DecodedInst { dst: 0, writeDst: False, src1: src1, src2: src2, imm: immB, brFunc: Geu, aluFunc: ?, iType: BRANCH, size: ?, extendSigned: ? };
			endcase
		end
		opLui:  dInst = DecodedInst { dst: dst, writeDst: True, src1: 0,   src2: 0, imm: immU, brFunc: ?, aluFunc: ?, iType: LUI, size: ?, extendSigned: ? };
		opJal:  dInst = DecodedInst { dst: dst, writeDst: True, src1: 0,   src2: 0, imm: immJ, brFunc: ?, aluFunc: ?, iType: JAL, size: ?, extendSigned: ? };
		opJalr: dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: 0, imm: immI, brFunc: ?, aluFunc: ?, iType: JALR, size: ?, extendSigned: ? };
		opLoad: begin
			case (funct3)
			fnLW: dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: 0, imm: immI, brFunc: ?, aluFunc: ?, iType: LOAD, size:3, extendSigned: ? };
			fnLH: dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: 0, imm: immI, brFunc: ?, aluFunc: ?, iType: LOAD, size:1, extendSigned: True };
			fnLB: dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2: 0, imm: immI, brFunc: ?, aluFunc: ?, iType: LOAD, size:0, extendSigned: True };
			fnLHU: dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2:0, imm: immI, brFunc: ?, aluFunc: ?, iType: LOAD, size:1, extendSigned: False };
			fnLBU: dInst = DecodedInst { dst: dst, writeDst: True, src1: src1, src2:0, imm: immI, brFunc: ?, aluFunc: ?, iType: LOAD, size:0, extendSigned: False };
			endcase
		end
		opStore: begin
			case (funct3)
				fnSW: dInst = DecodedInst { dst: 0, writeDst: False, src1: src1, src2: src2, imm: immS, brFunc: ?, aluFunc: ?, iType: STORE, size: 3, extendSigned: ? };
				fnSH: dInst = DecodedInst { dst: 0, writeDst: False, src1: src1, src2: src2, imm: immS, brFunc: ?, aluFunc: ?, iType: STORE, size: 1, extendSigned: ? };
				fnSB: dInst = DecodedInst { dst: 0, writeDst: False, src1: src1, src2: src2, imm: immS, brFunc: ?, aluFunc: ?, iType: STORE, size: 0, extendSigned: ? };
			endcase
		end

		opAuipc: dInst = DecodedInst { dst: dst, writeDst: True, src1: 0,   src2: 0, imm: immU, brFunc: ?, aluFunc: ?, iType: AUIPC, size:?, extendSigned: ? };
	endcase
	return dInst;
endfunction
