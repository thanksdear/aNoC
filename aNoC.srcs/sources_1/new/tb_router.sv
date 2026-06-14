`timescale 1ns/1ps
`include "noc_params.vh"
module tb_router();
 	reg 		clk;
	reg 		rst_n;   

	initial begin
		clk = 0;
		forever #5  clk = ~clk;
	end

	initial begin
		rst_n = 0;
	    #20 rst_n = 1;
	end
// input_port Inputs
reg   [`FLIT_WIDTH-1:0]  flit_in_data_local;
reg   [`FLIT_WIDTH-1:0]  flit_in_data_east;
reg   [`FLIT_WIDTH-1:0]  flit_in_data_west;
reg   [`FLIT_WIDTH-1:0]  flit_in_data_north;
reg   [`FLIT_WIDTH-1:0]  flit_in_data_south;
reg   flit_in_valid_local;
reg   flit_in_valid_east;
reg   flit_in_valid_west;
reg   flit_in_valid_north;
reg   flit_in_valid_south;

initial begin
    // 初始化所有输入信号
    flit_in_data_local = 0;
    flit_in_data_east = 0;
    flit_in_data_west = 0;
    flit_in_data_north = 0;
    flit_in_data_south = 0;
    
    flit_in_valid_local = 0;
    flit_in_valid_east = 0;
    flit_in_valid_west = 0;
    flit_in_valid_north = 0;
    flit_in_valid_south = 0;
end


// input_port Outputs
wire  flit_in_ready_local;
wire  flit_in_ready_east;
wire  flit_in_ready_west;
wire  flit_in_ready_north;
wire  flit_in_ready_south;

wire  [4:0]  route_req_out_local;
wire  [4:0]  route_req_out_east;
wire  [4:0]  route_req_out_west;
wire  [4:0]  route_req_out_north;
wire  [4:0]  route_req_out_south;

wire  [4:0]  grant_to_xbar_local;
wire  [4:0]  grant_to_xbar_east;
wire  [4:0]  grant_to_xbar_west;
wire  [4:0]  grant_to_xbar_north;
wire  [4:0]  grant_to_xbar_south;

wire  [`FLIT_WIDTH-1:0]  flit_to_xbar_local;
wire  [`FLIT_WIDTH-1:0]  flit_to_xbar_east;
wire  [`FLIT_WIDTH-1:0]  flit_to_xbar_west;
wire  [`FLIT_WIDTH-1:0]  flit_to_xbar_north;
wire  [`FLIT_WIDTH-1:0]  flit_to_xbar_south;
// switch_allocator Outputs
wire  [4:0]  grant_local;
wire  [4:0]  grant_east;
wire  [4:0]  grant_west;
wire  [4:0]  grant_north;
wire  [4:0]  grant_south;

input_port #(
    .CUR_X ( 0 ),.CUR_Y ( 0 )) input_port_local(
    .clk                           ( clk                         ),
    .rst_n                         ( rst_n                       ),
    .flit_in_data                  ( flit_in_data_local          ),
    .flit_in_valid                 ( flit_in_valid_local         ),
    .grant                         ( grant_local                 ),

    .flit_in_ready                 ( flit_in_ready_local         ),
    .route_req_out                 ( route_req_out_local         ),
    .grant_to_xbar                 ( grant_to_xbar_local         ),
    .flit_to_xbar                  ( flit_to_xbar_local          )    
);

input_port #(
    .CUR_X ( 0 ),.CUR_Y ( 0 )) input_port_east(
    .clk                           ( clk                        ),
    .rst_n                         ( rst_n                      ),
    .flit_in_data                  ( flit_in_data_east          ),
    .flit_in_valid                 ( flit_in_valid_east         ),
    .grant                         ( grant_east                 ),

    .flit_in_ready                 ( flit_in_ready_east         ),
    .route_req_out                 ( route_req_out_east         ),
    .grant_to_xbar                 ( grant_to_xbar_east         ),
    .flit_to_xbar                  ( flit_to_xbar_east          )    
);

