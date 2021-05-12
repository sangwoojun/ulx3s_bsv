package PLL;

interface PLLIfc;
	interface Clock clk_125mhz;
	interface Clock clk_100mhz;
	interface Clock clk_25mhz;
	interface Reset rst_25mhz;
	interface Reset rst_125mhz;
	interface Reset rst_100mhz;
endinterface

import "BVI" pll_fastclk =
module mkPllFast#(Clock clk) (PLLIfc);
	default_clock no_clock;
	default_reset no_reset;

	input_clock (clki_25mhz) = clk;

	output_clock clk_25mhz(clk_25mhz);
	output_clock clk_125mhz(clk_125mhz);
	output_clock clk_100mhz(clk_100mhz);
	output_reset rst_25mhz(lockedn) clocked_by(clk_25mhz);
	output_reset rst_125mhz(lockedn) clocked_by(clk_125mhz);
	output_reset rst_100mhz(lockedn) clocked_by(clk_100mhz);
endmodule

endpackage: PLL
