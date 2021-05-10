module mult18x18d (dataout, dataax, dataay, clk, rstn);
	output [35:0] dataout;
	input [17:0] dataax, dataay;
	input clk,rstn;
	reg [35:0] dataout;
	reg [17:0] dataax_reg, dataay_reg;
	wire [35:0] dataout_node;
	reg [35:0] dataout_reg;
	always @(posedge clk or negedge rstn)
	begin
		if (!rstn)
		begin
			dataax_reg <= 0;
			dataay_reg <= 0;
		end
		else
		begin
			dataax_reg <= dataax;
			dataay_reg <= dataay;
		end
	end
	assign dataout_node = dataax_reg * dataay_reg;
	always @(posedge clk or negedge rstn)
	begin
		if (!rstn)
			dataout_reg <= 0;
		else
			dataout_reg <= dataout_node;
		end
	always @(posedge clk or negedge rstn)
	begin
		if (!rstn)
			dataout <= 0;
		else
			dataout <= dataout_reg;
	end
endmodule
