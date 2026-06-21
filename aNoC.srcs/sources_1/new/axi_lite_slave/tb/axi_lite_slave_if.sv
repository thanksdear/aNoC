interface axi_lite_slave_if (input logic clk);
    logic rst_n;
    logic [7:0] awaddr;logic awvalid;logic awready;
    logic [31:0] wdata;logic [3:0] wstrb;logic wvalid;logic wready;
    logic [1:0] bresp;logic bvalid;logic bready;
    logic [7:0] araddr;logic arvalid;logic arready;
    logic [31:0] rdata;logic [1:0] rresp;logic rvalid;logic rready;
  // 驱动视角:我驱动的是 output, 我观察的是 input
  clocking drv_cb @(posedge clk);
    default input #1step output #0;
    output awaddr, awvalid, wdata, wstrb, wvalid, bready, araddr, arvalid, rready;
    input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid;
  endclocking

  // 监视视角:全是 input(只看不驱动)
  clocking mon_cb @(posedge clk);
    default input #1step;
    input awaddr, awvalid, awready, wdata, wstrb, wvalid, wready, bresp, bvalid, bready,
          araddr, arvalid, arready, rdata, rresp, rvalid, rready;
  endclocking

  modport DRV (clocking drv_cb, output rst_n);   // 给 driver 的方向打包
  modport MON (clocking mon_cb);                  // 给 monitor 的方向打包
endinterface