`default_nettype none

// CSR寄存器组：保存配置寄存器和硬件状态寄存器。
// APB slave 先译码成内部寄存器总线，本模块不直接处理 APB 时序。
//
// 寄存器表，按字节寻址，word aligned：
//   0x00  BUS_TIMING_0  [31:16]=SCL_HIGH  [15:0]=SCL_LOW          RW
//   0x04  BUS_TIMING_1  [15:0]=SDA_HOLD                           RW
//   0x08  CTRL          [4]=ibi_mdb_en [3]=ibi_en [2]=sw_rst [1]=core_en [0]=i3c_mode  RW
//   0x0C  STATUS        [1]=ibi_pending  [0]=busy                 RO
//   0x10  IBI_STATUS    [16]=ibi_valid(RW1C) [15:8]=len [7]=mdb [6:0]=addr  RO/RW1C
//   0x14  ERR_STATUS    [1]=nack_err  [0]=parity_err               RW1C
//   0x18  ENTDAA_STATUS [8]=valid [6:0]=assigned DA                RO
//   0x1C  ENTDAA_PID_LO discovered PID/BCR/DCR[31:0]               RO
//   0x30  ENTDAA_PID_HI discovered PID/BCR/DCR[63:32]              RO
//
// RW1C：软件写1清除，硬件通过 pulse 置位。
// sw_rst：自清零，只保持一个周期。

module csr_regs (
    input  logic        clk ,
    input  logic        rst_n,

    // 内部寄存器总线，由 APB slave 驱动
    input  logic [7:0]  reg_addr,       // 字节地址，word aligned
    input  logic [31:0] reg_wdata,
    input  logic        reg_wr_en,      // 单周期写使能
    input  logic [3:0]  reg_wstrb,      // byte mask
    output logic [31:0] reg_rdata,      // 组合读数据

    // 配置输出，供 Line Controller / Serializer / Scheduler 使用
    output logic [15:0] scl_high_period,
    output logic [15:0] scl_low_period,
    output logic [15:0] sda_hold_time,
    output logic        i3c_mode,
    output logic        core_en,
    output logic        ibi_en,
    output logic        ibi_mdb_en,
    output logic        sw_rst,         // 单周期复位 pulse

    // 硬件状态输入
    input  logic        hw_busy,            // 正在传输
    input  logic        hw_ibi_pending,     // 有 IBI 待处理
    input  logic [6:0]  hw_ibi_addr,        // IBI 发起方地址
    input  logic        hw_ibi_mdb,         // 1表示带 MDB
    input  logic [7:0]  hw_ibi_len,         // IBI 数据长度
    input  logic        hw_ibi_set,         // 捕获到新 IBI
    input  logic        hw_parity_err_set,  // parity 错误
    input  logic        hw_nack_err_set,    // 收到 NACK
    input  logic [63:0] hw_entdaa_pid,      // 最近发现的 PID/BCR/DCR
    input  logic [6:0]  hw_entdaa_da,       // 最近分配的动态地址
    input  logic        hw_entdaa_valid     // ENTDAA 结果有效
);

// 地址常量
localparam [7:0] ADDR_BUS_TIMING_0 = 8'h00;
localparam [7:0] ADDR_BUS_TIMING_1 = 8'h04;
localparam [7:0] ADDR_CTRL         = 8'h08;
localparam [7:0] ADDR_STATUS       = 8'h0C;
localparam [7:0] ADDR_IBI_STATUS   = 8'h10;
localparam [7:0] ADDR_ERR_STATUS   = 8'h14;
localparam [7:0] ADDR_ENTDAA_STATUS = 8'h18;
localparam [7:0] ADDR_ENTDAA_PID_LO = 8'h1C;
localparam [7:0] ADDR_ENTDAA_PID_HI = 8'h30;

// 寄存器存储
logic [31:0] r_bus_timing_0;  // SCL_HIGH / SCL_LOW
logic [15:0] r_bus_timing_1;  // SDA_HOLD
logic [4:0]  r_ctrl;          // [4]=ibi_mdb_en [3]=ibi_en [2]=sw_rst [1]=core_en [0]=i3c_mode
logic [16:0] r_ibi_status;    // [16]=valid [15:8]=len [7]=mdb [6:0]=addr
logic [1:0]  r_err_status;    // [1]=nack_err [0]=parity_err
logic [63:0] r_entdaa_pid;    // 最近发现的 PID+BCR/DCR
logic [8:0]  r_entdaa_status; // [8]=valid [6:0]=assigned DA

// 写逻辑
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_bus_timing_0 <= {16'd6, 16'd6};   // SCL_HIGH=6, SCL_LOW=6
        r_bus_timing_1 <= 16'd2;             // SDA_HOLD=2
        r_ctrl         <= 5'b0_0001;         // 默认 I3C mode，core 关闭
        r_ibi_status   <= '0;
        r_err_status   <= '0;
        r_entdaa_pid   <= '0;
        r_entdaa_status<= '0;
    end else begin
        // sw_rst 每周期默认清零，只有写入当拍有效
        r_ctrl[2] <= 1'b0;

        // RW寄存器写入
        if (reg_wr_en) begin
            case (reg_addr)
                ADDR_BUS_TIMING_0: 
                    for (int i = 0; i < 4; i++) begin
                        if (reg_wstrb[i])
                            r_bus_timing_0[i*8 +: 8]
                                <= reg_wdata[i*8 +: 8];
                    end
                ADDR_BUS_TIMING_1: 
                    for (int i = 0; i < 2; i++) begin
                        if (reg_wstrb[i])
                            r_bus_timing_1[i*8 +: 8] <= reg_wdata[i*8 +: 8];
                    end
                ADDR_CTRL: begin
                    if (reg_wstrb[0])begin         // i3c_mode
                        r_ctrl[1:0] <= reg_wdata[1:0];         // core_en, i3c_mode
                        r_ctrl[2]   <= reg_wdata[2];            // sw_rst 下一周期自清
                        r_ctrl[3]   <= reg_wdata[3];            // ibi_en
                        r_ctrl[4]   <= reg_wdata[4];            // ibi_mdb_en
                    end
                end
                // STATUS 为 RO，写入忽略
                // IBI_STATUS 只有 bit[16] 为 RW1C
                ADDR_IBI_STATUS:
                    if (reg_wstrb[2] && reg_wdata[16]) r_ibi_status[16] <= 1'b0;
                // ERR_STATUS 为 RW1C
                ADDR_ERR_STATUS:
                    if (reg_wstrb[0]) r_err_status <= r_err_status & ~reg_wdata[1:0];
                default: ;
            endcase
        end

        // 硬件状态更新
        if (hw_ibi_set) begin
            r_ibi_status[16]   <= 1'b1;
            r_ibi_status[15:8] <= hw_ibi_len;
            r_ibi_status[7]    <= hw_ibi_mdb;
            r_ibi_status[6:0]  <= hw_ibi_addr;
        end

        if (hw_parity_err_set) r_err_status[0] <= 1'b1;
        if (hw_nack_err_set)   r_err_status[1] <= 1'b1;

        if (hw_entdaa_valid) begin
            r_entdaa_pid       <= hw_entdaa_pid;
            r_entdaa_status[8] <= 1'b1;
            r_entdaa_status[6:0] <= hw_entdaa_da;
        end
    end
end

// 组合读 mux，支持 zero-wait APB 访问
always_comb begin
    case (reg_addr)
        ADDR_BUS_TIMING_0: reg_rdata = r_bus_timing_0;
        ADDR_BUS_TIMING_1: reg_rdata = {16'd0, r_bus_timing_1};
        ADDR_CTRL:         reg_rdata = {27'd0, r_ctrl};
        ADDR_STATUS:       reg_rdata = {30'd0, hw_ibi_pending, hw_busy};
        ADDR_IBI_STATUS:   reg_rdata = {15'd0, r_ibi_status};
        ADDR_ERR_STATUS:   reg_rdata = {30'd0, r_err_status};
        ADDR_ENTDAA_STATUS: reg_rdata = {23'd0, r_entdaa_status};
        ADDR_ENTDAA_PID_LO: reg_rdata = r_entdaa_pid[31:0];
        ADDR_ENTDAA_PID_HI: reg_rdata = r_entdaa_pid[63:32];
        default:           reg_rdata = '0;
    endcase
end

// 配置输出
assign scl_high_period = r_bus_timing_0[31:16];
assign scl_low_period  = r_bus_timing_0[15:0];
assign sda_hold_time   = r_bus_timing_1;
assign i3c_mode        = r_ctrl[0];
assign core_en         = r_ctrl[1];
assign sw_rst          = r_ctrl[2];
assign ibi_en          = r_ctrl[3];
assign ibi_mdb_en      = r_ctrl[4];

endmodule
