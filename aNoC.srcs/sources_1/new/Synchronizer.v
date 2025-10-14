// 两级触发器同步器
module synchronizer #(
    parameter WIDTH = 4
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] data_in,
    output wire [WIDTH-1:0] data_out
);
    reg [WIDTH-1:0] sync_reg1, sync_reg2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_reg1 <= 0;
            sync_reg2 <= 0;
        end else begin
            sync_reg1 <= data_in;
            sync_reg2 <= sync_reg1;
        end
    end
    assign data_out = sync_reg2;
endmodule