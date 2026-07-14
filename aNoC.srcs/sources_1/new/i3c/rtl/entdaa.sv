`default_nettype none

// ENTDAA：动态地址分配流程。
// ccc_handler 已经发出 START + 0x7E(W) + ENTDAA_CODE 后启动本模块。
//
// 循环流程：
//   1. master 提供64个 SCL，未分配地址的 target 用 OD 仲裁 PID+BCR+DCR。
//   2. master 读回获胜设备的64-bit ID。
//   3. master 发送 DA + parity。
//   4. target ACK 表示接受地址，NACK 表示无设备剩余。
//
// ENTDAA 仲裁是连续 OD bit 流，因此本模块绕过 byte_serializer 直接驱动 LC。
// DAT 提供下一个可用 DA；地址池耗尽时上报 error。

module entdaa (
    input  logic        clk,
    input  logic        rst_n,

    // 启动和完成
    input  logic        start,          // 开始 ENTDAA
    output logic        done,           // 分配流程结束
    output logic        error,          // DAT 地址耗尽

    // DAT 接口，由上层管理地址池
    input  logic [6:0]  dat_addr,       // 下一个可用动态地址
    input  logic        dat_valid,      // dat_addr 有效
    output logic        dat_rd,         // 消耗一个 DA

    // 本轮发现的设备信息
    output logic [63:0] dev_pid,        // 64-bit PID+BCR/DCR
    output logic [6:0]  dev_da,         // 分配给该设备的 DA
    output logic        dev_valid,      // dev_pid/dev_da 有效

    // Line Controller 接口
    output logic [1:0]  lc_cmd,
    output logic        lc_sda_tx,
    output logic        lc_cmd_valid,
    input  logic        lc_cmd_ready,
    input  logic        lc_sda_rx,
    input  logic        lc_sda_rx_valid,
    output logic        lc_open_drain
);

localparam [1:0] LC_DATA = 2'b00;

// 状态定义
typedef enum logic [2:0] {
    S_IDLE    = 3'd0,   // 空闲
    S_RCV_ID  = 3'd1,   // 接收 64-bit PID+BCR/DCR
    S_SEND_DA = 3'd2,   // 发送 7-bit DA + parity
    S_ACK9    = 3'd3,   // 释放 SDA 并采样 ACK/NACK
    S_CHECK   = 3'd4,   // ACK=continue, NACK=done
    S_DONE    = 3'd5,
    S_ERROR   = 3'd6
} entdaa_state_t;

entdaa_state_t state, next_state;

// 数据通路寄存器
logic [5:0] bit_idx;       // ID 接收时 63..0，DA 发送时 7..0
logic       lc_issued;     // LC DATA 命令已发出
logic [63:0] id_shift;     // MSB first 拼接 64-bit ID
logic [6:0]  da_r;         // 本轮 DA
logic        continue_r;   // 收到 ACK 后继续下一轮
logic [7:0]  da_byte;

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
            if (start) begin
                if (dat_valid) next_state = S_RCV_ID;
                else           next_state = S_ERROR;
            end

        // OD 模式下连续接收 64 bit
        S_RCV_ID:
            if (lc_issued && lc_sda_rx_valid && bit_idx == 6'd0)
                next_state = S_SEND_DA;

        // 发送 DA byte 后释放 SDA，等待 target ACK/NACK
        S_SEND_DA:
            if (lc_issued && lc_sda_rx_valid && bit_idx == 6'd0)
                next_state = S_ACK9;

        S_ACK9:
            if (lc_issued && lc_sda_rx_valid)
                next_state = S_CHECK;

        S_CHECK:
            if (continue_r) begin
                // 可能还有 target，继续申请新的 DA
                if (dat_valid) next_state = S_RCV_ID;
                else           next_state = S_ERROR;
            end else begin
                next_state = S_DONE;
            end

        S_DONE:  next_state = S_IDLE;
        S_ERROR: next_state = S_IDLE;

        default: next_state = S_IDLE;
    endcase
end

// 数据通路寄存器
// [S_IDLE] ─(start & 有空闲地址)─> [S_RCV_ID] ──> [S_SEND_DA] ──> [S_CHECK]
//                                    ▲                                │
//                                    └───────(还有从机 & ACK)─────────┘
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bit_idx    <= 6'd63;
        lc_issued  <= 1'b0;
        id_shift   <= '0;
        da_r       <= '0;
        continue_r <= 1'b0;
        dev_pid    <= '0;
        dev_da     <= '0;
        dev_valid  <= 1'b0;
        dat_rd     <= 1'b0;
        done       <= 1'b0;
        error      <= 1'b0;
    end else begin
        dev_valid <= 1'b0;
        dat_rd    <= 1'b0;
        done      <= 1'b0;
        error     <= 1'b0;

        // 新一轮 ID 接收开始
        if ((state == S_IDLE  && next_state == S_RCV_ID) ||
            (state == S_CHECK && next_state == S_RCV_ID)) begin
            bit_idx    <= 6'd63;
            lc_issued  <= 1'b0;
            id_shift   <= '0;
            // 锁存并消耗本轮 DA
            da_r    <= dat_addr;
            dat_rd  <= 1'b1;
        end

        // 发出 LC 命令后置位 lc_issued
        if (!lc_issued && lc_cmd_ready && state != S_IDLE &&
                state != S_CHECK && state != S_DONE && state != S_ERROR)
            lc_issued <= 1'b1;

        // LC 采样完成后清 lc_issued
        if (lc_issued && lc_sda_rx_valid)
            lc_issued <= 1'b0;

        // 连续接收并拼接 ID bit
        if (state == S_RCV_ID && lc_issued && lc_sda_rx_valid) begin
            id_shift <= {id_shift[62:0], lc_sda_rx};  // MSB first
            if (bit_idx != 6'd0)
                bit_idx <= bit_idx - 6'd1;
            else
                bit_idx <= 6'd7;
        end

        // DA byte bit 发送
        if (state == S_SEND_DA && lc_issued && lc_sda_rx_valid) begin
            if (bit_idx != 6'd0)
                bit_idx <= bit_idx - 6'd1;
        end

        // DA 发送完成后检查 ACK
        if (state == S_ACK9 && lc_issued && lc_sda_rx_valid) begin
            continue_r <= !lc_sda_rx;   // ACK(0)=continue, NACK(1)=done
            // 只有 ACK 表示真实分配成功；终止 NACK 不更新设备表
            if (!lc_sda_rx) begin
                dev_pid   <= id_shift;
                dev_da    <= da_r;
                dev_valid <= 1'b1;
            end
        end

        // 结束状态
        if (state == S_DONE)  done  <= 1'b1;
        if (state == S_ERROR) error <= 1'b1;
    end
end

// 输出到 line_controller 的组合逻辑

assign da_byte       = {da_r, ~^da_r};
assign lc_cmd        = LC_DATA;
assign lc_open_drain = 1'b1;

assign lc_cmd_valid = (state == S_RCV_ID || state == S_SEND_DA || state == S_ACK9) &&
                      !lc_issued && lc_cmd_ready;

always_comb begin
    case (state)
        S_SEND_DA: lc_sda_tx = da_byte[bit_idx[2:0]];
        default:   lc_sda_tx = 1'b1;  // 释放 SDA，用于 ID 仲裁和 ACK 采样
    endcase
end

endmodule
