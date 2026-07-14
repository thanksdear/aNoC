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
//找到reqmasked的最低位的1
assign mask_higher_pri_regs[0]	= 0;
assign mask_higher_pri_regs[4:1] =  mask_higher_pri_regs[3:0] | req_masked[3:0];
assign get_masked = req_masked & ~mask_higher_pri_regs;

wire [4:0]  unmask_higher_pri_regs;
wire [4:0]	get_unmasked;
//非掩码
assign unmask_higher_pri_regs[0]	= 0;
assign unmask_higher_pri_regs[4:1] =  unmask_higher_pri_regs[3:0] | reqs[3:0];

assign get_unmasked = reqs & ~unmask_higher_pri_regs;

wire no_req_masked;
assign no_req_masked = ~(|req_masked);
assign	gnts =  no_req_masked ? get_unmasked: get_masked;
//下一级掩码
wire [4:0] next_pointer_reqs;
assign next_pointer_reqs[0] = 1'b0;
assign next_pointer_reqs[4:1] = next_pointer_reqs[3:0] | gnts[3:0];

always@(posedge clk or negedge rst_n)begin
	if(!rst_n)
		pointer_reqs <=  5'b11111;
	else begin
		if(|req_masked) pointer_reqs <= ~next_pointer_reqs;
		else pointer_reqs <= pointer_reqs;
	end
end
endmodule