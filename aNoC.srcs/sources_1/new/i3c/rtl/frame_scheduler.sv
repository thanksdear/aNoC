`default_nettype none

// Frame Scheduler：把一次 I3C/I2C 传输拆成 byte 级命令。
//
// 传输格式：START + addr_byte + data_bytes[0..N-1] + STOP。
// START/STOP 直接透传给 serializer，地址和数据使用 SER_BYTE。
// 地址阶段 NACK 后立即 STOP，并上报 xfer_nack。
//
// cmd_issued 标记当前命令已发出，等待 byte_done 或 passthrough 完成。

module frame_scheduler (
    input  logic        clk,
    input  logic        rst_n,

    // 传输命令，来自命令队列或软件
    input  logic [6:0]  xfer_addr,      // 7-bit target 地址
    input  logic        xfer_rw,        // 0=write  1=read
    input  logic [7:0]  xfer_len,       // 数据 byte 数，1..255
    input  logic        xfer_valid,
    output logic        xfer_ready,     // S_IDLE 时为1

    // TX 数据，写方向
    input  logic [7:0]  tx_byte,
    input  logic        tx_valid,       // TX FIFO 非空
    output logic        tx_ready,       // 消耗一个 TX byte

    // RX 数据，读方向
    output logic [7:0]  rx_byte,        // rx_valid=1 时有效
    output logic        rx_valid,       // 写入一个 RX byte

    // 传输状态
    output logic        xfer_done,      // 传输完成，已发 STOP
    output logic        xfer_nack,      // 地址 NACK，已发 STOP

    // Byte serializer 接口
    output logic [1:0]  ser_cmd,
    output logic [7:0]  ser_tx_data,
    output logic        ser_is_read,
    output logic        ser_is_addr,
    output logic        ser_tbit_cont,  // 0表示最后一个 byte
    output logic        ser_cmd_valid,
    input  logic        ser_cmd_ready,
    input  logic [7:0]  ser_rx_data,
    input  logic        ser_byte_done,
    input  logic        ser_ack_ok,
    input  logic        ser_parity_err  // 本模块未使用，留给错误记录
);

// 命令编码
localparam [1:0] SER_BYTE  = 2'b00;
localparam [1:0] SER_START = 2'b01;
localparam [1:0] SER_STOP  = 2'b10;

// 状态定义
typedef enum logic [2:0] {
    S_IDLE    = 3'd0,
    S_START   = 3'd1,
    S_ADDR    = 3'd2,
    S_DATA_WR = 3'd3,
    S_DATA_RD = 3'd4,
    S_STOP    = 3'd5
} fsched_state_t;

fsched_state_t state, next_state;

// 数据通路寄存器
logic [6:0] addr_r;
logic       rw_r;
logic [7:0] byte_cnt_r;   // 剩余数据 byte 数
logic       nack_r;       // 已收到地址 NACK
logic       cmd_issued;   // 命令已发出，等待完成

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
            if (xfer_valid)
                next_state = S_START;

        // Passthrough 命令在 serializer 回到 idle 后完成
        S_START:
            if (cmd_issued && ser_cmd_ready)
                next_state = S_ADDR;

        S_ADDR:
            if (cmd_issued && ser_byte_done) begin
                if (!ser_ack_ok)       next_state = S_STOP;   // NACK 后中止
                else if (byte_cnt_r == 8'd0) next_state = S_STOP;
                else if (!rw_r)        next_state = S_DATA_WR;
                else                   next_state = S_DATA_RD;
            end

        S_DATA_WR:
            if (cmd_issued && ser_byte_done && byte_cnt_r == 8'd1)
                next_state = S_STOP;
            // cmd_issued 下周期清零后继续发下一个 byte

        S_DATA_RD:
            if (cmd_issued && ser_byte_done && byte_cnt_r == 8'd1)
                next_state = S_STOP;

        S_STOP:
            if (cmd_issued && ser_cmd_ready)
                next_state = S_IDLE;

        default: next_state = S_IDLE;
    endcase
end

// 数据通路寄存器
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        addr_r      <= '0;
        rw_r        <= 1'b0;
        byte_cnt_r  <= '0;
        nack_r      <= 1'b0;
        cmd_issued  <= 1'b0;
        rx_byte     <= '0;
        rx_valid    <= 1'b0;
        tx_ready    <= 1'b0;
        xfer_done   <= 1'b0;
        xfer_nack   <= 1'b0;
    end else begin
        // pulse 信号默认每周期清零
        rx_valid  <= 1'b0;
        tx_ready  <= 1'b0;
        xfer_done <= 1'b0;
        xfer_nack <= 1'b0;

        // 从 IDLE 进入工作状态时锁存传输参数
        if (state == S_IDLE && next_state != S_IDLE) begin
            addr_r     <= xfer_addr;
            rw_r       <= xfer_rw;
            byte_cnt_r <= xfer_len;
            nack_r     <= 1'b0;
            cmd_issued <= 1'b0;
        end

        // 发送命令给 serializer；写数据时 TX FIFO 空则等待
        if (!cmd_issued && ser_cmd_ready && state != S_IDLE &&
                !(state == S_DATA_WR && !tx_valid))
            cmd_issued <= 1'b1;

        // 命令完成后清 cmd_issued
        if (cmd_issued) begin
            // START/STOP：serializer 回到 idle
            if ((state == S_START || state == S_STOP) && ser_cmd_ready)
                cmd_issued <= 1'b0;
            // Byte 命令：等待 byte_done
            if ((state == S_ADDR || state == S_DATA_WR || state == S_DATA_RD)
                    && ser_byte_done)
                cmd_issued <= 1'b0;
        end

        // 地址 NACK 记录
        if (state == S_ADDR && cmd_issued && ser_byte_done && !ser_ack_ok)
            nack_r <= 1'b1;

        // 写数据：消耗 TX byte 并递减计数
        if (state == S_DATA_WR && cmd_issued && ser_byte_done) begin
            byte_cnt_r <= byte_cnt_r - 8'd1;
        end

        // 读数据：保存 RX byte 并递减计数
        if (state == S_DATA_RD && cmd_issued && ser_byte_done) begin
            rx_byte  <= ser_rx_data;
            rx_valid <= 1'b1;
            byte_cnt_r <= byte_cnt_r - 8'd1;
        end

        // 传输完成
        if (state == S_STOP && cmd_issued && ser_cmd_ready) begin
            xfer_done <= !nack_r;
            xfer_nack <= nack_r;
        end
    end
end

// 组合输出
assign tx_ready =(state == S_DATA_WR) &&
    !cmd_issued &&
    ser_cmd_ready &&
    tx_valid;
assign xfer_ready = (state == S_IDLE);

// 条件满足时向 serializer 发命令
assign ser_cmd_valid = (state != S_IDLE) && !cmd_issued && ser_cmd_ready
                       && !(state == S_DATA_WR && !tx_valid);

// serializer 命令类型
always_comb begin
    case (state)
        S_START:   ser_cmd = SER_START;
        S_STOP:    ser_cmd = SER_STOP;
        default:   ser_cmd = SER_BYTE;
    endcase
end

// 地址 byte = {7-bit addr, R/W bit}
assign ser_tx_data  = (state == S_ADDR) ? {addr_r, rw_r} : tx_byte;

assign ser_is_addr  = (state == S_ADDR);
assign ser_is_read  = (state == S_DATA_RD);

// tbit_cont：1表示后续还有 byte，0表示最后一个 byte
assign ser_tbit_cont = (byte_cnt_r > 8'd1);

endmodule
