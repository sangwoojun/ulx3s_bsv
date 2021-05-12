module pll_fastclk(
	input clki_25mhz, 
	output clk_25mhz,
	output clk_125mhz,
	output clk_100mhz,
	output lockedn
	);
wire clkfb;
wire locked;
assign lockedn = !locked;
(* ICP_CURRENT="12" *) (* LPF_RESISTOR="8" *) (* MFG_ENABLE_FILTEROPAMP="1" *) (* MFG_GMCREF_SEL="2" *)
EHXPLLL #(
		.PLLRST_ENA("DISABLED"),
		.INTFB_WAKE("DISABLED"),
		.STDBY_ENABLE("DISABLED"),
		.DPHASE_SOURCE("DISABLED"),
		.CLKOP_FPHASE(0),
		.CLKOP_CPHASE(0),
		.OUTDIVIDER_MUXA("DIVA"),
		.CLKOP_ENABLE("ENABLED"),
		.CLKOP_DIV(4),
		.CLKOS_ENABLE("ENABLED"),
		.CLKOS_DIV(5),
		.CLKOS_CPHASE(0),
		.CLKOS_FPHASE(0),
		.CLKOS2_ENABLE("ENABLED"),
		.CLKOS2_DIV(20),
		.CLKOS2_CPHASE(0),
		.CLKOS2_FPHASE(0),
		.CLKFB_DIV(10),
		.CLKI_DIV(1),
		.FEEDBK_PATH("INT_OP")
) pll_i (
	.CLKI(clki),
	.CLKFB(clkfb),
	.CLKINTFB(clkfb),
	.CLKOP(clk_125mhz),
	.CLKOS(clk_100mhz),
	.CLKOS2(clk_25mhz),
	.RST(1'b0),
	.STDBY(1'b0),
	.PHASESEL0(1'b0),
	.PHASESEL1(1'b0),
	.PHASEDIR(1'b0),
	.PHASESTEP(1'b0),
	.PLLWAKESYNC(1'b0),
	.ENCLKOP(1'b0),
	.LOCK(locked)
	);
endmodule

