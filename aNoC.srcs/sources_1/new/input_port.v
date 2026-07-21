`include "noc_params.vh"

module input_port #(
    parameter CUR_X      = 0,
    parameter CUR_Y      = 0,
    // sync_fifo 当前的指针实现要求深度为 2 的幂。
    parameter FIFO_DEPTH = 16
)(
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire [`FLIT_WIDTH-1:0]   flit_in_data,
    input  wire                     flit_in_valid,
    output wire                     flit_in_ready,

    // switch_allocator 返回给本输入端口的输出端口授权（one-hot）。
    input  wire [4:0]               grant,
    output wire [4:0]               route_req_out,

    // 送往 crossbar 的数据和实际生效的输出端口选择（one-hot）。
    output wire [4:0]               grant_to_xbar,
    output wire [`FLIT_WIDTH-1:0]   flit_to_xbar
);

// ============================================================================
// 输入 FIFO
// ============================================================================
wire [`FLIT_WIDTH-1:0] fifo_dout;
wire                   fifo_empty;
wire                   fifo_full;
wire                   fifo_rd_en;
wire                   fifo_wr_en;

// 仅在 valid && ready 时写入；复位期间不接收上游数据。
assign flit_in_ready = rst_n && !fifo_full;
assign fifo_wr_en    = flit_in_valid && flit_in_ready;

sync_fifo #(
    .WIDTH (`FLIT_WIDTH),
    .DEPTH (FIFO_DEPTH)
) u_sync_fifo (
    .clk     (clk),
    .rst_n   (rst_n),
    .wr_en   (fifo_wr_en),
    .wr_data (flit_in_data),
    .rd_en   (fifo_rd_en),
    .rd_data (fifo_dout),
    .full    (fifo_full),
    .empty   (fifo_empty)
);

// ============================================================================
// 路由计算
// ============================================================================
wire [`COORD_WIDTH-1:0] dest_x;
wire [`COORD_WIDTH-1:0] dest_y;
wire [`FLIT_TYPE_WIDTH-1:0] flit_type;
wire [4:0] route_computed;

assign dest_x    = fifo_dout[`DEST_X_RANGE];
assign dest_y    = fifo_dout[`DEST_Y_RANGE];
assign flit_type = fifo_dout[`FLIT_TYPE_RANGE];

route_compute #(
    .COORD_WIDTH (`COORD_WIDTH)
) u_route_compute (
    .dest_x    (dest_x),
    .dest_y    (dest_y),
    .cur_x     (CUR_X[`COORD_WIDTH-1:0]),
    .cur_y     (CUR_Y[`COORD_WIDTH-1:0]),
    .route_out (route_computed)
);

// ============================================================================
// 包状态和交换请求
// ============================================================================
localparam IDLE         = 2'b00;
localparam REQ_PENDING  = 2'b01;
localparam TRANSFERRING = 2'b10;

reg [1:0] state;
reg [1:0] next_state;
reg [4:0] route_saved;

wire request_active;
wire grant_matches_route;
wire flit_transfer;
wire packet_end;

assign request_active      = (state == REQ_PENDING) ||
                             (state == TRANSFERRING);
assign grant_matches_route = |(grant & route_saved);

/*
 * 每个 flit 都必须在本周期真正得到目标输出的授权后才能离开 FIFO。
 * 这样不会把“HEAD 曾获得授权”误当成 allocator 已经锁定整条通路。
 */
assign flit_transfer = request_active && !fifo_empty &&
                       grant_matches_route;
assign packet_end    = (flit_type == `FLIT_TYPE_TAIL) ||
                       (flit_type == `FLIT_TYPE_HEAD_TAIL);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= IDLE;
    else
        state <= next_state;
end

always @(*) begin
    next_state = state;

    case (state)
        IDLE: begin
            if (!fifo_empty)
                next_state = REQ_PENDING;
        end

        REQ_PENDING: begin
            if (flit_transfer) begin
                if (packet_end)
                    next_state = IDLE;
                else
                    next_state = TRANSFERRING;
            end
        end

        TRANSFERRING: begin
            if (flit_transfer && packet_end)
                next_state = IDLE;
        end

        default: next_state = IDLE;
    endcase
end

// 新包队首出现时保存 HEAD/HEAD_TAIL 计算出的方向；BODY/TAIL 沿用该方向。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        route_saved <= 5'b00000;
    else if ((state == IDLE) && !fifo_empty)
        route_saved <= route_computed;
end

// FIFO 为空时不请求，避免 allocator 对无效数据产生授权。
assign route_req_out = (request_active && !fifo_empty) ?
                       route_saved : 5'b00000;

// 只有一次真实的 grant/data 传输才弹出 FIFO 并驱动 crossbar。
assign fifo_rd_en    = flit_transfer;
assign grant_to_xbar = flit_transfer ? (grant & route_saved) : 5'b00000;
assign flit_to_xbar  = flit_transfer ? fifo_dout : {`FLIT_WIDTH{1'b0}};

endmodule
