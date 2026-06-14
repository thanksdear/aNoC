`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/13 13:36:29
// Design Name: 
// Module Name: FIFO
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
//异步FIFO，满信号是写时钟域跟同步后的读时钟域格雷码做比较
//空信号是读时钟域指针跟同步后的写时钟域格雷码做比较
//边写边读的时候，读信号至少晚三个周期，这是异步打了两拍导致的。
module FIFO #(
    parameter DATA_WIDTH = 8,       // 数据位宽
    parameter ADDR_WIDTH = 4,       // 地址位宽 (深度 = 2^ADDR_WIDTH)
    parameter DEPTH      = (1 << (ADDR_WIDTH)) -1     // FIFO 深度
    )(
 // Write Domain
    input   wire    wr_clk,
    input   wire    wr_rst_n,
    input   wire    wr_en,
    input   wire    [DATA_WIDTH-1:0] w_data,
    output  wire    full,

 // Read Domain
    input   wire    rd_clk,
    input   wire    rd_rst_n, 
    input   wire    rd_en,
    output  wire    [DATA_WIDTH-1:0] r_data,
    output  wire    empty    
    );
    wire [ADDR_WIDTH-1:0] wr_addr;
    wire [ADDR_WIDTH-1:0] rd_addr;

    reg  [ADDR_WIDTH:0]     wr_ptr_bin;
    wire [ADDR_WIDTH:0]     wr_ptr_gray;
    wire  [ADDR_WIDTH:0]     rd_ptr_gray_sync; // 同步过来的读指针

    assign wr_addr = wr_ptr_bin[ADDR_WIDTH-1:0];
    assign wr_ptr_gray = (wr_ptr_bin >> 1) ^ wr_ptr_bin;

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin <= 0;
        end else if (wr_en && !full) begin
            wr_ptr_bin <= wr_ptr_bin + 1;
        end
    end  

// -- Read Domain --
    reg  [ADDR_WIDTH:0] rd_ptr_bin;
    wire [ADDR_WIDTH:0] rd_ptr_gray;
    wire  [ADDR_WIDTH:0] wr_ptr_gray_sync; // 同步过来的写指针

    assign rd_addr = rd_ptr_bin[ADDR_WIDTH-1:0];
    assign rd_ptr_gray = (rd_ptr_bin >> 1) ^ rd_ptr_bin;

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin <= 0;
        end else if (rd_en && !empty) begin
            rd_ptr_bin <= rd_ptr_bin + 1;
        end
    end

    // 3. 指针跨域同步
    synchronizer #(.WIDTH(ADDR_WIDTH+1)) wr_sync_inst (
        .clk(rd_clk),
        .rst_n(rd_rst_n),
        .data_in(wr_ptr_gray),
        .data_out(wr_ptr_gray_sync)
    );


    synchronizer #(.WIDTH(ADDR_WIDTH+1)) rd_sync_inst (
        .clk(wr_clk),
        .rst_n(wr_rst_n),
        .data_in(rd_ptr_gray),
        .data_out(rd_ptr_gray_sync)
    );

    assign full = (wr_ptr_gray[ADDR_WIDTH:ADDR_WIDTH-1] == ~rd_ptr_gray_sync[ADDR_WIDTH:ADDR_WIDTH-1]) &&
                  (wr_ptr_gray[ADDR_WIDTH-2:0] == rd_ptr_gray_sync[ADDR_WIDTH-2:0]);
    assign empty = (rd_ptr_gray == wr_ptr_gray_sync);


    ram_dp #(
      .DATA_WIDTH (DATA_WIDTH),
      .ADDR_WIDTH (ADDR_WIDTH),
      .DEPTH      (DEPTH)) ram_dp_init
    (
       .wr_clk          (wr_clk),
       .rst_n           (wr_rst_n),
       .wr_addr         (wr_addr),
       .w_data          (w_data),
       .wr_en           (wr_en & !full),
       .rd_clk          (rd_clk),
       .rd_addr         (rd_addr),
       .rd_en           (rd_en & !empty),
       .r_data          (r_data)
    );
endmodule
