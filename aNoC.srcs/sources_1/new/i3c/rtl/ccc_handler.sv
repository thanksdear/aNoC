`default_nettype none

// CCC Handler：生成 CCC 帧序列；ENTDAA 流程交给 entdaa 子模块。
//
// 支持三类帧：
//
//   Broadcast: START → 0xFC(0x7E W) → CCC_CODE → [data_len bytes TX/RX] → STOP
//   Direct:    START → 0xFC          → CCC_CODE → Sr → {DA,RW} → [data] → STOP
//   ENTDAA:    START → 0xFC          → 0x07     → <entdaa loop> → STOP
//
// header byte 使用 is_addr=1，保持 OD 并检查 ACK/NACK。
// data byte 根据方向设置 is_read。

module ccc_handler (
    input  logic        clk,
    input  logic        rst_n,

    // CCC 命令描述符
    input  logic        ccc_type,       // 0=broadcast  1=direct
    input  logic [7:0]  ccc_code,       // CCC code，0x07=ENTDAA
    input  logic [6:0]  target_addr,    // direct CCC 目标 DA
    input  logic        target_rw,      // 0=write(set)，1=read(get)
    input  logic [7:0]  data_len,       // data byte 数，0表示只有 header
    input  logic        ccc_valid,
    output logic        ccc_ready,

    // TX / RX 数据
    input  logic [7:0]  tx_byte,
    input  logic        tx_valid,
    output logic        tx_ready,
    output logic [7:0]  rx_byte,
    output logic        rx_valid,

    // 传输状态
    output logic        ccc_done,
    output logic        ccc_nack,       // 任意 header byte 被 NACK

    // DAT 接口，转发给 entdaa
    input  logic [6:0]  dat_addr,
    input  logic        dat_valid,
    output logic        dat_rd,
    output logic [63:0] dev_pid,
    output logic [6:0]  dev_da,
    output logic        dev_valid,

    // Byte serializer 接口
    output logic [1:0]  ser_cmd,
    output logic [7:0]  ser_tx_data,
    output logic        ser_is_read,
    output logic        ser_is_addr,
    output logic        ser_tbit_cont,
    output logic        ser_cmd_valid,
    input  logic        ser_cmd_ready,
    input  logic [7:0]  ser_rx_data,
    input  logic        ser_byte_done,
    input  logic        ser_ack_ok,
    input  logic        ser_parity_err,

    // ENTDAA 直接驱动 Line Controller 的旁路接口
    output logic        entdaa_lc_active,
    output logic [1:0]  entdaa_lc_cmd,
    output logic        entdaa_lc_sda_tx,
    output logic        entdaa_lc_cmd_valid,
    input  logic        lc_cmd_ready,
    input  logic        lc_sda_rx,
    input  logic        lc_sda_rx_valid,
    output logic        entdaa_lc_open_drain
);

// 编码
localparam [7:0]  ENTDAA_CODE   = 8'h07;
localparam [7:0]  BCAST_ADDR_B  = 8'hFC;    // {7'h7E, W=0}
localparam [1:0]  SER_BYTE      = 2'b00;
localparam [1:0]  SER_START     = 2'b01;
localparam [1:0]  SER_STOP      = 2'b10;
localparam [1:0]  SER_SR        = 2'b11;

// 状态定义
typedef enum logic [3:0] {
    S_IDLE        = 4'd0,
    S_START       = 4'd1,
    S_BCAST_ADDR  = 4'd2,   // 0xFC, is_addr=1
    S_CCC_CODE    = 4'd3,   // ccc_code, is_addr=1
    S_ENTDAA_RUN  = 4'd4,   // 交给 entdaa 子模块
    S_SR          = 4'd5,   // Repeated Start，仅 direct CCC
    S_TARGET_ADDR = 4'd6,   // {target_addr, rw}, is_addr=1
    S_DATA_TX     = 4'd7,
    S_DATA_RX     = 4'd8,
    S_STOP        = 4'd9
} ccc_state_t;

ccc_state_t state, next_state;

// 数据通路寄存器
logic       ccc_type_r;
logic [7:0] ccc_code_r;
logic [6:0] target_addr_r;
logic       target_rw_r;
    logic [7:0] byte_cnt_r;  // 剩余 data byte 数
logic       nack_r;
logic       cmd_issued;
logic       entdaa_kicked;   // 防止重复拉高 entdaa_start

// entdaa 子模块连线
logic        entdaa_start;
logic        entdaa_done, entdaa_error;
logic [1:0]  e_lc_cmd;
logic        e_lc_sda_tx, e_lc_cmd_valid, e_lc_open_drain;

entdaa u_entdaa (
    .clk          (clk),
    .rst_n        (rst_n),
    .start        (entdaa_start),
    .done         (entdaa_done),
    .error        (entdaa_error),
    .dat_addr     (dat_addr),
    .dat_valid    (dat_valid),
    .dat_rd       (dat_rd),
    .dev_pid      (dev_pid),
    .dev_da       (dev_da),
    .dev_valid    (dev_valid),
    .lc_cmd          (e_lc_cmd),
    .lc_sda_tx       (e_lc_sda_tx),
    .lc_cmd_valid    (e_lc_cmd_valid),
    .lc_cmd_ready    (lc_cmd_ready),
    .lc_sda_rx       (lc_sda_rx),
    .lc_sda_rx_valid (lc_sda_rx_valid),
    .lc_open_drain   (e_lc_open_drain)
);

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
            if (ccc_valid) next_state = S_START;

        S_START:
            if (cmd_issued && ser_cmd_ready) next_state = S_BCAST_ADDR;

        S_BCAST_ADDR:
            if (cmd_issued && ser_byte_done) begin
                if (!ser_ack_ok) next_state = S_STOP;    // 没有 target 响应
                else             next_state = S_CCC_CODE;
            end

        S_CCC_CODE:
            if (cmd_issued && ser_byte_done) begin
                if (!ser_ack_ok)                       next_state = S_STOP;
                else if (ccc_code_r == ENTDAA_CODE)    next_state = S_ENTDAA_RUN;
                else if (ccc_type_r)                   next_state = S_SR;
                else if (byte_cnt_r != 8'd0)
                    next_state = S_DATA_TX;             // 带 data 的 broadcast
                else                                   next_state = S_STOP;
            end

        S_ENTDAA_RUN:
            if (entdaa_done || entdaa_error) next_state = S_STOP;

        S_SR:
            if (cmd_issued && ser_cmd_ready) next_state = S_TARGET_ADDR;

        S_TARGET_ADDR:
            if (cmd_issued && ser_byte_done) begin
                if (!ser_ack_ok)      next_state = S_STOP;
                else if (byte_cnt_r == 8'd0) next_state = S_STOP;
                else if (target_rw_r) next_state = S_DATA_RX;
                else                  next_state = S_DATA_TX;
            end

        S_DATA_TX:
            if (cmd_issued && ser_byte_done && byte_cnt_r == 8'd1)
                next_state = S_STOP;

        S_DATA_RX:
            if (cmd_issued && ser_byte_done && byte_cnt_r == 8'd1)
                next_state = S_STOP;

        S_STOP:
            if (cmd_issued && ser_cmd_ready) next_state = S_IDLE;

        default: next_state = S_IDLE;
    endcase
end

// 数据通路寄存器
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ccc_type_r    <= 1'b0;
        ccc_code_r    <= '0;
        target_addr_r <= '0;
        target_rw_r   <= 1'b0;
        byte_cnt_r    <= '0;
        nack_r        <= 1'b0;
        cmd_issued    <= 1'b0;
        entdaa_kicked <= 1'b0;
        rx_byte       <= '0;
        rx_valid      <= 1'b0;
        tx_ready      <= 1'b0;
        ccc_done      <= 1'b0;
        ccc_nack      <= 1'b0;
    end else begin
        rx_valid  <= 1'b0;
        tx_ready  <= 1'b0;
        ccc_done  <= 1'b0;
        ccc_nack  <= 1'b0;

        // 从 IDLE 进入 START 时锁存描述符
        if (state == S_IDLE && next_state != S_IDLE) begin
            ccc_type_r    <= ccc_type;
            ccc_code_r    <= ccc_code;
            target_addr_r <= target_addr;
            target_rw_r   <= target_rw;
            byte_cnt_r    <= data_len;
            nack_r        <= 1'b0;
            cmd_issued    <= 1'b0;
            entdaa_kicked <= 1'b0;
        end

        // ENTDAA start：S_ENTDAA_RUN 首周期打一拍 pulse
        if (state != S_ENTDAA_RUN)
            entdaa_kicked <= 1'b0;
        if (state == S_ENTDAA_RUN && !entdaa_kicked)
            entdaa_kicked <= 1'b1;

        // 发普通 serializer 命令；ENTDAA 旁路期间不使用
        if (!cmd_issued && ser_cmd_ready && state != S_IDLE &&
                state != S_ENTDAA_RUN &&
                !(state == S_DATA_TX && !tx_valid))
            cmd_issued <= 1'b1;

        // 命令完成后清 cmd_issued
        if (cmd_issued) begin
            if ((state == S_START || state == S_SR || state == S_STOP)
                    && ser_cmd_ready)
                cmd_issued <= 1'b0;
            if ((state == S_BCAST_ADDR || state == S_CCC_CODE ||
                 state == S_TARGET_ADDR ||
                 state == S_DATA_TX    || state == S_DATA_RX)
                    && ser_byte_done)
                cmd_issued <= 1'b0;
        end

        // 记录任意 header byte 的 NACK
        if ((state == S_BCAST_ADDR || state == S_CCC_CODE ||
             state == S_TARGET_ADDR) &&
                cmd_issued && ser_byte_done && !ser_ack_ok)
            nack_r <= 1'b1;

        // Data TX
        if (state == S_DATA_TX && cmd_issued && ser_byte_done) begin
            byte_cnt_r <= byte_cnt_r - 8'd1;
        end

        // Data RX
        if (state == S_DATA_RX && cmd_issued && ser_byte_done) begin
            rx_byte  <= ser_rx_data;
            rx_valid <= 1'b1;
            byte_cnt_r <= byte_cnt_r - 8'd1;
        end

        // 传输完成
        if (state == S_STOP && cmd_issued && ser_cmd_ready) begin
            ccc_done <= !nack_r;
            ccc_nack <=  nack_r;
        end
    end
end

// 组合输出
assign tx_ready =(state == S_DATA_WR) &&!cmd_issued &&
    ser_cmd_ready &&
    tx_valid;
assign ccc_ready    = (state == S_IDLE);

// entdaa_start 在 S_ENTDAA_RUN 首周期有效
assign entdaa_start = (state == S_ENTDAA_RUN) && !entdaa_kicked;

// ENTDAA 期间绕过 byte_serializer，直接通过顶层 mux 驱动 LC。
logic own_cmd_valid;
always_comb begin
    case (state)
        S_START, S_SR, S_STOP:
            own_cmd_valid = !cmd_issued && ser_cmd_ready;
        S_DATA_TX:
            own_cmd_valid = !cmd_issued && ser_cmd_ready && tx_valid;
        S_ENTDAA_RUN, S_IDLE:
            own_cmd_valid = 1'b0;
        default:
            own_cmd_valid = !cmd_issued && ser_cmd_ready;
    endcase
end

assign ser_cmd_valid  = (state == S_ENTDAA_RUN) ? 1'b0             : own_cmd_valid;
assign ser_cmd        = (state == S_START)       ? SER_START        :
                        (state == S_SR)          ? SER_SR           :
                        (state == S_STOP)        ? SER_STOP         : SER_BYTE;
assign ser_tx_data    = (state == S_BCAST_ADDR)  ? BCAST_ADDR_B     :
                        (state == S_CCC_CODE)    ? ccc_code_r       :
                        (state == S_TARGET_ADDR) ? {target_addr_r, target_rw_r} :
                                                   tx_byte;
assign ser_is_read    = (state == S_DATA_RX);
assign ser_is_addr    = (state == S_BCAST_ADDR || state == S_CCC_CODE ||
                         state == S_TARGET_ADDR);
assign ser_tbit_cont  = (byte_cnt_r > 8'd1);

assign entdaa_lc_active     = (state == S_ENTDAA_RUN);
assign entdaa_lc_cmd        = e_lc_cmd;
assign entdaa_lc_sda_tx     = e_lc_sda_tx;
assign entdaa_lc_cmd_valid  = e_lc_cmd_valid;
assign entdaa_lc_open_drain = e_lc_open_drain;

endmodule
