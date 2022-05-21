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

	Reg#(Bit#(32)) cycles <- mkReg(0);
	Reg#(Bit#(32)) cycleOutputStart <- mkReg(0);
	rule incCyclecount;
		cycles <= cycles + 1;
	endrule

	Reg#(Bit#(32)) cycleBegin <- mkReg(0);

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

	Reg#(Bit#(32)) pixOutCnt <- mkReg(0);
	method ActionValue#(Bit#(8)) serial_tx;
		if ( cycleOutputStart == 0 ) begin
			$write( "Impage processing latency: %d cycles\n", cycles - cycleBegin );
			cycleOutputStart <= cycles;
		end
		if ( pixOutCnt + 1 >= 512*256 ) begin
			$write( "Impage processing total cycles: %d\n", cycles - cycleBegin );
		end
		pixOutCnt <= pixOutCnt + 1;
		serialtxQ.deq;
		return serialtxQ.first();
	endmethod
	method Action serial_rx(Bit#(8) d);
		if ( cycleBegin == 0 ) cycleBegin <= cycles;
		serialrxQ.enq(d);
	endmethod
endmodule
