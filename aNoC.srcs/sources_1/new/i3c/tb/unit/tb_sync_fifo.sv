`timescale 1ns/1ps
`default_nettype none

module tb_sync_fifo;
  localparam int CLK_PERIOD_NS = 10;
  localparam int WIDTH = 32;
  localparam int DEPTH = 8;

  logic clk;
  logic rst_n;
  logic wr_en;
  logic [WIDTH-1:0] wr_data;
  logic rd_en;
  logic [WIDTH-1:0] rd_data;
  logic full;
  logic empty;
  int errors;

  sync_fifo #(
    .WIDTH(WIDTH),
    .DEPTH(DEPTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .wr_en(wr_en),
    .wr_data(wr_data),
    .rd_en(rd_en),
    .rd_data(rd_data),
    .full(full),
    .empty(empty)
  );

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD_NS / 2) clk = ~clk;
  end

  task automatic drive_idle();
    wr_en   <= 1'b0;
    wr_data <= '0;
    rd_en   <= 1'b0;
  endtask

  task automatic check32(input string name, input logic [31:0] got, input logic [31:0] exp);
    if (got !== exp) begin
      errors++;
      $error("%s mismatch: got=0x%08h exp=0x%08h", name, got, exp);
    end else begin
      $display("[%0t] PASS %s: 0x%08h", $time, name, got);
    end
  endtask

  task automatic check1(input string name, input logic got, input logic exp);
    if (got !== exp) begin
      errors++;
      $error("%s mismatch: got=%0b exp=%0b", name, got, exp);
    end else begin
      $display("[%0t] PASS %s: %0b", $time, name, got);
    end
  endtask

  task automatic push(input logic [31:0] data);
    @(posedge clk);
    wr_en   <= 1'b1;
    wr_data <= data;
    rd_en   <= 1'b0;
    @(posedge clk);
    drive_idle();
  endtask

  task automatic pop_no_check();
    @(posedge clk);
    wr_en   <= 1'b0;
    wr_data <= '0;
    rd_en   <= 1'b1;
    @(posedge clk);
    drive_idle();
  endtask

  initial begin
    errors = 0;
    rst_n = 1'b0;
    drive_idle();

    repeat (4) @(posedge clk);
    rst_n <= 1'b1;
    repeat (2) @(posedge clk);

    check1("empty after reset", empty, 1'b1);
    check1("full after reset", full, 1'b0);

    $display("[%0t] T1: single write, show-ahead read", $time);
    push(32'h0324_0000);
    #1;
    check1("T1 empty clears", empty, 1'b0);
    check32("T1 rd_data shows first word", rd_data, 32'h0324_0000);
    pop_no_check();
    #1;
    check1("T1 empty after pop", empty, 1'b1);

    $display("[%0t] T2: two writes keep FIFO order", $time);
    push(32'haaaa_0001);
    push(32'hbbbb_0002);
    #1;
    check32("T2 first visible", rd_data, 32'haaaa_0001);
    pop_no_check();
    #1;
    check32("T2 second visible after first pop", rd_data, 32'hbbbb_0002);
    pop_no_check();
    #1;
    check1("T2 empty after second pop", empty, 1'b1);

    $display("[%0t] T3: write then read on next cycle", $time);
    @(posedge clk);
    wr_en   <= 1'b1;
    wr_data <= 32'hcafe_1234;
    rd_en   <= 1'b0;
    @(posedge clk);
    wr_en   <= 1'b0;
    wr_data <= '0;
    rd_en   <= 1'b1;
    #1;
    check32("T3 rd_data during read cycle", rd_data, 32'hcafe_1234);
    @(posedge clk);
    drive_idle();
    #1;
    check1("T3 empty after read", empty, 1'b1);

    $display("[%0t] T4: simultaneous read/write", $time);
    push(32'h1111_2222);
    @(posedge clk);
    wr_en   <= 1'b1;
    wr_data <= 32'h3333_4444;
    rd_en   <= 1'b1;
    #1;
    check32("T4 old head during simultaneous rd/wr", rd_data, 32'h1111_2222);
    @(posedge clk);
    drive_idle();
    #1;
    check32("T4 new head after simultaneous rd/wr", rd_data, 32'h3333_4444);
    pop_no_check();
    #1;
    check1("T4 empty after final pop", empty, 1'b1);

    if (errors == 0)
      $display("[%0t] TEST PASSED", $time);
    else
      $fatal(1, "TEST FAILED with %0d error(s)", errors);

    repeat (5) @(posedge clk);
    $finish;
  end
endmodule

`default_nettype wire
