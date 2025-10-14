module ram_dp #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4,
    parameter DEPTH = 16
) (
    input wire                   wr_clk,
    input wire                   rst_n,
    input wire [ADDR_WIDTH-1:0]  wr_addr,
    input wire [DATA_WIDTH-1:0]  w_data,
    input wire                   wr_en,
    
    input wire                   rd_clk,
    input wire [ADDR_WIDTH-1:0]  rd_addr,
    input wire                   rd_en,
    output wire [DATA_WIDTH-1:0] r_data
);
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    
    always @(posedge wr_clk ) begin
        if (wr_en) begin
            mem[wr_addr] <= w_data;
        end
    end

    assign  r_data = mem[rd_addr];
endmodule