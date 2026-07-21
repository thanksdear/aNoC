`default_nettype none

// Byte Serializer：连接 Scheduler 和 Line Controller。
// 把一个 byte 以及第9位语义转换成9个 LC DATA 命令。
//
// 第9位规则：
//   地址阶段：释放 SDA，由 target 驱动 ACK/NACK
//   I3C write：master 驱动 T-bit，值为 tx_data 的 odd parity
//   I3C read ：target 先驱动 T-bit；master 可在仍有数据时拉低 SDA 提前结束
//   I2C write：释放 SDA，由 target 驱动 ACK/NACK
//   I2C read ：master 驱动 ACK/NACK，0=continue，1=last
//
// lc_issued 表示 LC 命令已发出，正在等待完成。

module byte_serializer (
    input  logic        clk,
    input  logic        rst_n,

    // 模式配置，来自 CSR
    input  logic        i3c_mode,       // 1=I3C  0=I2C legacy

    // 上层接口，来自 Scheduler
    // SER_BYTE 发送/接收一个 byte；START/STOP/Sr 直接透传给 LC。
    input  logic [1:0]  cmd,
    input  logic [7:0]  tx_data,        // 写/地址阶段要发送的 byte
    input  logic        is_read,        // 1=target 驱动 bit[7:0]
    input  logic        is_addr,        // 1=地址 byte，第9位为 ACK/NACK
    input  logic        tbit_cont,      // read 方向：master 1=继续/释放，0=提前结束
    input  logic        cmd_valid,
    output logic        cmd_ready,

    // 结果信号，在 byte_done 当周期有效
    output logic [7:0]  rx_data,        // read 阶段收到的 byte
    output logic        byte_done,      // 第9位结束
    output logic        ack_ok,         // 地址/I2C：1=ACK，0=NACK
    output logic        parity_err,     // I3C write 的 T-bit 不匹配
    output logic        read_continue,  // I3C read：解析后的 T=1；仅 byte_done 时有效

    // 下层接口，连接 Line Controller
    output logic [1:0]  lc_cmd,
    output logic        lc_sda_tx,
    output logic        lc_cmd_valid,
    input  logic        lc_cmd_ready,
    input  logic        lc_sda_rx,
    input  logic        lc_sda_rx_valid,
    output logic        lc_open_drain   // 1=OD，0=PP
);

// 命令编码，START/STOP/Sr 与 LC 编码一致
localparam [1:0] SER_BYTE  = 2'b00;
localparam [1:0] SER_START = 2'b01;
localparam [1:0] SER_STOP  = 2'b10;
localparam [1:0] SER_SR    = 2'b11;

localparam [1:0] LC_DATA   = 2'b00;

// 状态定义
typedef enum logic [1:0] {
    S_IDLE      = 2'd0,
    S_PASSTHRU  = 2'd1,    // START / STOP / Sr 透传
    S_BITS      = 2'd2,    // data bit[7:0]
    S_BIT9      = 2'd3     // 第9位：ACK/NACK 或 T-bit
} ser_state_t;

ser_state_t state, next_state;

// 内部寄存器
logic [2:0] bit_cnt;        // 当前 bit 位置，7到0
logic       lc_issued;      // LC 命令已发出
logic [7:0] tx_data_r;
logic       is_read_r;
logic       is_addr_r;
logic       i3c_mode_r;
logic       tbit_cont_r;
logic [1:0] cmd_r;
logic       parity_acc;     // TX 数据 bit 异或，用于 T-bit
logic [7:0] rx_shift;       // RX byte 拼接寄存器

// 第9位驱动值，组合逻辑
// 8个数据 bit 后 parity_acc = ^tx_data_r，odd parity T-bit = !parity_acc。
logic bit9_tx;
always_comb begin
    if (is_addr_r || (!i3c_mode_r && !is_read_r))
        bit9_tx = 1'b1;             // 释放 SDA，由 target 驱动 ACK/NACK
    else if (!i3c_mode_r)
        bit9_tx = !tbit_cont_r;     // I2C read：0=ACK，1=NACK
    else if (!is_read_r)
        bit9_tx = !parity_acc;      // I3C write：T-bit 奇偶校验
    else
        // I3C read 的 T-bit 由 target 先驱动。这里使用 OD：master
        // 希望继续时释放 SDA；达到接收上限时拉低 SDA 提前结束。
        bit9_tx = tbit_cont_r;
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= S_IDLE;
    else        state <= next_state;
end

// 次态组合逻辑
always_comb begin
    next_state = state;
    case (state)
        S_IDLE:
            if (cmd_valid) begin
                if (cmd == SER_BYTE) next_state = S_BITS;
                else                 next_state = S_PASSTHRU;
            end

        // LC 接收命令并回到 idle 后完成
        S_PASSTHRU:
            if (lc_issued && lc_cmd_ready)
                next_state = S_IDLE;

        // 发送到 bit0 后进入第9位
        S_BITS:
            if (lc_issued && lc_sda_rx_valid && bit_cnt == 3'd0)
                next_state = S_BIT9;

        S_BIT9:
            if (lc_issued && lc_sda_rx_valid)
                next_state = S_IDLE;

        default: next_state = S_IDLE;
    endcase
end

// 数据通路寄存器
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        lc_issued   <= 1'b0;
        bit_cnt     <= 3'd7;
        parity_acc  <= 1'b0;
        rx_shift    <= '0;
        tx_data_r   <= '0;
        is_read_r   <= 1'b0;
        is_addr_r   <= 1'b0;
        i3c_mode_r  <= 1'b0;
        tbit_cont_r <= 1'b1;
        cmd_r       <= SER_BYTE;
        rx_data     <= '0;
        byte_done   <= 1'b0;
        ack_ok      <= 1'b0;
        parity_err  <= 1'b0;
        read_continue <= 1'b0;
    end else begin
        byte_done  <= 1'b0;   // 默认清零，S_BIT9 完成时置位
        parity_err <= 1'b0;   // 错误结果只在 byte_done 当拍有效

        // 从 IDLE 进入工作状态时锁存命令参数
        if (state == S_IDLE && next_state != S_IDLE) begin
            tx_data_r   <= tx_data;
            is_read_r   <= is_read;
            is_addr_r   <= is_addr;
            i3c_mode_r  <= i3c_mode;
            tbit_cont_r <= tbit_cont;
            cmd_r       <= cmd;
            bit_cnt     <= 3'd7;
            parity_acc  <= 1'b0;
            rx_shift    <= '0;
            lc_issued   <= 1'b0;
        end

        // 发出 LC 命令后置位 lc_issued
        if (!lc_issued && lc_cmd_ready && state != S_IDLE)
            lc_issued <= 1'b1;

        // LC 完成后清零 lc_issued
        if (lc_issued) begin
            // START/STOP/Sr：LC 回到 idle
            if (state == S_PASSTHRU && lc_cmd_ready)
                lc_issued <= 1'b0;
            // DATA bit：SCL high 结束时 sda_rx_valid 有效
            if ((state == S_BITS || state == S_BIT9) && lc_sda_rx_valid)
                lc_issued <= 1'b0;
        end

        // 收集 RX bit，并计算 TX parity
        if (state == S_BITS && lc_issued && lc_sda_rx_valid) begin
            rx_shift[bit_cnt] <= lc_sda_rx;
            parity_acc        <= parity_acc ^ tx_data_r[bit_cnt];
            if (bit_cnt != 3'd0)
                bit_cnt <= bit_cnt - 3'd1;
            // bit_cnt 保持0，用于次态判断
        end

        // 第9位完成后锁存结果
        if (state == S_BIT9 && lc_issued && lc_sda_rx_valid) begin
            byte_done  <= 1'b1;
            rx_data    <= rx_shift;
            // ack_ok 只对地址阶段和 I2C 有意义；I3C data 强制为1
            ack_ok     <= (is_addr_r || !i3c_mode_r) ? !lc_sda_rx : 1'b1;
            // I3C read 的总线 T 只有在 target 和 controller 都愿意继续
            // 时才为1。I2C 没有 target-driven T，继续条件来自本地长度。
            read_continue <= is_read_r &&
                             (i3c_mode_r ? lc_sda_rx : tbit_cont_r);
            // parity_err 只检查 I3C write 的 T-bit 回读
            parity_err <= i3c_mode_r && !is_addr_r && !is_read_r
                          && (lc_sda_rx != !parity_acc);
        end
    end
end

// 组合输出

// idle 时可接收新命令
assign cmd_ready = (state == S_IDLE);

// OD/PP 选择：地址、I2C 和 I3C read data/T-bit 使用 OD；
// I3C write data 和 parity T-bit 使用 PP。
always_comb begin
    case (state)
        S_BITS:  lc_open_drain = is_addr_r || !i3c_mode_r || is_read_r;
        S_BIT9:  lc_open_drain = is_addr_r || !i3c_mode_r || is_read_r;
        default: lc_open_drain = 1'b1;
    endcase
end

// START/STOP/Sr 透传，DATA 固定为 2'b00
assign lc_cmd = (state == S_PASSTHRU) ? cmd_r : LC_DATA;

// SDA 驱动值；需要 target 驱动时释放为1
always_comb begin
    case (state)
        S_BITS:  lc_sda_tx = is_read_r ? 1'b1 : tx_data_r[bit_cnt];
        S_BIT9:  lc_sda_tx = bit9_tx;
        default: lc_sda_tx = 1'b1;
    endcase
end

// 非 idle 且 LC ready 时发出命令
assign lc_cmd_valid = (state != S_IDLE) && !lc_issued && lc_cmd_ready;

endmodule
