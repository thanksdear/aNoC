`include "noc_params.vh"

// 输出端口模块：直通模式（可选添加输出FIFO）
module output_port(
    input  wire [`FLIT_WIDTH-1:0]   flit_from_xbar,
    input  wire                     flit_valid,

    output wire [`FLIT_WIDTH-1:0]   flit_out,
    output wire                     flit_out_valid
);

    // 简单直通模式
    assign flit_out = flit_from_xbar;
    assign flit_out_valid = flit_valid;

endmodule