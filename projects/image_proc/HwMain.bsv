import Clocks :: *;
import Vector::*;
import FIFO::*;
import BRAM::*;
import BRAMFIFO::*;
import Uart::*;
import Sdram::*;

interface HwMainIfc;
	method ActionValue#(Bit#(8)) serial_tx;
	method Action serial_rx(Bit#(8) rx);
endinterface

module mkHwMain#(Ulx3sSdramUserIfc mem) (HwMainIfc);
	Clock curclk <- exposeCurrentClock;
	Reset currst <- exposeCurrentReset;

	FIFO#(Bit#(8)) serialrxQ <- mkFIFO;
	FIFO#(Bit#(8)) serialtxQ <- mkFIFO;

	FIFO#(Bit#(8)) rowbufferQ1 <- mkSizedBRAMFIFO(512);
	FIFO#(Bit#(8)) rowbufferQ2 <- mkSizedBRAMFIFO(512);

	rule relayRow1;
		serialrxQ.deq;
		let pix = serialrxQ.first;
		rowbufferQ1.enq(pix);
	endrule

	rule relayRow2;
		rowbufferQ1.deq;
		let pix = rowbufferQ1.first;
		rowbufferQ2.enq(pix);
	endrule

	rule relayRow3;
		rowbufferQ2.deq;
		let pix = rowbufferQ2.first;
		serialtxQ.enq(pix);
	endrule

	method ActionValue#(Bit#(8)) serial_tx;
		serialtxQ.deq;
		return serialtxQ.first();
	endmethod
	method Action serial_rx(Bit#(8) d);
		serialrxQ.enq(d);
	endmethod
endmodule
