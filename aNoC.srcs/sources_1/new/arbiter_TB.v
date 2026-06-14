`timescale 1ns/1ps
module arbiter_TB();

	reg 		clk;
	reg 		rst_n;
	reg	[4:0]	reqs;
	wire [4:0] 	gnts;	
	initial begin
		clk = 0;
		forever #5  clk = ~clk;
	end
	
	
	initial begin
		rst_n = 0;
		reqs = 5'b00000;
		#20	rst_n = 1;
		#10 reqs = 5'b00001;
		#10 reqs = 5'b00010;	
		#100;
		#10 reqs = 5'b11111;	
		#50 reqs = 5'b10101;		
		#30 reqs = 5'b01010;		
		#50 $finish;
		
	end

arbiter u_arbiter(
	.clk	(clk),
	.rst_n	(rst_n),
	.reqs	(reqs),
	.gnts	(gnts)
);
endmodule