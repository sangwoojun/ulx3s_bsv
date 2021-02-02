typedef Bit#(32) Word;
typedef Bit#(5) RIndx;
typedef Bit#(2) SizeType;
typedef enum {Fetch, Decode, Execute, Writeback} ProcStage deriving (Eq,Bits);

typedef struct {
	Bit#(16) addr;
	Word word;
	SizeType bytes; // 1-index. value of 0 means 1 byte
	Bool write;
} MemReq32 deriving (Bits);

