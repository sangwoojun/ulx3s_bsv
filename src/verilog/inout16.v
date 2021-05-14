module inout16 (
	input wire clk,
	inout wire [15:0] inout_pins,

	input wire [15:0] write_data,
	output wire [15:0] read_data,
	input wire write_req
	);

	assign inout_pins = (write_req ? write_data : 16'hzzzz);
	assign read_data = (write_req ? 16'hxxxx : inout_pins);
endmodule
