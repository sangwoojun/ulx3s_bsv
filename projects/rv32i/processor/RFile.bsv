import Vector::*;
import BRAM::*;
import RegFile::*;

typedef Bit#(32) Word;
typedef Bit#(5) RIndx;

// Register File

interface RFile2R1W;
    method Word rd1(RIndx rindx);
    method Word rd2(RIndx rindx);
    method Action wr(RIndx rindx, Word data);
    // simulation-only debugging method
    method Action displayRFileInSimulation;
endinterface

module mkRFile2R1W(RFile2R1W);
    Vector#(32, Reg#(Word)) rfile <- replicateM(mkReg(0));

    method Word rd1(RIndx rindx);
        return rfile[rindx];
    endmethod
    method Word rd2(RIndx rindx);
        return rfile[rindx];
    endmethod
    method Action wr(RIndx rindx, Word data);
        if (rindx != 0) begin
            rfile[rindx] <= data;
        end
    endmethod
    // simulation-only debugging method
    method Action displayRFileInSimulation;
        for (Integer i = 0 ; i < 32 ; i = i+1) begin
            $display("x%0d = 0x%x", i, rfile[i]);
        end
        $write("{x31, ..., x0} = 0x");
        for (Integer i = 31 ; i >= 0 ; i = i-1) begin
            $write("%x", rfile[i]);
        end
        $write("\n");
    endmethod
endmodule

// Memory
