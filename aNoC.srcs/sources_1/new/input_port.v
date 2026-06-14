`include "noc_params.vh"
module input_port #(
    parameter CUR_X = 0,
    parameter CUR_Y = 0
)(
    input                    clk,
    input                    rst_n,
    input [`FLIT_WIDTH-1:0]  flit_in_data,
    input                    flit_in_valid,
    output                   flit_in_ready,

    input  [4:0]             grant,
    output [4:0]             route_req_out,

    output [4:0]             grant_to_xbar,
    output [`FLIT_WIDTH-1:0] flit_to_xbar
);

// ========== FIFO实例化 ==========
wire    [`FLIT_WIDTH-1:0]   fifo_dout;
wire                        fifo_empty;
wire                        fifo_full;
wire                        fifo_rd_en;

assign  flit_in_ready  =   !fifo_full;

syn_fifo #(
    .DATA_WIDTH ( `FLIT_WIDTH  ),
    .ADDR_WIDTH ( 4 ),
    .DEPTH      ( 15 ))
    u_asyn_fifo (
    .clk                  ( clk            ),
    .rst_n                ( rst_n          ),
    .wr_en                   ( flit_in_valid  ),
    .w_data                  ( flit_in_data   ),

    .rd_en                   ( fifo_rd_en     ),
    .full                    ( fifo_full      ),
    .r_data                  ( fifo_dout      ),
    .empty                   ( fifo_empty     )
);

// ========== 路由计算 ==========
// 只在FIFO非空时提取目标坐标和计算路由
wire    [1:0]               flit_type = fifo_dout[`FLIT_TYPE_RANGE];
wire    [1:0]               dest_x;
wire    [1:0]               dest_y;
wire    [4:0]               route_out;

// 只在FIFO非空时使用有效的目标坐标
assign dest_x = fifo_empty ? 2'b00 : fifo_dout[`DEST_X_RANGE];
assign dest_y = fifo_empty ? 2'b00 : fifo_dout[`DEST_Y_RANGE];

route_compute #(
    .COORD_WIDTH ( 2 ))
 u_route_compute (
    .dest_x                  ( dest_x      ),
    .dest_y                  ( dest_y      ),
    .cur_x                   ( CUR_X[1:0]  ),
    .cur_y                   ( CUR_Y[1:0]  ),

    .route_out               ( route_out   )
);

// ========== 状态机：处理请求和多flit包传输 ==========
// 状态定义
localparam IDLE         = 2'b00;  // 空闲状态
localparam REQ_PENDING  = 2'b01;  // 等待grant（HEAD或HEAD_TAIL flit）
localparam TRANSFERRING = 2'b10;  // 正在传输多flit包（BODY/TAIL）

reg [1:0]               state, next_state;
reg [4:0]               route_saved;        // 保存的路由方向
reg                     in_packet;          // 标记是否在传输包中

// 状态转移
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        state <= IDLE;
    else
        state <= next_state;
end

// 下一状态逻辑
always @(*) begin
    next_state = state;
    case(state)
        IDLE: begin
            if(!fifo_empty) begin
                // FIFO有数据，读取并请求路由
                next_state = REQ_PENDING;
            end
        end

        REQ_PENDING: begin
            if(|grant) begin
                // 获得grant
                if(flit_type == `FLIT_TYPE_HEAD) begin
                    // HEAD flit，后续还有BODY/TAIL
                    next_state = TRANSFERRING;
                end
                else begin
                    // HEAD_TAIL flit，单flit包，直接回到IDLE
                    next_state = IDLE;
                end
            end
        end

        TRANSFERRING: begin
            if(!fifo_empty && (flit_type == `FLIT_TYPE_TAIL)) begin
                // 传输完TAIL flit，包结束
                next_state = IDLE;
            end
            else if(fifo_empty) begin
                // FIFO空了但包未结束，继续等待
                next_state = TRANSFERRING;
            end
        end

        default: next_state = IDLE;
    endcase
end

// 保存路由方向（只在接收HEAD或HEAD_TAIL时更新）
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        route_saved <= 5'b00000;
    end
    else if(state == IDLE && !fifo_empty) begin
        // 在IDLE状态且FIFO非空时，保存新的路由计算结果
        route_saved <= route_out;
    end
end

// 包传输标志
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        in_packet <= 1'b0;
    end
    else begin
        case(state)
            IDLE:
                in_packet <= 1'b0;
            REQ_PENDING:
                if(|grant && flit_type == `FLIT_TYPE_HEAD)
                    in_packet <= 1'b1;
            TRANSFERRING:
                if(!fifo_empty && flit_type == `FLIT_TYPE_TAIL)
                    in_packet <= 1'b0;
        endcase
    end
end

// ========== 输出逻辑 ==========
// 路由请求输出：在REQ_PENDING状态发出请求
assign route_req_out = (state == REQ_PENDING) ? route_saved : 5'b00000;

// FIFO读使能：
// 1. REQ_PENDING状态下获得grant时读取
// 2. TRANSFERRING状态下持续读取（虫洞路由，保持通路）
assign fifo_rd_en = ((state == REQ_PENDING) && (|grant)) ||
                    ((state == TRANSFERRING) && !fifo_empty);

// 输出到交叉开关
assign flit_to_xbar = (!fifo_empty)?fifo_dout:{`FLIT_WIDTH{1'b0}};
assign grant_to_xbar = (state == REQ_PENDING && (|grant)) ? grant :
                       (state == TRANSFERRING) ? route_saved : 5'b00000;

endmodule