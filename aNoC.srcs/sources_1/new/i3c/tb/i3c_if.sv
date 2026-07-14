interface i3c_if (input logic clk);
    logic rst_n;
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
    logic        slave_i2c_read_mode;
    logic        slave_i3c_write_tbit_mode;
    int          slave_i2c_write_ack_count;
    logic        ccc_ack_en;
    logic        ccc_direct_en;
    logic        entdaa_slave_en;
    logic        expect_ccc_target;
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
