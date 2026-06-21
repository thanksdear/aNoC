// ---------- top (不变) ----------
import axi_lite_slave_pkg::*;
module top;
  logic clk = 0;
  always #5 clk = ~clk;
  initial begin
//    $fsdbDumpfile("axi_lite_slave.fsdb");   // 起名: 文件
//    $fsdbDumpvars(0, top);        // ★ 录信号: 是 DumpVARS, 不是 DumpFILE ★
  end

  axi_lite_slave_if vif (clk);
  axi_lite_slave dut(
    .clk(clk),.rst_n(vif.rst_n),
    .awaddr(vif.awaddr),.awvalid(vif.awvalid),.awready(vif.awready),
    .wdata(vif.wdata), .wstrb(vif.wstrb),.wvalid(vif.wvalid),.wready(vif.wready),
    .bresp(vif.bresp),.bvalid(vif.bvalid),.bready(vif.bready),    
    .araddr(vif.araddr),.arvalid(vif.arvalid),.arready(vif.arready),
    .rdata(vif.rdata),.rresp(vif.rresp),.rvalid(vif.rvalid),.rready(vif.rready)
  );
  initial begin
    uvm_config_db#(virtual axi_lite_slave_if)::set(null, "*", "vif", vif);
    run_test("axi_lite_slave_base_test");
  end
endmodule