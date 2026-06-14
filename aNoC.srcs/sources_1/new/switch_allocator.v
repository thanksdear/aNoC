`include "noc_params.vh"

// 交换分配器：解决多个输入端口竞争同一输出端口的冲突
// 为每个输出端口配置一个仲裁器
module switch_allocator (
    input   clk,
    input   rst_n,

    // 5个输入端口的路由请求 [0=local, 1=east, 2=west, 3=north, 4=south]
    input   [4:0]   route_req_local,  // 输入0的请求（独热码）
    input   [4:0]   route_req_east,  // 输入1的请求
    input   [4:0]   route_req_west,  // 输入2的请求
    input   [4:0]   route_req_north,  // 输入3的请求
    input   [4:0]   route_req_south,  // 输入4的请求

    // 5个输入端口的授权信号 [0=local, 1=east, 2=west, 3=north, 4=south]
    output  [4:0]   grant_local,      // 输入0被授权去哪个输出
    output  [4:0]   grant_east,      // 输入1被授权去哪个输出
    output  [4:0]   grant_west,      // 输入2被授权去哪个输出
    output  [4:0]   grant_north,      // 输入3被授权去哪个输出
    output  [4:0]   grant_south       // 输入4被授权去哪个输出
);


wire    [4:0]        reqs_to_0;
wire    [4:0]        reqs_to_1;
wire    [4:0]        reqs_to_2;
wire    [4:0]        reqs_to_3;
wire    [4:0]        reqs_to_4;

assign  reqs_to_0 = {route_req_south[0],route_req_north[0],route_req_west[0],
                     route_req_east[0],route_req_local[0]};
assign  reqs_to_1 = {route_req_south[1],route_req_north[1],route_req_west[1],
                     route_req_east[1],route_req_local[1]};
assign  reqs_to_2 = {route_req_south[2],route_req_north[2],route_req_west[2],
                     route_req_east[2],route_req_local[2]};
assign  reqs_to_3 = {route_req_south[3],route_req_north[3],route_req_west[3],
                     route_req_east[3],route_req_local[3]};
assign  reqs_to_4 = {route_req_south[4],route_req_north[4],route_req_west[4],
                     route_req_east[4],route_req_local[4]};

wire    [4:0]      gnts_from_0;
wire    [4:0]      gnts_from_1;
wire    [4:0]      gnts_from_2;
wire    [4:0]      gnts_from_3;
wire    [4:0]      gnts_from_4;

assign  grant_local= {gnts_from_4[0],gnts_from_3[0],gnts_from_2[0],
                       gnts_from_1[0],gnts_from_0[0]};
assign  grant_east = {gnts_from_4[1],gnts_from_3[1],gnts_from_2[1],
                       gnts_from_1[1],gnts_from_0[1]};
assign  grant_west = {gnts_from_4[2],gnts_from_3[2],gnts_from_2[2],
                       gnts_from_1[2],gnts_from_0[2]};
assign  grant_north = {gnts_from_4[3],gnts_from_3[3],gnts_from_2[3],
                       gnts_from_1[3],gnts_from_0[3]};
assign  grant_south = {gnts_from_4[4],gnts_from_3[4],gnts_from_2[4],
                       gnts_from_1[4],gnts_from_0[4]};                     
arbiter  arb_to_0 (
    .clk                     (  clk          ),
    .rst_n                   (  rst_n        ),
    .reqs                    (  reqs_to_0    ),

    .gnts                    (  gnts_from_0  )
);

arbiter  arb_to_1 (
    .clk                     (  clk          ),
    .rst_n                   (  rst_n        ),
    .reqs                    (  reqs_to_1    ),

    .gnts                    (  gnts_from_1  )
);

arbiter  arb_to_2 (
    .clk                     (  clk          ),
    .rst_n                   (  rst_n        ),
    .reqs                    (  reqs_to_2    ),

    .gnts                    (  gnts_from_2  )
);

arbiter  arb_to_3 (
    .clk                     (  clk          ),
    .rst_n                   (  rst_n        ),
    .reqs                    (  reqs_to_3    ),

    .gnts                    (  gnts_from_3  )
);

arbiter  arb_to_4 (
    .clk                     (  clk          ),
    .rst_n                   (  rst_n        ),
    .reqs                    (  reqs_to_4    ),

    .gnts                    (  gnts_from_4  )
);
endmodule