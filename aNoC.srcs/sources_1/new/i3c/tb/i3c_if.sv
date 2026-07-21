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

    logic        slave_drive_low;
    logic        slave_ack_addr;
    logic        slave_read_en;
    int unsigned slave_read_length;
    logic        slave_i2c_read_mode;
    logic        slave_i3c_write_tbit_mode;
    int          slave_i2c_write_ack_count;
    logic        ccc_ack_en;
    logic        ccc_direct_en;
    logic        entdaa_slave_en;
    logic        expect_ccc_target;

    // Independent target-side IBI plan.  The active IBI stimulus publishes
    // these fields before it changes SDA; the protocol scoreboard consumes a
    // separate intent object built from this plan, never the sampled bus data.
    logic        ibi_plan_valid = 1'b0;
    logic [6:0]  ibi_plan_addr = '0;
    logic        ibi_plan_expect_addr_ack = 1'b0;
    logic        ibi_plan_has_mdb = 1'b0;
    logic [7:0]  ibi_plan_mdb = '0;
    logic        ibi_plan_expect_controller_t_low = 1'b0;

    logic [7:0]  slave_read_data [0:3];
    logic [7:0]  slave_dbg_addr_byte;
    logic [7:0]  slave_dbg_ccc_byte;
    logic [7:0]  slave_dbg_write_byte;
    logic [7:0]  slave_dbg_entdaa_da;
    logic        slave_dbg_matched;
    logic        slave_dbg_ack_phase;

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
