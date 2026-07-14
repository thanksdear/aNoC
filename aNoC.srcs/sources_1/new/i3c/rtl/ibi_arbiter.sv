`default_nettype none

// IBI Arbiter：处理 target 发起的带内中断。
//
// bus idle 时检测 SDA 被拉低，随后接收获胜 target 的 DA，
// 根据配置发送 ACK/NACK，并可选接收一个 MDB。
//
// 流程：
//   S_IDLE  : 监测 SDA，target 拉低后进入请求
//   S_REQ   : 向顶层 mux 请求总线控制权
//   S_ADDR  : OD 接收 DA[6:0] + RnW=1
//   S_ACK9  : master 驱动第9位，0=ACK，1=NACK
//   S_MDB   : 若接受且 ibi_mdb_en=1，接收 MDB
//   S_TBIT  : master 驱动 T-bit=0，表示不再接收更多 MDB
//   S_STOP  : 发 STOP 并输出状态 pulse
//
// addr_shift 最后一位在 S_ADDR→S_ACK9 的 posedge 更新，
// 所以 ibi_addr 在 S_ACK9 的下一拍锁存。

module ibi_arbiter (
    input  logic        clk,
    input  logic        rst_n,

    // 总线监测
    input  logic        bus_idle,       // 主传输路径空闲
    input  logic        sda_in,         // pad 后的 SDA

    // 配置，来自 CSR CTRL
    input  logic        ibi_en,         // 使能 IBI 检测
    input  logic        ibi_accept,     // 1=ACK，0=NACK
    input  logic        ibi_mdb_en,     // ACK 后是否接收 MDB

    // 与普通传输路径仲裁总线控制权
    output logic        ibi_req,        // 请求控制总线
    input  logic        ibi_grant,      // 顶层 mux 授权

    // Line Controller 接口，顶层 mux 选择
    output logic [1:0]  lc_cmd,
    output logic        lc_sda_tx,
    output logic        lc_cmd_valid,
    input  logic        lc_cmd_ready,
    input  logic        lc_sda_rx,
    input  logic        lc_sda_rx_valid,
    output logic        lc_open_drain,

    // 结果，送到 csr_regs
    output logic [6:0]  ibi_addr,       // 获胜 target 的 DA
    output logic [7:0]  ibi_mdb_data,   // MDB byte
    output logic        ibi_mdb_valid,  // MDB 捕获完成
    output logic        ibi_done,       // IBI 已接受并处理完成
    output logic        ibi_nacked      // IBI 被 NACK
);

localparam [1:0] LC_DATA = 2'b00;
localparam [1:0] LC_STOP = 2'b10;

// 状态定义
typedef enum logic [2:0] {
    S_IDLE  = 3'd0,
    S_REQ   = 3'd1,
    S_ADDR  = 3'd2,
    S_ACK9  = 3'd3,
    S_MDB   = 3'd4,
    S_TBIT  = 3'd5,
    S_STOP  = 3'd6
} ibi_state_t;

ibi_state_t state, next_state;

// 数据通路寄存器
logic [2:0] bit_cnt;      // 8-bit 接收阶段从7递减到0
logic       lc_issued;    // LC 命令已发出
logic [7:0] addr_shift;   // 接收完成后 [7:1]=DA，[0]=RnW
logic [7:0] mdb_shift;    // MDB byte 拼接
logic       accept_r;     // 锁存 ibi_accept
logic       mdb_en_r;     // 锁存 ibi_mdb_en
logic       result_done_r;
logic       result_nacked_r;
logic       result_mdb_valid_r;

// 状态寄存器
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= S_IDLE;
    else        state <= next_state;
end

// 次态组合逻辑
always_comb begin
    next_state = state;
    case (state)
        S_IDLE:
            if (ibi_en && bus_idle && !sda_in)
                next_state = S_REQ;

        S_REQ:
            if (ibi_grant) next_state = S_ADDR;

        S_ADDR:
            if (lc_issued && lc_sda_rx_valid && bit_cnt == 3'd0)
                next_state = S_ACK9;

        S_ACK9:
            if (lc_issued && lc_sda_rx_valid) begin
                if (accept_r && mdb_en_r) next_state = S_MDB;
                else                      next_state = S_STOP;
            end

        S_MDB:
            if (lc_issued && lc_sda_rx_valid && bit_cnt == 3'd0)
                next_state = S_TBIT;

        S_TBIT:
            if (lc_issued && lc_sda_rx_valid)
                next_state = S_STOP;

        S_STOP:
            if (lc_issued && lc_cmd_ready)
                next_state = S_IDLE;

        default: next_state = S_IDLE;
    endcase
end

// 数据通路寄存器
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bit_cnt      <= 3'd7;
        lc_issued    <= 1'b0;
        addr_shift   <= '0;
        mdb_shift    <= '0;
        accept_r     <= 1'b0;
        mdb_en_r     <= 1'b0;
        result_done_r <= 1'b0;
        result_nacked_r <= 1'b0;
        result_mdb_valid_r <= 1'b0;
        ibi_addr     <= '0;
        ibi_mdb_data <= '0;
        ibi_mdb_valid<= 1'b0;
        ibi_done     <= 1'b0;
        ibi_nacked   <= 1'b0;
    end else begin
        // pulse 输出默认每周期清零
        ibi_done      <= 1'b0;
        ibi_nacked    <= 1'b0;
        ibi_mdb_valid <= 1'b0;

        // 进入新接收阶段时复位阶段状态
        if (state == S_REQ && next_state == S_ADDR) begin
            accept_r <= ibi_accept;
            mdb_en_r <= ibi_mdb_en;
            bit_cnt   <= 3'd7;
            lc_issued <= 1'b0;
            addr_shift<= '0;
            result_done_r <= 1'b0;
            result_nacked_r <= 1'b0;
            result_mdb_valid_r <= 1'b0;
        end
        if (state == S_ACK9 && next_state == S_MDB) begin
            bit_cnt   <= 3'd7;
            mdb_shift <= '0;
            // lc_issued 已由同周期 rx_valid 分支清零
        end

        // 发出 LC 命令后置位 lc_issued
        if (!lc_issued && lc_cmd_ready &&
                state != S_IDLE && state != S_REQ)
            lc_issued <= 1'b1;

        // LC 命令完成后清零
        if (state == S_STOP && lc_issued && lc_cmd_ready)
            lc_issued <= 1'b0;
        else if (lc_issued && lc_sda_rx_valid)
            lc_issued <= 1'b0;

        // 接收地址 byte
        if (state == S_ADDR && lc_issued && lc_sda_rx_valid) begin
            addr_shift <= {addr_shift[6:0], lc_sda_rx};
            if (bit_cnt != 3'd0) bit_cnt <= bit_cnt - 3'd1;
        end

        // S_ACK9 首周期锁存 ibi_addr，此时 addr_shift 已稳定
        if (state == S_ACK9 && !lc_issued)
            ibi_addr <= addr_shift[7:1];  // 丢弃 RnW 位

        // ACK9 完成
        if (state == S_ACK9 && lc_issued && lc_sda_rx_valid) begin
            if (!accept_r) begin
                result_nacked_r <= 1'b1;
            end else if (!mdb_en_r) begin
                result_done_r <= 1'b1;
            end
        end

        // MDB 接收
        if (state == S_MDB && lc_issued && lc_sda_rx_valid) begin
            mdb_shift <= {mdb_shift[6:0], lc_sda_rx};
            if (bit_cnt != 3'd0) bit_cnt <= bit_cnt - 3'd1;
        end

        // T-bit 完成后 MDB 有效
        if (state == S_TBIT && lc_issued && lc_sda_rx_valid) begin
            ibi_mdb_data  <= mdb_shift;
            result_mdb_valid_r <= 1'b1;
            result_done_r <= 1'b1;
        end

        // STOP 完成后发布结果 pulse
        if (state == S_STOP && lc_issued && lc_cmd_ready) begin
            ibi_done      <= result_done_r;
            ibi_nacked    <= result_nacked_r;
            ibi_mdb_valid <= result_mdb_valid_r;
        end
    end
end

// 组合输出

assign ibi_req       = (state != S_IDLE);
assign lc_open_drain = 1'b1;   // IBI 仲裁始终使用 OD
assign lc_cmd        = (state == S_STOP) ? LC_STOP : LC_DATA;

// 非 idle/request 且 LC ready 时发命令
assign lc_cmd_valid  = (state != S_IDLE) && (state != S_REQ) &&
                       !lc_issued && lc_cmd_ready;

// SDA 驱动值：ADDR/MDB 阶段释放；ACK9 阶段 0=ACK、1=NACK；TBIT 驱动0。
always_comb begin
    case (state)
        S_ACK9:  lc_sda_tx = !accept_r;   // 0=ACK，1=NACK
        S_TBIT:  lc_sda_tx = 1'b0;        // 不再接收更多 MDB
        S_STOP:  lc_sda_tx = 1'b1;        // STOP 释放 SDA
        default: lc_sda_tx = 1'b1;        // 释放，由 target 驱动
    endcase
end

endmodule
