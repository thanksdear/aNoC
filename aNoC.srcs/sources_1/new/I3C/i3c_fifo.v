module i3c_fifo #(
    parameter DATA_W = 8,
    parameter DEPTH  = 16,
    parameter CNT_W  = 5        // must hold 0..DEPTH inclusive
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             wr_en,
    input  wire [DATA_W-1:0] wr_data,
    input  wire             rd_en,
    output wire [DATA_W-1:0] rd_data,
    output wire             full,
    output wire             empty,
    output wire [CNT_W-1:0] count
);

    localparam ADDR_W = $clog2(DEPTH);

    reg [DATA_W-1:0] mem [0:DEPTH-1];
    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W-1:0] rd_ptr;
    reg [CNT_W-1:0]  cnt;

    assign full    = (cnt == DEPTH[CNT_W-1:0]);
    assign empty   = (cnt == {CNT_W{1'b0}});
    assign count   = cnt;
    // First-word fall-through: rd_data is always combinationally driven by rd_ptr.
    // The caller reads rd_data and then pulses rd_en to consume (advance rd_ptr).
    assign rd_data = empty ? {DATA_W{1'b0}} : mem[rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr  <= {ADDR_W{1'b0}};
            rd_ptr  <= {ADDR_W{1'b0}};
            cnt     <= {CNT_W{1'b0}};
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr      <= (wr_ptr == DEPTH[ADDR_W-1:0] - {{(ADDR_W-1){1'b0}}, 1'b1})
                               ? {ADDR_W{1'b0}} : wr_ptr + {{(ADDR_W-1){1'b0}}, 1'b1};
            end

            if (rd_en && !empty) begin
                rd_ptr  <= (rd_ptr == DEPTH[ADDR_W-1:0] - {{(ADDR_W-1){1'b0}}, 1'b1})
                           ? {ADDR_W{1'b0}} : rd_ptr + {{(ADDR_W-1){1'b0}}, 1'b1};
            end

            if (wr_en && !full && !(rd_en && !empty))
                cnt <= cnt + {{(CNT_W-1){1'b0}}, 1'b1};
            else if (rd_en && !empty && !(wr_en && !full))
                cnt <= cnt - {{(CNT_W-1){1'b0}}, 1'b1};
        end
    end

endmodule
