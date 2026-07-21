`default_nettype none

// Line Controller：I3C master 的底层时序控制。
// 负责驱动 SCL/SDA，产生 START、STOP、Repeated START 和逐 bit SCL 周期。
//
// scl_high_period、scl_low_period、sda_hold_time 要大于等于1。
//
// 基本规则：空闲 SCL/SDA 为高；SCL 高时 SDA 下降为 START，上升为 STOP；
// DATA 阶段在 SCL low 修改 SDA，在 SCL high 末尾采样。
module line_controller (
    input  logic        clk,
    input  logic        rst_n,

    // 总线时序，由 BUS_TIMING_0 / BUS_TIMING_1 配置
    input  logic [15:0] scl_high_period,
    input  logic [15:0] scl_low_period,
    input  logic [15:0] sda_hold_time,
    input  logic        open_drain_mode,

    // 命令接口，来自 byte_serializer
    input  logic [1:0]  cmd,        // CMD_DATA / CMD_START / CMD_STOP / CMD_SR
    input  logic        sda_tx,     // 需要发射的数据
    input  logic        cmd_valid,
    output logic        cmd_ready,  // 空闲拉高

    // SCL high 结束时采样的 SDA
    output logic        sda_rx,
    output logic        sda_rx_valid,

    // Pad 接口，顶层再连接到双向管脚
    output logic        scl_oe,
    output logic        scl_out,
    input  logic        scl_in,
    output logic        sda_oe,
    output logic        sda_out,
    input  logic        sda_in
);

// 命令编码
localparam [1:0] CMD_DATA  = 2'b00;
localparam [1:0] CMD_START = 2'b01;
localparam [1:0] CMD_STOP  = 2'b10;
localparam [1:0] CMD_SR    = 2'b11;

// 状态定义
typedef enum logic [3:0] {
    S_IDLE        = 4'd0,
    S_START_COND  = 4'd1,
    S_BIT_SCL_LO  = 4'd2,
    S_BIT_SCL_HI  = 4'd3,
    S_STOP_SCL_LO = 4'd4,
    S_STOP_SCL_HI = 4'd5,
    S_STOP_COND   = 4'd6,
    S_SR_SCL_LO   = 4'd7,
    S_SR_SDA_HI   = 4'd8,
    S_SR_SDA_LO   = 4'd9
} lc_state_t;

lc_state_t   state, next_state;
logic [15:0] cnt;
logic        sda_tx_r;   // 锁存发射数据
logic        sda_prev;   // 上一个 SDA 电平，用于 tHD;DAT 保持

// 状态寄存器
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= S_IDLE;
    else        state <= next_state;
end

// 次态组合逻辑
always_comb begin
    next_state = state;  // 默认保持当前状态
    case (state)
        S_IDLE: begin
            if (cmd_valid)
                unique case (cmd)
                    CMD_START: next_state = S_START_COND;
                    CMD_DATA:  next_state = S_BIT_SCL_LO;
                    CMD_STOP:  next_state = S_STOP_SCL_LO;
                    CMD_SR:    next_state = S_SR_SCL_LO;
                endcase
        end
        S_START_COND:  if (cnt >= sda_hold_time  - 16'h1) next_state = S_IDLE;
        S_BIT_SCL_LO:  if (cnt >= scl_low_period  - 16'h1) next_state = S_BIT_SCL_HI;
        S_BIT_SCL_HI:  if (cnt >= scl_high_period - 16'h1) next_state = S_IDLE;
        S_STOP_SCL_LO: if (cnt >= scl_low_period  - 16'h1) next_state = S_STOP_SCL_HI;
        S_STOP_SCL_HI: if (cnt >= sda_hold_time   - 16'h1) next_state = S_STOP_COND;
        S_STOP_COND:   if (cnt >= sda_hold_time   - 16'h1) next_state = S_IDLE;
        // Sr 前先在 SCL low 保持旧 SDA，再释放 SDA。等 SDA 已在
        // SCL low 期间稳定至少一拍后才拉高 SCL，避免旧值为 0 时
        // 把 SDA 上升沿误生成 STOP。
        S_SR_SCL_LO:   if ((cnt >= scl_low_period - 16'h1) &&
                           (cnt >= sda_hold_time))
                              next_state = S_SR_SDA_HI;
        S_SR_SDA_HI:   if (cnt >= sda_hold_time   - 16'h1) next_state = S_SR_SDA_LO;
        S_SR_SDA_LO:   if (cnt >= sda_hold_time   - 16'h1) next_state = S_IDLE;
        default: next_state = S_IDLE;
    endcase
end

// 数据通路寄存器
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt          <= '0;
        sda_tx_r     <= 1'b1;
        sda_prev     <= 1'b1;
        sda_rx       <= 1'b1;
        sda_rx_valid <= 1'b0;
    end else begin
        // 状态跳转时清计数器，状态内递增
        cnt <= (state != next_state) ? '0 : cnt + 1'b1;

        // 从 IDLE 进入工作状态时锁存待发送 bit
        if (state == S_IDLE && next_state != S_IDLE)
            sda_tx_r <= sda_tx;

        // sda_prev 用于 SCL 拉低后的 SDA hold 阶段
        if (state == S_BIT_SCL_HI && next_state == S_IDLE)
            sda_prev <= sda_tx_r;           // 给下一个连续 bit 使用
        else if ((state == S_START_COND || state == S_SR_SDA_LO)
                 && next_state == S_IDLE)
            sda_prev <= 1'b0;               // START/Sr 后 SDA 保持低
        else if (state == S_STOP_COND && next_state == S_IDLE)
            sda_prev <= 1'b1;               // STOP 后释放总线

        // SCL high 最后一个周期采样 SDA
        if (state == S_BIT_SCL_HI && next_state == S_IDLE) begin
            sda_rx       <= sda_in;
            sda_rx_valid <= 1'b1;
        end else begin
            sda_rx_valid <= 1'b0;
        end
    end
end

// 组合输出

// idle 时可接收命令
assign cmd_ready = (state == S_IDLE);

// SCL 由 master push-pull 驱动，仅在 low 状态拉低
logic scl_drive;
always_comb
    scl_drive = (state != S_BIT_SCL_LO) &&
                (state != S_STOP_SCL_LO) &&
                (state != S_SR_SCL_LO);

assign scl_oe  = 1'b1;
assign scl_out = scl_drive;

// 各状态下的 SDA 逻辑值
logic sda_drive;
always_comb begin
    case (state)
        S_IDLE:        sda_drive = sda_prev;
        S_START_COND:  sda_drive = 1'b0;
        S_BIT_SCL_LO:  sda_drive = (cnt < sda_hold_time) ? sda_prev : sda_tx_r;
        S_BIT_SCL_HI:  sda_drive = sda_tx_r;
        S_STOP_SCL_LO: sda_drive = 1'b0;
        S_STOP_SCL_HI: sda_drive = 1'b0;  
        S_STOP_COND:   sda_drive = 1'b1;
        S_SR_SCL_LO:   sda_drive = (cnt < sda_hold_time) ? sda_prev : 1'b1;
        S_SR_SDA_HI:   sda_drive = 1'b1;
        S_SR_SDA_LO:   sda_drive = 1'b0;
        default:       sda_drive = 1'b1;
    endcase
end

// OD 模式：只能主动拉低，拉高靠释放总线。
// PP 模式：直接驱动 SDA 输出值。
always_comb begin
    if (open_drain_mode) begin
        sda_oe  = !sda_drive;   // oe=1 时拉低，oe=0 时释放
        sda_out = 1'b0;         // OD 模式只输出0
    end else begin
        sda_oe  = (state != S_IDLE) || !sda_prev; // START/Sr 后的间隔保持 SDA 低
        sda_out = sda_drive;
    end
end

endmodule
