`timescale 1ns/100ps
module tb();
logic clk;logic rst_n;
logic [7:0] awaddr;logic awvalid;logic awready;
logic [31:0] wdata;logic [3:0] wstrb;logic wvalid;logic wready;
logic [1:0] bresp;logic bvalid;logic bready;
logic [7:0] araddr;logic arvalid;logic arready;
logic [31:0] rdata;logic [1:0] rresp;logic rvalid;logic rready;
logic [31:0] rd;
axi_lite_slave dut(
    .clk(clk),.rst_n(rst_n),
    .awaddr(awaddr),.awvalid(awvalid),.awready(awready),
    .wdata(wdata), .wstrb(wstrb),.wvalid(wvalid),.wready(wready),
    .bresp(bresp),.bvalid(bvalid),.bready(bready),    
    .araddr(araddr),.arvalid(arvalid),.arready(arready),
    .rdata(rdata),.rresp(rresp),.rvalid(rvalid),.rready(rready)
);

initial begin
    clk = 0;
    forever #5 clk = ~clk;
end
task asyaxi_write(input [7:0] addr,input [31:0] data,input [3:0] strb);
    @(posedge clk);
    awaddr <= addr; awvalid <= 1;
    do@(posedge clk);while(!awready);   // 等 AW 握手完成
    awvalid <= 0;
    repeat(5)@(posedge clk);            // 延迟 5 拍再发 W
    wdata <= data; wstrb <= strb; wvalid <= 1;
    bready <= 1;
    do@(posedge clk);while(!wready);    // 等 W 握手完成
    wvalid <= 0;
    do@(posedge clk);while(!bvalid);    // 等 B 响应
    bready <= 0;
endtask

task axi_write(input [7:0] addr,input [31:0] data,input [3:0] strb);
    @(posedge clk);
    awaddr <= addr; awvalid <= 1;
    wdata <= data; wstrb <= strb;wvalid <= 1;
    bready <= 1;
    do@(posedge clk);while (!(awready && wready)); 
    awvalid <= 0; wvalid <= 0;
    do@(posedge clk);while (!bvalid);
    bready <= 0;
endtask

task axi_read(input [7:0] addr,output [31:0] data);
    @(posedge clk);
    araddr <= addr;arvalid <= 1;
    rready <= 1;
    do@(posedge clk);while (!arready);
    arvalid <= 0;
    do@(posedge clk);while(!rvalid);
    data = rdata;
    rready <= 0;
endtask

initial begin
    rst_n = 0;
    awaddr = 0;awvalid = 0; wdata = 0;wstrb = 0;wvalid=0;
    bready = 0;araddr = 0; arvalid = 0;rready = 0;
    rd = 0;
    repeat(3) @(posedge clk);
    rst_n = 1;
    //=======================================================//
    axi_write(8'h00,32'h12345678,4'b1111);
    axi_read(8'h00,rd);
    if(rd == 32'h12345678) $display("PASS addr=04, rd=%d",rd);
    else $display("Fail addr=04, rd!=%d,exp=32'h12345678",rd);
    //=======================================================//
    axi_write(8'h04,32'h12345678,4'b1000);
    axi_read(8'h04,rd);
    if(rd == 32'h12000000) $display("PASS addr=04, rd=%d",rd);
    else $display("Fail addr=04, rd!=%d,exp=32'h12000000",rd);
    //=======================================================//
    asyaxi_write(8'h08,32'h12345678,4'b1111);
    axi_read(8'h08,rd);
    if(rd == 32'h12345678) $display("PASS addr=04, rd=%d",rd);
    else $display("Fail addr=04, rd!=%d,exp=32'h12345678",rd); 
    //=======================================================//
    axi_write(8'h0c,32'hAAAA_0000,4'b1111);
    axi_write(8'h10,32'hBBBB_1111,4'b1111);
    axi_write(8'h14,32'hCCCC_2222,4'b1111);
    axi_read(8'h0c,rd);
    if(rd==32'hAAAA_0000) $display("PASS @0c = %h", rd);
    else $display("Fail @0c = %h, exp=32'hAAAA_0000", rd);
    axi_read(8'h10,rd);
    if(rd==32'hBBBB_1111) $display("PASS @10 = %h", rd);
    else $display("Fail @10 = %h, exp=32'hBBBB_1111", rd);
    axi_read(8'h14,rd);
    if(rd==32'hCCCC_2222) $display("PASS @14 = %h", rd);
    else $display("Fail @14 = %h, exp=32'hCCCC_2222", rd);
    //=======================================================//
    axi_write(8'h3c,32'h3c3c_3c3c,4'b1111);
    axi_read(8'h3c,rd);
    if(rd==32'h3c3c_3c3c) $display("PASS @0c = %h", rd);
    else $display("Fail @0c = %h, exp=32'h3c3c_3c3c", rd); 
    axi_write(8'h40,32'h4040_4040,4'b1111);
    axi_read(8'h40,rd);
    if(rd==32'h4040_4040) $display("PASS @0c = %h", rd);
    else $display("Fail @0c = %h, exp=32'hAAAA_0000", rd);
    //=======================================================//    
    axi_read(8'h00,rd);
    if(rd==32'h4040_4040) $display("PASS @00 = %h", rd);
    else $display("Fail @00 = %h, exp=32'hAAAA_0000", rd);
    repeat(5) @(posedge clk);
    $display("==done==");
    $finish;
end

endmodule