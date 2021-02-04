import FIFO::*;
import Vector::*;
import BRAM::*;

interface BRAMSubWord4Ifc#(numeric type addrsz);
	// "bytes": 0 = 1 byte, 3 = 4 bytes
	method Action req(Bit#(addrsz) addr, Bit#(32) word, Bit#(2) bytes, Bool write);
	method ActionValue#(Bit#(32)) resp;
endinterface

function Bit#(32) genMask(Bit#(2) off, Bit#(2) bytes); // bytes starts at one, so 0 -> 1 byte
	Vector#(4,Bit#(8)) mask;
	for ( Integer i = 0; i < 4; i=i+1 ) begin
		if ( fromInteger(i) >= off && fromInteger(i) <= off+bytes ) mask[i] = 8'hff;
		else mask[i] = 0;
	end
	return {mask[3],mask[2],mask[1],mask[0]};
endfunction

module mkBRAMSubWord (BRAMSubWord4Ifc#(asz))
	provisos(
		Add#(sasz,2,asz)
	);
	BRAM2Port#(Bit#(sasz),Bit#(32)) mem <- mkBRAM2Server(defaultValue);
	FIFO#(Tuple4#(Bit#(asz),Bit#(32),Bit#(2),Bool)) reqQ <- mkFIFO;
	FIFO#(Bit#(2)) readOffsetQ <- mkFIFO;

	rule doWrite;
		let r = reqQ.first;
		reqQ.deq;
		let d <- mem.portA.response.get;
		let addr = tpl_1(r);
		let data = tpl_2(r);
		let bytes = tpl_3(r);
		let write = tpl_4(r);
		if (!write) begin
			
			mem.portB.request.put(BRAMRequest{write:False,responseOnWrite:False,address:truncate(addr>>2),datain:?});
			//$write( "Reading %x\n", addr>>2 );
			readOffsetQ.enq(truncate(addr));
		end else begin
			Bit#(2) woff = truncate(addr);
			Bit#(5) woffe = zeroExtend(woff);
			Bit#(32) wdat = (data<<(8*woffe));
			Bit#(32) mask = genMask(woff, bytes);
			Bit#(32) odat = d & (~mask);
			Bit#(32) ndat = wdat | odat;
			mem.portB.request.put(BRAMRequest{write:True,responseOnWrite:False,address:truncate(addr>>2),datain:ndat});
			//$write( "Writing %x %x %x %x %x\n", addr>>2, d, data, ndat, mask );
		end
	endrule


	method Action req(Bit#(asz) addr, Bit#(32) word, Bit#(2) bytes, Bool write);
		reqQ.enq(tuple4(addr,word,bytes,write));
		mem.portA.request.put(BRAMRequest{write:False,responseOnWrite:False,address:truncate(addr>>2),datain:?});
	endmethod
	method ActionValue#(Bit#(32)) resp;
		let d <- mem.portB.response.get;
		Bit#(5) so = zeroExtend(readOffsetQ.first);
		readOffsetQ.deq;
		//$write("!~~ %x %x\n", d, so);
		return (d>>(so*8));
	endmethod
endmodule
