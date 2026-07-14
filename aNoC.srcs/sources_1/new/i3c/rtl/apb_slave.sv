`default_nettype none

// APB slave：把 APB 访问转换成内部寄存器总线访问。
//
// APB 无等待周期时序：
//   Cycle N   : Setup，PSEL=1，PENABLE=0
//   Cycle N+1 : Access，PSEL=1，PENABLE=1
//   Cycle N+2 : master 采样 PRDATA，完成传输
//
// PREADY 固定为1，CSR 组合读数据直接送到 PRDATA。

module apb_slave (
    input  logic        PCLK,
    input  logic        PRESETn,

    // APB master 侧信号
    input  logic        PSEL,           //片选
    input  logic        PENABLE,       //握手
    input  logic        PWRITE,
    input  logic [11:0] PADDR,         // 12-bit 字节地址，4 KB aperture
    input  logic [31:0] PWDATA,
    input  logic [3:0]  PSTRB,         // APB4 byte strobe
    output logic [31:0] PRDATA,
    output logic        PREADY,
    output logic        PSLVERR,

    // 内部寄存器总线，连接 csr_regs
    output logic [7:0]  reg_addr,
    output logic [31:0] reg_wdata,
    output logic [3:0]  reg_wstrb,
    output logic        reg_wr_en,
    input  logic [31:0] reg_rdata
);

// 写使能：写传输的 Access phase 拉高一个周期
assign reg_wr_en = PSEL & PENABLE & PWRITE;

// 地址：Setup/Access phase 都保持有效
assign reg_addr = PADDR[7:0];

// 写数据 byte mask
assign reg_wdata = PWDATA;
assign reg_wstrb = PSTRB;

// 读数据直接来自 CSR
assign PRDATA = reg_rdata;

// 无 wait state，无 slave error
assign PREADY  = 1'b1;
assign PSLVERR = 1'b0;

endmodule
