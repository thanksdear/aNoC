`include "noc_params.vh"
//grant为5位独热码，第几位是1，就走哪个out，判断grant的第0位，哪个是1就哪个走outdata0
//5次always，先判断谁走第一个outdata0，第二个outdata1，第三个outdata2
module crossbar (
    input   [`FLIT_WIDTH-1:0]  in_data_local,
    input   [`FLIT_WIDTH-1:0]  in_data_east,
    input   [`FLIT_WIDTH-1:0]  in_data_west,
    input   [`FLIT_WIDTH-1:0]  in_data_north,
    input   [`FLIT_WIDTH-1:0]  in_data_south,

    input   [4:0]              grant_local,//data0往哪个方向走
    input   [4:0]              grant_east,
    input   [4:0]              grant_west,
    input   [4:0]              grant_north,
    input   [4:0]              grant_south,

    output  reg [`FLIT_WIDTH-1:0]  out_data_local,
    output  reg [`FLIT_WIDTH-1:0]  out_data_east,
    output  reg [`FLIT_WIDTH-1:0]  out_data_west,
    output  reg [`FLIT_WIDTH-1:0]  out_data_north,
    output  reg [`FLIT_WIDTH-1:0]  out_data_south,

    output  wire                   out_valid_local,
    output  wire                   out_valid_east,
    output  wire                   out_valid_west,
    output  wire                   out_valid_north,
    output  wire                   out_valid_south
);

always@(*)begin
    if(grant_local[0])
        out_data_local = in_data_local;
    else if(grant_east[0])
        out_data_local = in_data_east;
    else if(grant_west[0])
        out_data_local = in_data_west;
    else if(grant_north[0])
        out_data_local = in_data_north;
    else if(grant_south[0])
        out_data_local = in_data_south;
    else
        out_data_local = {`FLIT_WIDTH{1'b0}};
end

always@(*)begin
    if(grant_local[1])
        out_data_east = in_data_local;
    else if(grant_east[1])
        out_data_east = in_data_east;
    else if(grant_west[1])
        out_data_east = in_data_west;
    else if(grant_north[1])
        out_data_east = in_data_north;
    else if(grant_south[1])
        out_data_east = in_data_south;
    else
        out_data_east = {`FLIT_WIDTH{1'b0}};
end
always@(*)begin
    if(grant_local[2])
        out_data_west = in_data_local;
    else if(grant_east[2])
        out_data_west = in_data_east;
    else if(grant_west[2])
        out_data_west = in_data_west;
    else if(grant_north[2])
        out_data_west = in_data_north;
    else if(grant_south[2])
        out_data_west = in_data_south;
    else
        out_data_west = {`FLIT_WIDTH{1'b0}};
end
always@(*)begin
    if(grant_local[3])
        out_data_north = in_data_local;
    else if(grant_east[3])
        out_data_north = in_data_east;
    else if(grant_west[3])
        out_data_north = in_data_west;
    else if(grant_north[3])
        out_data_north = in_data_north;
    else if(grant_south[3])
        out_data_north = in_data_south;
    else
        out_data_north = {`FLIT_WIDTH{1'b0}};
end
always@(*)begin
    if(grant_local[4])
        out_data_south = in_data_local;
    else if(grant_east[4])
        out_data_south = in_data_east;
    else if(grant_west[4])
        out_data_south = in_data_west;
    else if(grant_north[4])
        out_data_south = in_data_north;
    else if(grant_south[4])
        out_data_south = in_data_south;
    else
        out_data_south = {`FLIT_WIDTH{1'b0}};
end

// 新增：Valid信号生成
// 输出端口0有valid：任意一个输入被授权到输出0
assign out_valid_local = grant_local[0] | grant_east[0] | grant_west[0] | grant_north[0] | grant_south[0];
assign out_valid_east  = grant_local[1] | grant_east[1] | grant_west[1] | grant_north[1] | grant_south[1];
assign out_valid_west  = grant_local[2] | grant_east[2] | grant_west[2] | grant_north[2] | grant_south[2];
assign out_valid_north = grant_local[3] | grant_east[3] | grant_west[3] | grant_north[3] | grant_south[3];
assign out_valid_south = grant_local[4] | grant_east[4] | grant_west[4] | grant_north[4] | grant_south[4];

endmodule