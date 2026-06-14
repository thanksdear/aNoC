`include "noc_params.vh"

module route_compute #(
    parameter COORD_WIDTH = 2
)(
    input   [COORD_WIDTH-1:0] dest_x,
    input   [COORD_WIDTH-1:0] dest_y,
    input   [COORD_WIDTH-1:0] cur_x,
    input   [COORD_WIDTH-1:0] cur_y,
    output  reg [4:0]   route_out  // [Local, East, West, North, South]
);

    // 使用参数文件中的独热码定义
    localparam LOCAL = `ONEHOT_LOCAL;
    localparam EAST  = `ONEHOT_EAST;
    localparam WEST  = `ONEHOT_WEST;
    localparam NORTH = `ONEHOT_NORTH;
    localparam SOUTH = `ONEHOT_SOUTH;

    always @(*) begin
        route_out = LOCAL;
        if(dest_x > cur_x)
            route_out = EAST;
        else if(dest_x < cur_x)
            route_out = WEST;
        else if(dest_y > cur_y)
            route_out = NORTH;
        else if(dest_y < cur_y)
            route_out = SOUTH;
        else
            route_out = LOCAL;
    end
endmodule