input_port #(
    .CUR_X ( 0 ),.CUR_Y ( 0 )) input_port_west(
    .clk                           ( clk                         ),
    .rst_n                         ( rst_n                       ),
    .flit_in_data                  ( flit_in_data_west          ),
    .flit_in_valid                 ( flit_in_valid_west         ),
    .grant                         ( grant_west                 ),

    .flit_in_ready                 ( flit_in_ready_west         ),
    .route_req_out                 ( route_req_out_west         ),
    .grant_to_xbar                 ( grant_to_xbar_west         ),
    .flit_to_xbar                  ( flit_to_xbar_west          )    
);

input_port #(
    .CUR_X ( 0 ),.CUR_Y ( 0 )) input_port_north(
    .clk                           ( clk                         ),
    .rst_n                         ( rst_n                       ),
    .flit_in_data                  ( flit_in_data_north          ),
    .flit_in_valid                 ( flit_in_valid_north         ),
    .grant                         ( grant_north                 ),

    .flit_in_ready                 ( flit_in_ready_north         ),
    .route_req_out                 ( route_req_out_north         ),
    .grant_to_xbar                 ( grant_to_xbar_north         ),
    .flit_to_xbar                  ( flit_to_xbar_north         )    
);

input_port #(
    .CUR_X ( 0 ),.CUR_Y ( 0 )) input_port_south(
    .clk                           ( clk                         ),
    .rst_n                         ( rst_n                       ),
    .flit_in_data                  ( flit_in_data_south          ),
    .flit_in_valid                 ( flit_in_valid_south         ),
    .grant                         ( grant_south                 ),

    .flit_in_ready                 ( flit_in_ready_south         ),
    .route_req_out                 ( route_req_out_south         ),
    .grant_to_xbar                 ( grant_to_xbar_south         ),
    .flit_to_xbar                  ( flit_to_xbar_south          )    
);


switch_allocator  u_switch_allocator (
    .clk                     ( clk               ),
    .rst_n                   ( rst_n             ),
    .route_req_local         ( route_req_out_local   ),
    .route_req_east          ( route_req_out_east    ),
    .route_req_west          ( route_req_out_west    ),
    .route_req_north         ( route_req_out_north   ),
    .route_req_south         ( route_req_out_south   ),

    .grant_local             ( grant_local       ),
    .grant_east              ( grant_east        ),
    .grant_west              ( grant_west        ),
    .grant_north             ( grant_north       ),
    .grant_south             ( grant_south       )
);
// crossbar Outputs
wire  [`FLIT_WIDTH-1:0]  out_data_local;
wire  [`FLIT_WIDTH-1:0]  out_data_east;
wire  [`FLIT_WIDTH-1:0]  out_data_west;
wire  [`FLIT_WIDTH-1:0]  out_data_north;
wire  [`FLIT_WIDTH-1:0]  out_data_south;
wire  out_valid_local;
wire  out_valid_east;
wire  out_valid_west;
wire  out_valid_north;
wire  out_valid_south;

crossbar  u_crossbar (
    .in_data_local           ( flit_to_xbar_local     ),
    .in_data_east            ( flit_to_xbar_east      ),
    .in_data_west            ( flit_to_xbar_west      ),
    .in_data_north           ( flit_to_xbar_north     ),
    .in_data_south           ( flit_to_xbar_south     ),
    .grant_local             ( grant_to_xbar_local       ),
    .grant_east              ( grant_to_xbar_east        ),
    .grant_west              ( grant_to_xbar_west        ),
    .grant_north             ( grant_to_xbar_north       ),
    .grant_south             ( grant_to_xbar_south       ),

    .out_data_local          ( out_data_local    ),
    .out_data_east           ( out_data_east     ),
    .out_data_west           ( out_data_west     ),
    .out_data_north          ( out_data_north    ),
    .out_data_south          ( out_data_south    ),
    .out_valid_local         ( out_valid_local   ),
    .out_valid_east          ( out_valid_east    ),
    .out_valid_west          ( out_valid_west    ),
    .out_valid_north         ( out_valid_north   ),
    .out_valid_south         ( out_valid_south   )
);

// output_port Outputs
wire  [`FLIT_WIDTH-1:0]  flit_out_local;
wire  [`FLIT_WIDTH-1:0]  flit_out_east;
wire  [`FLIT_WIDTH-1:0]  flit_out_west;
wire  [`FLIT_WIDTH-1:0]  flit_out_north;
wire  [`FLIT_WIDTH-1:0]  flit_out_south;

