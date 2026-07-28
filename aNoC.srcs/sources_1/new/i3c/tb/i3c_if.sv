interface i3c_if (input logic clk);
    logic rst_n;
    // Monotonic testbench reset generation.  The APB monitor advances this
    // before publishing a CTRL.sw_rst write, and also on hard reset.  Passive
    // bus/target threads use it to abort work that the DUT's internal reset
    // terminates without necessarily producing a bus STOP.
    longint unsigned tb_reset_epoch = 0;
    logic        psel;logic penable;logic pwrite;
    logic [11:0] paddr;
    logic [31:0] pwdata;logic [3:0] pstrb;
    logic [31:0] prdata;
    logic        pready;logic pslverr;
    logic        scl_in;logic scl_oe;logic scl_out;
    logic        sda_in;logic sda_oe;logic sda_out;
    logic        irq;

    // Target model's only electrical contribution to the shared SDA line.
    // Protocol configuration stays inside i3c_target_driver.
    logic        target_drive_low;
    // Dedicated fault-injection contribution. It is separate from legal
    // target driving so intentional corruption is not reported as contention.
    logic        target_fault_drive_low;

    // Read-only target observations used by directed synchronization and
    // diagnostics.  These are observations, not target stimulus controls.
    logic [7:0]  target_dbg_addr_byte;
    logic [7:0]  target_dbg_ccc_byte;
    logic [7:0]  target_dbg_write_byte;
    logic        target_dbg_ack_phase;

  // 驱动视角:我驱动的是 output, 我观察的是 input
  clocking drv_cb @(posedge clk);
    default input #1step output #0;
    output psel, penable, pwrite, paddr, pwdata, pstrb;
    input  prdata, pready, pslverr, scl_oe, scl_out, sda_oe, sda_out, irq;
  endclocking

  // 监视视角:全是 input(只看不驱动)
  clocking mon_cb @(posedge clk);
    default input #1step;
    input rst_n, psel, penable, pwrite, paddr, pwdata, pstrb, prdata, pready,
          pslverr, scl_in, scl_oe, scl_out, sda_in, sda_oe, sda_out, irq;
  endclocking

  modport DRV (clocking drv_cb, output rst_n);   // 给 driver 的方向打包
  modport MON (clocking mon_cb);                  // 给 monitor 的方向打包
endinterface
