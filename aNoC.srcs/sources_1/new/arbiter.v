//对于一个通道输入请求，包含了五个输入通道对一个输出通道的请求，
//RC得到的是一个输入通道想去哪一个输出通道，比如input0输出是00010，input1也是00010
//输出通道1的req需要重组为00011，
//也就是req_input_0[4]、req_input_0[3]、req_input_0[2]、req_input_1[1]、req_input_0[1]
//输出结果是通过哪一个input
module arbiter
(
	input	clk,
	input	rst_n,
	input  [4:0] 	reqs,
	output [4:0] 	gnts
);

reg [4:0]  pointer_reqs;

wire [4:0]  req_masked;
wire [4:0]  mask_higher_pri_regs;
wire [4:0]	get_masked;
assign req_masked = pointer_reqs & reqs;
assign mask_higher_pri_regs[4:1] =  mask_higher_pri_regs[3:0] | req_masked[3:0];
assign mask_higher_pri_regs[0]	= 0;
assign get_masked = req_masked & ~mask_higher_pri_regs;

wire [4:0]  unmask_higher_pri_regs;
wire [4:0]	get_unmasked;
assign unmask_higher_pri_regs[4:1] =  unmask_higher_pri_regs[3:0] | reqs[3:0];
assign unmask_higher_pri_regs[0]	= 0;
assign get_unmasked = reqs & ~unmask_higher_pri_regs;

wire no_req_masked;
assign no_req_masked = ~(|req_masked);
assign	gnts = ({5{no_req_masked}} & get_unmasked) | get_masked;

always@(posedge clk or negedge rst_n)
	if(!rst_n)
		pointer_reqs <=  5'b11111;
	else begin
		if(|req_masked) pointer_reqs <= mask_higher_pri_regs;
		else if(|reqs) pointer_reqs <= unmask_higher_pri_regs;
		else pointer_reqs <= pointer_reqs;
	end

endmodule