wire  flit_out_valid_local;
wire  flit_out_valid_east;
wire  flit_out_valid_west;
wire  flit_out_valid_north;
wire  flit_out_valid_south;
output_port  output_port_local(
    .flit_from_xbar          ( out_data_local   ),
    .flit_valid              ( out_valid_local       ),

    .flit_out                ( flit_out_local         ),
    .flit_out_valid          ( flit_out_valid_local   )
);

output_port  output_port_east(
    .flit_from_xbar          ( out_data_east   ),
    .flit_valid              ( out_valid_east       ),

    .flit_out                ( flit_out_east         ),
    .flit_out_valid          ( flit_out_valid_east   )
);

output_port  output_port_west(
    .flit_from_xbar          ( out_data_west   ),
    .flit_valid              ( out_valid_west       ),

    .flit_out                ( flit_out_west         ),
    .flit_out_valid          ( flit_out_valid_west   )
);

output_port  output_port_north(
    .flit_from_xbar          ( out_data_north   ),
    .flit_valid              ( out_valid_north       ),

    .flit_out                ( flit_out_north         ),
    .flit_out_valid          ( flit_out_valid_north   )
);

output_port  output_port_south(
    .flit_from_xbar          ( out_data_south   ),
    .flit_valid              ( out_valid_south       ),

    .flit_out                ( flit_out_south         ),
    .flit_out_valid          ( flit_out_valid_south   )
);

// 任务：生成一个flit
task create_flit;
    input [1:0] flit_type;    // FLIT类型
    input [1:0] dest_x;       // 目标X坐标
    input [1:0] dest_y;       // 目标Y坐标
    input [1:0] src_x;        // 源X坐标
    input [1:0] src_y;        // 源Y坐标
    input [3:0] packet_id;    // 数据包ID
    input [3:0] flit_num;     // Flit数量
    input [95:0] payload;     // 有效载荷
    output [`FLIT_WIDTH-1:0] flit;
    begin
        flit[`FLIT_TYPE_RANGE] = flit_type;
        flit[`DEST_X_RANGE] = dest_x;
        flit[`DEST_Y_RANGE] = dest_y;
        flit[`SRC_X_RANGE] = src_x;
        flit[`SRC_Y_RANGE] = src_y;
        flit[`PACKET_ID_RANGE] = packet_id;
        flit[`FLIT_NUM_RANGE] = flit_num;
        flit[`RESERVED_RANGE] = 14'b0;
        flit[`PAYLOAD_RANGE] = payload;
    end
endtask

