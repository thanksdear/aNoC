// 同步 FIFO
module sync_fifo #(
    parameter WIDTH = 8,    // 数据位宽
    parameter DEPTH = 8     // FIFO 深度
    )(
 // 写端口
    input   wire    clk,
    input   wire    rst_n,
    input   wire    wr_en,
    input   wire    [WIDTH-1:0] wr_data,
 // 读端口
    input   wire    rd_en,
    output  wire    [WIDTH-1:0] rd_data,

    output  wire    full,
    output  wire    empty    
    );
    localparam ADDR = $clog2(DEPTH);
    reg  [WIDTH-1:0] mem [DEPTH-1:0];
    reg  [ADDR:0]     wr_ptr;
    reg  [ADDR:0]     rd_ptr;

    wire do_wr = wr_en && !full;    
    wire do_rd = rd_en && !empty; 

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
        end else begin
            if (do_wr) begin
                wr_ptr <= wr_ptr + 1;
                mem[wr_ptr[ADDR-1:0]] <= wr_data;
            end
            if (do_rd)
                rd_ptr <= rd_ptr + 1;
        end
    end
      
    assign rd_data = mem[rd_ptr[ADDR-1:0]];
    assign full = (wr_ptr[ADDR] != rd_ptr[ADDR]) &&
                  (wr_ptr[ADDR-1:0] == rd_ptr[ADDR-1:0]);
    assign empty = (rd_ptr == wr_ptr);

endmodule
