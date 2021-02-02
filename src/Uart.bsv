import FIFO::*;

import "BDPI" function ActionValue#(Bit#(32)) bdpiUartGet(Bit#(8) idx);
import "BDPI" function Action bdpiUartPut(Bit#(32) data);

interface UartUserIfc;
	method Action send(Bit#(8) word);
	method ActionValue#(Bit#(8)) get;
endinterface
interface UartIfc;
	interface UartUserIfc user;

	(* always_ready *)
	method Bit#(1) serial_txd;
	(* always_enabled, always_ready, prefix = "", result = "serial_rxd" *)
	method Action serial_rx(Bit#(1) serial_rxd);
endinterface

module mkUart_bsim(UartUserIfc);
	FIFO#(Bit#(8)) inQ <- mkFIFO;
	FIFO#(Bit#(8)) outQ <- mkFIFO;
	Reg#(Bit#(8)) outCnt <- mkReg(0);
	Reg#(Bit#(8)) inReqId <- mkReg(0);
	rule relayOut;
		let d <- bdpiUartGet(inReqId);
		Bit#(8) data = truncate(d);
		Bit#(8) flg = truncate(d>>8);
		if ( flg == 0 ) begin
			inReqId <= inReqId + 1;
			outQ.enq(data);
		end
	endrule
	rule relayIn;
		inQ.deq;
		let d = inQ.first;
		outCnt <= outCnt + 1;
		bdpiUartPut({0,outCnt,d});
	endrule

	method Action send(Bit#(8) word);
		inQ.enq(word);
	endmethod
	method ActionValue#(Bit#(8)) get;
		outQ.deq;
		return outQ.first;
	endmethod
endmodule
	//Reg#(Bit#(16)) clkdiv <- mkReg(5000); // 48,000,000 / 9600


/*******
	Parameters: 
		clkdiv_ = clock hz / baud. e.g. 48MHz -> 48,000,000 / 9600 = 5000

		Terminal: 
		8 bits, no parity, 1 stop bit, no flow control
*******/


module mkUart#(Integer clkdiv_) (UartIfc);

	FIFO#(Bit#(8)) outQ <- mkFIFO;
	FIFO#(Bit#(8)) inQ <- mkFIFO;
	Bit#(16) clkdiv = fromInteger(clkdiv_);
	//Reg#(Bit#(16)) clkdiv <- mkReg(5000); // 48,000,000 / 9600
	Reg#(Bit#(16)) clkcnt <- mkReg(0);

	Reg#(Bit#(1)) txdr <- mkReg(1);
	Reg#(Bit#(11)) curoutd <- mkReg(0);
	Reg#(Bit#(5)) curoutoff <- mkReg(0);
	rule outcntclk;
		if ( clkcnt + 1 >= clkdiv ) begin
			clkcnt <= 0;

			if ( curoutoff != 0 ) begin
				curoutd <= {1,curoutd[10:1]};
				txdr <= curoutd[0];
				curoutoff <= curoutoff - 1;
			end else begin
				inQ.deq;
				let word = inQ.first;
				curoutd <= {2'b11,word,1'b0};
				curoutoff <= 11;
			end
		end else begin
			clkcnt <= clkcnt + 1;
		end
	endrule

	Wire#(Bit#(1)) inw <- mkDWire(1);
	Reg#(Bit#(16)) samplecountdown <- mkReg(0);
	Reg#(Bit#(4)) bleft <- mkReg(0);
	Reg#(Bit#(8)) outword <- mkReg(0);
	rule insample;
		if ( bleft == 0 && inw == 0 ) begin
			bleft <= (8+1);
			samplecountdown <= (clkdiv*6)/4;
		end
		else if ( bleft != 0 ) begin
			if ( samplecountdown != 0 ) begin
				samplecountdown <= samplecountdown - 1;
			end else begin
				samplecountdown <= clkdiv;
				outword <= {inw,outword[7:1]};
				bleft <= bleft - 1;
				if ( bleft == 1 ) begin
					outQ.enq(outword);
				end
			end
		end
	endrule





	Reg#(Bit#(4)) rxin <- mkReg(4'b1111);
	interface UartUserIfc user;
		method Action send(Bit#(8) word);// if ( curoutoff == 0 );
			inQ.enq(word);
			//curoutd <= {2'b11,word,1'b0};
			//curoutoff <= 11;
		endmethod
		method ActionValue#(Bit#(8)) get;
			outQ.deq;
			return outQ.first;
		endmethod
	endinterface
	method Bit#(1) serial_txd;
		return txdr;
	endmethod
	method Action serial_rx(Bit#(1) serial_rxd);
		rxin <= {serial_rxd,rxin[3:1]};
		inw <= (rxin==0)?0:1;
	endmethod
endmodule