// 任务：从指定端口发送一个flit
task send_flit;
    input [2:0] port;  // 0=local, 1=east, 2=west, 3=north, 4=south
    input [`FLIT_WIDTH-1:0] flit_data;
    begin
        @(posedge clk);
        case(port)
            3'd0: begin
                flit_in_data_local <= flit_data;
                flit_in_valid_local <= 1;
                @(posedge clk);
                while(!flit_in_ready_local) @(posedge clk);
                flit_in_valid_local <= 0;
            end
            3'd1: begin
                flit_in_data_east <= flit_data;
                flit_in_valid_east <= 1;
                @(posedge clk);
                while(!flit_in_ready_east) @(posedge clk);
                flit_in_valid_east <= 0;
            end
            3'd2: begin
                flit_in_data_west <= flit_data;
                flit_in_valid_west <= 1;
                @(posedge clk);
                while(!flit_in_ready_west) @(posedge clk);
                flit_in_valid_west <= 0;
            end
            3'd3: begin
                flit_in_data_north <= flit_data;
                flit_in_valid_north <= 1;
                @(posedge clk);
                while(!flit_in_ready_north) @(posedge clk);
                flit_in_valid_north <= 0;
            end
            3'd4: begin
                flit_in_data_south <= flit_data;
                flit_in_valid_south <= 1;
                @(posedge clk);
                while(!flit_in_ready_south) @(posedge clk);
                flit_in_valid_south <= 0;
            end
        endcase
    end
endtask

// 主测试序列
initial begin
    $dumpfile("tb_router.vcd");
    $dumpvars(0, tb_router);
    
    wait(rst_n == 1);  // 等待复位完成
    #50;
    
    $display("========================================");
    $display("Test 1: Local -> East (单flit包)");
    $display("========================================");
    // 当前路由器坐标 (0,0), 发送到 (1,0)
    fork
        begin
            reg [`FLIT_WIDTH-1:0] flit1;
            create_flit(
                `FLIT_TYPE_HEAD_TAIL,  // 单flit包
                2'd1, 2'd0,            // 目标: (1,0) -> 应该路由到East
                2'd0, 2'd0,            // 源: (0,0)
                4'd1,                  // packet_id = 1
                4'd1,                  // flit_num = 1
                96'hAABBCCDD_11223344_55667788, // payload
                flit1
            );
            send_flit(3'd0, flit1);  // 从local端口发送
        end
    join
    
    #100;
    
    $display("========================================");
    $display("Test 2: North -> South (多flit包)");
    $display("========================================");
    // 从北边来的数据，发往南边 (0,-1) -> (0,1)
    fork
        begin
            reg [`FLIT_WIDTH-1:0] flit_head, flit_body, flit_tail;
            
            // HEAD flit
            create_flit(
                `FLIT_TYPE_HEAD,
                2'd0, 2'd1,            // 目标: (0,1) -> 应该路由到South
                2'd0, 2'd0,            // 源: (0,0) - 实际是从(0,-1)来的
                4'd2,                  // packet_id = 2
                4'd3,                  // 总共3个flit
                96'h00000000_00000000_00000001,
                flit_head
            );
            send_flit(3'd3, flit_head);  // 从north端口发送
            
            // BODY flit
            create_flit(
                `FLIT_TYPE_BODY,
                2'd0, 2'd1,
                2'd0, 2'd0,
                4'd2,
                4'd3,
                96'h00000000_00000000_00000002,
                flit_body
            );
            send_flit(3'd3, flit_body);
            
            // TAIL flit
            create_flit(
                `FLIT_TYPE_TAIL,
                2'd0, 2'd1,
                2'd0, 2'd0,
                4'd2,
                4'd3,
                96'h00000000_00000000_00000003,
                flit_tail
            );
            send_flit(3'd3, flit_tail);
        end
    join
    
    #100;
    
    $display("========================================");
    $display("Test 3: Local -> Local (本地通信)");
    $display("========================================");
    // 发送到本地处理器
    fork
        begin
            reg [`FLIT_WIDTH-1:0] flit_local;
            create_flit(
                `FLIT_TYPE_HEAD_TAIL,
                2'd0, 2'd0,            // 目标: (0,0) -> 本地
                2'd0, 2'd0,            // 源: (0,0)
                4'd3,
                4'd1,
                96'hDEADBEEF_CAFEBABE_12345678,
                flit_local
            );
            send_flit(3'd0, flit_local);
        end
    join
    
    #100;
    
    $display("========================================");
    $display("Test 4: 并发测试 - 多个端口同时发送");
    $display("========================================");
    fork
        // Local -> East
        begin
            reg [`FLIT_WIDTH-1:0] flit_le;
            create_flit(`FLIT_TYPE_HEAD_TAIL, 2'd1, 2'd0, 2'd0, 2'd0, 
                       4'd4, 4'd1, 96'h1111_2222_3333, flit_le);
            send_flit(3'd0, flit_le);
        end
        
        // West -> East
        begin
            reg [`FLIT_WIDTH-1:0] flit_we;
            create_flit(`FLIT_TYPE_HEAD_TAIL, 2'd1, 2'd0, 2'd0, 2'd0, 
                       4'd5, 4'd1, 96'h4444_5555_6666, flit_we);
            #5;  // 稍微错开时间
            send_flit(3'd2, flit_we);
        end
        
        // North -> South  
        begin
            reg [`FLIT_WIDTH-1:0] flit_ns;
            create_flit(`FLIT_TYPE_HEAD_TAIL, 2'd0, 2'd1, 2'd0, 2'd0, 
                       4'd6, 4'd1, 96'h7777_8888_9999, flit_ns);
            #10;  // 再错开一点
            send_flit(3'd3, flit_ns);
        end
    join
    
    #200;
    
    $display("========================================");
    $display("All tests completed!");
    $display("========================================");
    $finish;
end

// 监控输出
always @(posedge clk) begin
    if(flit_out_valid_local)
        $display("[%0t] OUTPUT Local: Type=%b Dest=(%0d,%0d) Src=(%0d,%0d) ID=%0d Payload=%h", 
                 $time, flit_out_local[`FLIT_TYPE_RANGE],
                 flit_out_local[`DEST_X_RANGE], flit_out_local[`DEST_Y_RANGE],
                 flit_out_local[`SRC_X_RANGE], flit_out_local[`SRC_Y_RANGE],
                 flit_out_local[`PACKET_ID_RANGE], flit_out_local[`PAYLOAD_RANGE]);
    
    if(flit_out_valid_east)
        $display("[%0t] OUTPUT East: Type=%b Dest=(%0d,%0d) Src=(%0d,%0d) ID=%0d Payload=%h", 
                 $time, flit_out_east[`FLIT_TYPE_RANGE],
                 flit_out_east[`DEST_X_RANGE], flit_out_east[`DEST_Y_RANGE],
                 flit_out_east[`SRC_X_RANGE], flit_out_east[`SRC_Y_RANGE],
                 flit_out_east[`PACKET_ID_RANGE], flit_out_east[`PAYLOAD_RANGE]);
    
    if(flit_out_valid_west)
        $display("[%0t] OUTPUT West: Type=%b Dest=(%0d,%0d) Src=(%0d,%0d) ID=%0d Payload=%h", 
                 $time, flit_out_west[`FLIT_TYPE_RANGE],
                 flit_out_west[`DEST_X_RANGE], flit_out_west[`DEST_Y_RANGE],
                 flit_out_west[`SRC_X_RANGE], flit_out_west[`SRC_Y_RANGE],
                 flit_out_west[`PACKET_ID_RANGE], flit_out_west[`PAYLOAD_RANGE]);
    
    if(flit_out_valid_north)
        $display("[%0t] OUTPUT North: Type=%b Dest=(%0d,%0d) Src=(%0d,%0d) ID=%0d Payload=%h", 
                 $time, flit_out_north[`FLIT_TYPE_RANGE],
                 flit_out_north[`DEST_X_RANGE], flit_out_north[`DEST_Y_RANGE],
                 flit_out_north[`SRC_X_RANGE], flit_out_north[`SRC_Y_RANGE],
                 flit_out_north[`PACKET_ID_RANGE], flit_out_north[`PAYLOAD_RANGE]);
    
    if(flit_out_valid_south)
        $display("[%0t] OUTPUT South: Type=%b Dest=(%0d,%0d) Src=(%0d,%0d) ID=%0d Payload=%h", 
                 $time, flit_out_south[`FLIT_TYPE_RANGE],
                 flit_out_south[`DEST_X_RANGE], flit_out_south[`DEST_Y_RANGE],
                 flit_out_south[`SRC_X_RANGE], flit_out_south[`SRC_Y_RANGE],
                 flit_out_south[`PACKET_ID_RANGE], flit_out_south[`PAYLOAD_RANGE]);
end

// 超时保护
initial begin
    #50000;  // 50us后超时
    $display("ERROR: Simulation timeout!");
    $finish;
end
endmodule