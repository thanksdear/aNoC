// ---------- top ----------
`include "uvm_macros.svh"
import i3c_pkg::*;
module top;
  logic clk = 0;
  always #5 clk = ~clk;

  i3c_if vif (clk);

  assign vif.scl_in = vif.scl_oe ? vif.scl_out : 1'b1;
  assign vif.sda_in = (vif.slave_drive_low || (vif.sda_oe && !vif.sda_out)) ? 1'b0 : 1'b1;

  i3c_top dut(
    .PCLK(clk),
    .PRESETn(vif.rst_n),
    .PSEL(vif.psel),
    .PENABLE(vif.penable),
    .PWRITE(vif.pwrite),
    .PADDR(vif.paddr),
    .PWDATA(vif.pwdata),
    .PSTRB(vif.pstrb),
    .PRDATA(vif.prdata),
    .PREADY(vif.pready),
    .PSLVERR(vif.pslverr),
    .SCL_IN(vif.scl_in),
    .SCL_OE(vif.scl_oe),
    .SCL_OUT(vif.scl_out),
    .SDA_IN(vif.sda_in),
    .SDA_OE(vif.sda_oe),
    .SDA_OUT(vif.sda_out),
    .IRQ(vif.irq)
  );
  initial begin
    uvm_config_db#(virtual i3c_if)::set(null, "*", "vif", vif);
    run_test();
  end
endmodule
