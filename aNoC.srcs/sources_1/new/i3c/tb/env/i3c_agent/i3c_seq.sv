class i3c_seq extends uvm_sequence #(i3c_txn);
  `uvm_object_utils(i3c_seq)

  localparam bit [7:0] REG_BUS_TIMING_0   = 8'h00;
  localparam bit [7:0] REG_BUS_TIMING_1   = 8'h04;
  localparam bit [7:0] REG_CTRL           = 8'h08;
  localparam bit [7:0] REG_STATUS         = 8'h0c;
  localparam bit [7:0] REG_IBI_STATUS     = 8'h10;
  localparam bit [7:0] REG_ERR_STATUS     = 8'h14;
  localparam bit [7:0] REG_ENTDAA_STATUS  = 8'h18;
  localparam bit [7:0] REG_ENTDAA_PID_LO  = 8'h1c;
  localparam bit [7:0] REG_ENTDAA_PID_HI  = 8'h30;
  localparam bit [7:0] CMD_PORT           = 8'h20;
  localparam bit [7:0] RESP_PORT          = 8'h24;
  localparam bit [7:0] TX_PORT            = 8'h28;
  localparam bit [7:0] RX_PORT            = 8'h2c;

  localparam bit [6:0] SLAVE_ADDR         = 7'h12;
  localparam bit [7:0] CCC_ENEC           = 8'h00;
  localparam bit [7:0] CCC_ENTDAA         = 8'h07;
  localparam bit [7:0] CCC_GETSTATUS      = 8'h90;
  localparam bit [7:0] CCC_SETDASA        = 8'h87;
  localparam bit [6:0] NEW_DYNAMIC_ADDR   = 7'h22;
  localparam bit [63:0] ENTDAA_ID         = 64'h1234_5678_9abc_de01;

  virtual i3c_if vif;

  function new(string name = "i3c_seq");
    super.new(name);
  endfunction

  task pre_body();
    if (vif == null) begin
      if (!uvm_config_db#(virtual i3c_if)::get(null, "*", "vif", vif))
        `uvm_fatal("SEQ", "sequence 拿不到 vif")
    end
  endtask

  task send_apb(input op_e op, input bit [7:0] addr,
                input bit [31:0] data = '0, input bit [3:0] strb = 4'hf);
    i3c_txn tr = i3c_txn::type_id::create("tr");
    start_item(tr);
    tr.op = op;
    tr.addr = addr;
    tr.data = data;
    tr.strb = strb;
    tr.start_delay = 0;
    finish_item(tr);
  endtask

  task apb_read(input bit [7:0] addr, output bit [31:0] data);
    i3c_txn tr = i3c_txn::type_id::create("rd_tr");
    start_item(tr);
    tr.op = RD;
    tr.addr = addr;
    tr.data = '0;
    tr.strb = 4'h0;
    tr.start_delay = 0;
    finish_item(tr);
    data = tr.data;
  endtask

  task expect_eq(input string name, input bit [31:0] got, input bit [31:0] exp,
                 input bit [31:0] mask = 32'hffff_ffff);
    if ((got & mask) !== (exp & mask))
      `uvm_error("CHK", $sformatf("%s mismatch: got=0x%08h exp=0x%08h mask=0x%08h",
                                  name, got, exp, mask))
    else
      `uvm_info("CHK", $sformatf("%s PASS: 0x%08h", name, got & mask), UVM_LOW)
  endtask

  task cfg_i3c_mode(input bit [15:0] scl_high = 16'd4,
                    input bit [15:0] scl_low  = 16'd4,
                    input bit [15:0] sda_hold = 16'd2);
    send_apb(WR, REG_BUS_TIMING_0, {scl_high, scl_low});
    send_apb(WR, REG_BUS_TIMING_1, {16'd0, sda_hold});
    send_apb(WR, REG_CTRL, 32'h0000_0003);
  endtask

  task cfg_i2c_mode();
    send_apb(WR, REG_CTRL, 32'h0000_0002);
  endtask

  task wait_status_idle();
    bit [31:0] status;
    int timeout;

    timeout = 2000;
    do begin
      apb_read(REG_STATUS, status);
      timeout--;
      if (timeout == 0) begin
        `uvm_error("TIMEOUT", "Timeout waiting for STATUS.busy to assert")
        return;
      end
    end while (!status[0]);

    timeout = 2000;
    do begin
      apb_read(REG_STATUS, status);
      timeout--;
      if (timeout == 0) begin
        `uvm_error("TIMEOUT", "Timeout waiting for STATUS.busy to deassert")
        return;
      end
    end while (status[0]);
  endtask

  task wait_irq_asserted();
    int timeout = 2000;
    while (!vif.irq) begin
      @(posedge vif.clk);
      timeout--;
      if (timeout == 0) begin
        `uvm_error("TIMEOUT", "Timeout waiting for IRQ")
        return;
      end
    end
  endtask

  extern task send_ibi(bit [6:0] addr, bit has_mdb, bit [7:0] mdb);

  function bit [31:0] private_cmd(bit [6:0] addr, bit rw, bit [7:0] len);
    private_cmd = '0;
    private_cmd[31:24] = len;
    private_cmd[23:17] = addr;
    private_cmd[16]    = rw;
    private_cmd[1]     = 1'b0;
    private_cmd[0]     = 1'b0;
  endfunction

  function bit [31:0] ccc_cmd(bit is_direct, bit [7:0] code,
                              bit [6:0] addr, bit rw, bit [7:0] len);
    ccc_cmd = '0;
    ccc_cmd[31:24] = len;
    ccc_cmd[23:17] = addr;
    ccc_cmd[16]    = rw;
    ccc_cmd[15:8]  = code;
    ccc_cmd[1]     = 1'b1;
    ccc_cmd[0]     = is_direct;
  endfunction

  task body();
    bit [31:0] rdata;
    cfg_i3c_mode(16'd6, 16'd6, 16'd2);
    apb_read(REG_BUS_TIMING_0, rdata);
    expect_eq("BUS_TIMING_0", rdata, {16'd6, 16'd6});
    apb_read(REG_BUS_TIMING_1, rdata);
    expect_eq("BUS_TIMING_1", rdata, 32'd2, 32'h0000_ffff);
    apb_read(REG_CTRL, rdata);
    expect_eq("CTRL", rdata, 32'h0000_0003, 32'h0000_000f);
  endtask
endclass

class i3c_apb_reg_access_seq extends i3c_seq;
  `uvm_object_utils(i3c_apb_reg_access_seq)
  function new(string name = "i3c_apb_reg_access_seq"); super.new(name); endfunction
  task body();
    bit [31:0] rdata;
    send_apb(WR, REG_CTRL, 32'h0000_0000);
    apb_read(REG_CTRL, rdata);
    expect_eq("apb CTRL disabled", rdata, 32'h0, 32'h1f);
    send_apb(WR, REG_CTRL, 32'h0000_0013);
    cfg_i3c_mode(16'd5, 16'd7, 16'd3);
    apb_read(REG_BUS_TIMING_0, rdata);
    expect_eq("apb BUS_TIMING_0", rdata, {16'd5, 16'd7});
    apb_read(REG_BUS_TIMING_1, rdata);
    expect_eq("apb BUS_TIMING_1", rdata, 32'd3, 32'h0000_ffff);
    apb_read(REG_CTRL, rdata);
    expect_eq("apb CTRL", rdata, 32'h3, 32'hf);
  endtask
endclass

class i3c_apb_strb_seq extends i3c_seq;
  `uvm_object_utils(i3c_apb_strb_seq)
  function new(string name = "i3c_apb_strb_seq"); super.new(name); endfunction

  function bit [31:0] apply_strb_zero(input bit [31:0] data, input bit [3:0] strb);
    apply_strb_zero = {
      strb[3] ? data[31:24] : 8'h00,
      strb[2] ? data[23:16] : 8'h00,
      strb[1] ? data[15:8]  : 8'h00,
      strb[0] ? data[7:0]   : 8'h00
    };
  endfunction

  task run_strb_case(input bit [3:0] strb);
    bit [31:0] rdata;
    bit [31:0] wdata;
    bit [31:0] exp;

    wdata = {8'h10 + strb, 8'h20 + strb, 8'h30 + strb, 8'h40 + strb};
    apb_read(REG_BUS_TIMING_0, exp);
    for (int i = 0; i < 4; i++)
      if (strb[i])
        exp[i*8 +: 8] = wdata[i*8 +: 8];
    send_apb(WR, REG_BUS_TIMING_0, wdata, strb);
    apb_read(REG_BUS_TIMING_0, rdata);
    expect_eq($sformatf("APB STRB BUS_TIMING_0 strb_%04b", strb), rdata, exp);
  endtask

  task body();
    bit [31:0] rdata;

    // Exercise every non-zero, non-full byte strobe bin on a 32-bit RW register.
    send_apb(WR, REG_BUS_TIMING_0, 32'h0000_0000, 4'hf);
    run_strb_case(4'b0001);
    run_strb_case(4'b0010);
    run_strb_case(4'b0011);
    run_strb_case(4'b0100);
    run_strb_case(4'b0101);
    run_strb_case(4'b0110);
    run_strb_case(4'b0111);
    run_strb_case(4'b1000);
    run_strb_case(4'b1001);
    run_strb_case(4'b1010);
    run_strb_case(4'b1011);
    run_strb_case(4'b1100);
    run_strb_case(4'b1101);
    run_strb_case(4'b1110);
    run_strb_case(4'b1111);

    // BUS_TIMING_1 has only low 16 valid bits.
    send_apb(WR, REG_BUS_TIMING_1, 32'h0000_0000, 4'hf);
    send_apb(WR, REG_BUS_TIMING_1, 32'h0000_0055, 4'b0001);
    apb_read(REG_BUS_TIMING_1, rdata);
    expect_eq("APB STRB BUS_TIMING_1 byte0", rdata, 32'h0000_0055, 32'h0000_ffff);

    send_apb(WR, REG_BUS_TIMING_1, 32'h0000_6600, 4'b0010);
    apb_read(REG_BUS_TIMING_1, rdata);
    expect_eq("APB STRB BUS_TIMING_1 byte1", rdata, 32'h0000_6655, 32'h0000_ffff);

    // CTRL only uses low byte, but byte0 strobe should still update it.
    send_apb(WR, REG_CTRL, 32'h0000_0003, 4'b0001);
    apb_read(REG_CTRL, rdata);
    expect_eq("APB STRB CTRL byte0", rdata, 32'h0000_0003, 32'h0000_001f);
  endtask
endclass

class i3c_bus_timing_seq extends i3c_seq;
  `uvm_object_utils(i3c_bus_timing_seq)
  function new(string name = "i3c_bus_timing_seq"); super.new(name); endfunction
  task body();
    bit [31:0] rdata;
    cfg_i3c_mode(16'd5, 16'd9, 16'd3);
    apb_read(REG_BUS_TIMING_0, rdata);
    expect_eq("timing SCL high/low", rdata, {16'd5, 16'd9});
    apb_read(REG_BUS_TIMING_1, rdata);
    expect_eq("timing SDA hold", rdata, 32'd3, 32'hffff);
    send_apb(WR, TX_PORT, 32'h0000_005a);
    vif.slave_ack_addr <= 1'b1;
    send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b0, 8'd1));
    wait_status_idle();
    vif.slave_ack_addr <= 1'b0;
    apb_read(RESP_PORT, rdata);
    expect_eq("timing transfer response", rdata, 32'h0, 32'h3);
  endtask
endclass

class i3c_sdr_private_write_seq extends i3c_seq;
  `uvm_object_utils(i3c_sdr_private_write_seq)
  function new(string name = "i3c_sdr_private_write_seq"); super.new(name); endfunction
  task body();
    bit [31:0] rdata;
    cfg_i3c_mode();
    send_apb(WR, TX_PORT, 32'h0000_00a5);
    send_apb(WR, TX_PORT, 32'h0000_005a);
    send_apb(WR, TX_PORT, 32'h0000_00c3);
    vif.slave_ack_addr <= 1'b1;
    send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b0, 8'd3));
    wait_status_idle();
    vif.slave_ack_addr <= 1'b0;
    apb_read(RESP_PORT, rdata);
    expect_eq("SDR private write response", rdata, 32'h0, 32'h3);
    apb_read(REG_ERR_STATUS, rdata);
    expect_eq("SDR private write ERR_STATUS", rdata, 32'h0, 32'h3);
  endtask
endclass

class i3c_sdr_private_write_len4_seq extends i3c_seq;
  `uvm_object_utils(i3c_sdr_private_write_len4_seq)
  function new(string name = "i3c_sdr_private_write_len4_seq"); super.new(name); endfunction
  task body();
    bit [31:0] rdata;
    cfg_i3c_mode();
    send_apb(WR, TX_PORT, 32'h0000_0010);
    send_apb(WR, TX_PORT, 32'h0000_0020);
    send_apb(WR, TX_PORT, 32'h0000_0030);
    send_apb(WR, TX_PORT, 32'h0000_0040);
    vif.slave_ack_addr <= 1'b1;
    send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b0, 8'd4));
    wait_status_idle();
    vif.slave_ack_addr <= 1'b0;
    apb_read(RESP_PORT, rdata);
    expect_eq("SDR private write len4 response", rdata, 32'h0, 32'h3);
  endtask
endclass

class i3c_cmd_before_tx_seq extends i3c_seq;
  `uvm_object_utils(i3c_cmd_before_tx_seq)
  function new(string name = "i3c_cmd_before_tx_seq"); super.new(name); endfunction

  task body();
    bit [31:0] rdata;

    cfg_i3c_mode();
    vif.slave_ack_addr <= 1'b1;
    vif.slave_i2c_write_ack_count <= 2;
    vif.slave_i3c_write_tbit_mode <= 1'b1;

    // The RTL is allowed to accept a descriptor before its payload.  It must
    // finish the address and then remain busy in S_DATA_WR until TX arrives.
    send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b0, 8'd2));
    wait (vif.slave_dbg_ack_phase === 1'b1);

    // 地址 ACK 必须等到下一次 SCL 下降沿才能安全释放；否则 SDA 在 SCL 高时
    // 上升会被误认为 STOP。此时 TX FIFO 还是空的，RTL 停在 S_DATA_WR，尚不
    // 会产生下一次 SCL 下降沿，因此不能在写首个 TX byte 前等待 ACK phase 清零。
    repeat (4) @(posedge vif.clk);
    apb_read(REG_STATUS, rdata);
    expect_eq("CMD-before-TX waits after address", rdata,
              32'h0000_0001, 32'h0000_0001);

    send_apb(WR, TX_PORT, 32'h0000_00d1);
    // 首个 TX byte 到达后 RTL 才会继续拉低 SCL；target 随即释放地址 ACK。
    wait (vif.slave_dbg_ack_phase === 1'b0);
    wait (vif.slave_dbg_write_byte === 8'hd1);
    apb_read(REG_STATUS, rdata);
    expect_eq("CMD-before-TX waits for byte1", rdata,
              32'h0000_0001, 32'h0000_0001);

    send_apb(WR, TX_PORT, 32'h0000_00e2);
    wait_status_idle();
    vif.slave_ack_addr <= 1'b0;
    vif.slave_i2c_write_ack_count <= 0;
    vif.slave_i3c_write_tbit_mode <= 1'b0;
    apb_read(RESP_PORT, rdata);
    expect_eq("CMD-before-TX response", rdata, 32'h0, 32'h3);
  endtask
endclass

class i3c_private_nack_seq extends i3c_seq;
  `uvm_object_utils(i3c_private_nack_seq)
  function new(string name = "i3c_private_nack_seq"); super.new(name); endfunction
  task body();
    bit [31:0] rdata;
    cfg_i3c_mode();
    vif.slave_ack_addr <= 1'b0;
    send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b0, 8'd0));
    wait_status_idle();
    wait_irq_asserted();
    apb_read(RESP_PORT, rdata);
    expect_eq("private NACK response", rdata, 32'h0000_0002, 32'h0000_0002);
    apb_read(REG_ERR_STATUS, rdata);
    expect_eq("private NACK ERR_STATUS set", rdata, 32'h0000_0002, 32'h0000_0002);
    send_apb(WR, REG_ERR_STATUS, 32'h0000_0002);
    apb_read(REG_ERR_STATUS, rdata);
    expect_eq("private NACK ERR_STATUS clear", rdata, 32'h0000_0000, 32'h0000_0003);
  endtask
endclass

class i3c_sdr_private_read_seq extends i3c_seq;
  `uvm_object_utils(i3c_sdr_private_read_seq)
  function new(string name = "i3c_sdr_private_read_seq"); super.new(name); endfunction
  task body();
    bit [31:0] rdata;
    cfg_i3c_mode();
    vif.slave_read_data[0] <= 8'h3c;
    vif.slave_read_data[1] <= 8'ha7;
    vif.slave_read_data[2] <= 8'hd2;
    // Target has a third byte ready, but the controller command accepts only
    // two.  The second T-bit therefore exercises controller early termination.
    vif.slave_read_length <= 3;
    vif.slave_ack_addr <= 1'b1;
    vif.slave_read_en <= 1'b1;
    send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b1, 8'd2));
    wait_status_idle();
    vif.slave_ack_addr <= 1'b0;
    vif.slave_read_en <= 1'b0;
    vif.slave_read_length <= 0;
    apb_read(RESP_PORT, rdata);
    expect_eq("SDR private read response", rdata, 32'h0, 32'h3);
    apb_read(RX_PORT, rdata);
    expect_eq("SDR RX byte0", rdata, 32'h3c, 32'hff);
    apb_read(RX_PORT, rdata);
    expect_eq("SDR RX byte1", rdata, 32'ha7, 32'hff);
  endtask
endclass

class i3c_sdr_private_read_short_seq extends i3c_seq;
  `uvm_object_utils(i3c_sdr_private_read_short_seq)
  function new(string name = "i3c_sdr_private_read_short_seq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] rdata;
    cfg_i3c_mode();
    vif.slave_read_data[0] <= 8'he1;
    // Controller permits three bytes, while the target ends after the first
    // valid byte by driving T=0.
    vif.slave_read_length <= 1;
    vif.slave_ack_addr <= 1'b1;
    vif.slave_read_en <= 1'b1;
    send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b1, 8'd3));
    wait_status_idle();
    vif.slave_ack_addr <= 1'b0;
    vif.slave_read_en <= 1'b0;
    vif.slave_read_length <= 0;
    apb_read(RESP_PORT, rdata);
    expect_eq("SDR short-read response", rdata, 32'h0, 32'h3);
    apb_read(RX_PORT, rdata);
    expect_eq("SDR short-read RX byte0", rdata, 32'he1, 32'hff);
  endtask
endclass

class i3c_i2c_private_write_seq extends i3c_seq;
  `uvm_object_utils(i3c_i2c_private_write_seq)
  function new(string name = "i3c_i2c_private_write_seq"); super.new(name); endfunction
  task body();
    bit [31:0] rdata;
    cfg_i3c_mode();
    cfg_i2c_mode();
    send_apb(WR, TX_PORT, 32'h11);
    send_apb(WR, TX_PORT, 32'h22);
    vif.slave_ack_addr <= 1'b1;
    vif.slave_i2c_write_ack_count <= 2;
    send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b0, 8'd2));
    wait_status_idle();
    vif.slave_ack_addr <= 1'b0;
    vif.slave_i2c_write_ack_count <= 0;
    apb_read(RESP_PORT, rdata);
    expect_eq("I2C private write response", rdata, 32'h0, 32'h3);
  endtask
endclass

class i3c_i2c_private_write_data_nack_seq extends i3c_seq;
  `uvm_object_utils(i3c_i2c_private_write_data_nack_seq)
  function new(string name = "i3c_i2c_private_write_data_nack_seq");
    super.new(name);
  endfunction

  task body();
    bit [31:0] rdata;

    cfg_i3c_mode();
    cfg_i2c_mode();
    send_apb(WR, TX_PORT, 32'h33);
    send_apb(WR, TX_PORT, 32'h44);
    vif.slave_ack_addr <= 1'b1;
    // ACK byte[0], then leave byte[1]'s ninth bit released (NACK).
    vif.slave_i2c_write_ack_count <= 1;
    send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b0, 8'd2));
    wait_status_idle();
    vif.slave_ack_addr <= 1'b0;
    vif.slave_i2c_write_ack_count <= 0;

    apb_read(RESP_PORT, rdata);
    expect_eq("I2C data NACK response", rdata,
              32'h0000_0002, 32'h0000_0003);
    apb_read(REG_ERR_STATUS, rdata);
    expect_eq("I2C data NACK ERR_STATUS", rdata,
              32'h0000_0002, 32'h0000_0002);
    send_apb(WR, REG_ERR_STATUS, 32'h0000_0002);
  endtask
endclass

class i3c_i2c_private_read_seq extends i3c_seq;
  `uvm_object_utils(i3c_i2c_private_read_seq)
  function new(string name = "i3c_i2c_private_read_seq"); super.new(name); endfunction
  task body();
    bit [31:0] rdata;
    cfg_i3c_mode();
    cfg_i2c_mode();
    vif.slave_read_data[0] <= 8'h11;
    vif.slave_read_data[1] <= 8'h22;
    vif.slave_read_length <= 2;
    vif.slave_ack_addr <= 1'b1;
    vif.slave_read_en <= 1'b1;
    vif.slave_i2c_read_mode <= 1'b1;
    send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b1, 8'd2));
    wait_status_idle();
    vif.slave_ack_addr <= 1'b0;
    vif.slave_read_en <= 1'b0;
    vif.slave_read_length <= 0;
    vif.slave_i2c_read_mode <= 1'b0;
    apb_read(RESP_PORT, rdata);
    expect_eq("I2C private read response", rdata, 32'h0, 32'h3);
    apb_read(RX_PORT, rdata);
    expect_eq("I2C RX byte0", rdata, 32'h11, 32'hff);
    apb_read(RX_PORT, rdata);
    expect_eq("I2C RX byte1", rdata, 32'h22, 32'hff);
  endtask
endclass

class i3c_broadcast_ccc_seq extends i3c_seq;
  `uvm_object_utils(i3c_broadcast_ccc_seq)
  function new(string name = "i3c_broadcast_ccc_seq"); super.new(name); endfunction
  task body();
    bit [31:0] rdata;
    cfg_i3c_mode();
    vif.ccc_ack_en <= 1'b1;
    vif.ccc_direct_en <= 1'b0;
    send_apb(WR, CMD_PORT, ccc_cmd(1'b0, CCC_ENEC, 7'h00, 1'b0, 8'd0));
    wait_status_idle();
    vif.ccc_ack_en <= 1'b0;
    apb_read(RESP_PORT, rdata);
    expect_eq("broadcast CCC response", rdata, 32'h0, 32'h3);
  endtask
endclass

class i3c_direct_ccc_seq extends i3c_seq;
  `uvm_object_utils(i3c_direct_ccc_seq)
  function new(string name = "i3c_direct_ccc_seq"); super.new(name); endfunction
  task body();
    bit [31:0] rdata;
    cfg_i3c_mode();
    vif.slave_read_data[0] <= 8'h55;
    vif.slave_read_data[1] <= 8'hAA;
    vif.slave_read_length <= 1;
    vif.slave_ack_addr <= 1'b1;
    vif.slave_read_en <= 1'b1;
    vif.ccc_ack_en <= 1'b1;
    vif.ccc_direct_en <= 1'b1;
    send_apb(WR, CMD_PORT, ccc_cmd(1'b1, CCC_GETSTATUS, SLAVE_ADDR, 1'b1, 8'd1));
    wait_status_idle();
    vif.slave_ack_addr <= 1'b0;
    vif.slave_read_en <= 1'b0;
    vif.slave_read_length <= 0;
    vif.ccc_ack_en <= 1'b0;
    vif.ccc_direct_en <= 1'b0;
    apb_read(RESP_PORT, rdata);
    expect_eq("direct CCC response", rdata, 32'h0, 32'h3);
    apb_read(RX_PORT, rdata);
    expect_eq("direct CCC RX byte0", rdata, 32'h55, 32'hff);
  endtask
endclass

class i3c_direct_ccc_write_seq extends i3c_seq;
  `uvm_object_utils(i3c_direct_ccc_write_seq)
  function new(string name = "i3c_direct_ccc_write_seq"); super.new(name); endfunction
  task body();
    bit [31:0] rdata;
    cfg_i3c_mode();
    // SETDASA payload carries the new DA in [7:1] and a required zero pad in
    // [0].  The byte_serializer sends the separate odd-parity T-bit.
    send_apb(WR, TX_PORT, {24'h0, NEW_DYNAMIC_ADDR, 1'b0});
    vif.slave_ack_addr <= 1'b1;
    vif.slave_i3c_write_tbit_mode <= 1'b1;
    vif.slave_i2c_write_ack_count <= 1;
    vif.ccc_ack_en <= 1'b1;
    vif.ccc_direct_en <= 1'b1;
    send_apb(WR, CMD_PORT, ccc_cmd(1'b1, CCC_SETDASA, SLAVE_ADDR, 1'b0, 8'd1));
    wait_status_idle();
    expect_eq("direct CCC write code observed",
              {24'h0, vif.slave_dbg_ccc_byte}, {24'h0, CCC_SETDASA}, 32'hff);
    expect_eq("SETDASA payload observed",
              {24'h0, vif.slave_dbg_write_byte},
              {24'h0, NEW_DYNAMIC_ADDR, 1'b0}, 32'hff);
    vif.slave_ack_addr <= 1'b0;
    vif.slave_i3c_write_tbit_mode <= 1'b0;
    vif.slave_i2c_write_ack_count <= 0;
    vif.ccc_ack_en <= 1'b0;
    vif.ccc_direct_en <= 1'b0;
    apb_read(RESP_PORT, rdata);
    expect_eq("direct CCC write response", rdata, 32'h0, 32'h3);
  endtask
endclass

class i3c_entdaa_seq extends i3c_seq;
  `uvm_object_utils(i3c_entdaa_seq)
  function new(string name = "i3c_entdaa_seq"); super.new(name); endfunction
  task body();
    bit [31:0] rdata;
    cfg_i3c_mode();
    vif.ccc_ack_en <= 1'b1;
    vif.ccc_direct_en <= 1'b0;
    vif.entdaa_slave_en <= 1'b1;
    send_apb(WR, CMD_PORT, ccc_cmd(1'b0, CCC_ENTDAA, 7'h00, 1'b0, 8'd0));
    wait_status_idle();
    vif.ccc_ack_en <= 1'b0;
    vif.entdaa_slave_en <= 1'b0;
    apb_read(RESP_PORT, rdata);
    expect_eq("ENTDAA response", rdata, 32'h0, 32'h3);
    apb_read(REG_ENTDAA_STATUS, rdata);
    expect_eq("ENTDAA assigned DA", rdata, 32'h0000_0101, 32'h0000_01ff);
    apb_read(REG_ENTDAA_PID_LO, rdata);
    expect_eq("ENTDAA PID low", rdata, ENTDAA_ID[31:0]);
    apb_read(REG_ENTDAA_PID_HI, rdata);
    expect_eq("ENTDAA PID high", rdata, ENTDAA_ID[63:32]);
  endtask
endclass

class i3c_ibi_no_payload_seq extends i3c_seq;
  `uvm_object_utils(i3c_ibi_no_payload_seq)
  function new(string name = "i3c_ibi_no_payload_seq"); super.new(name); endfunction
  task body();
    bit [31:0] rdata;
    cfg_i3c_mode();
    send_apb(WR, REG_CTRL, 32'h0000_000b);
    fork
      send_ibi(SLAVE_ADDR, 1'b0, 8'h00);
    join_none
    wait_irq_asserted();
    apb_read(REG_IBI_STATUS, rdata);
    expect_eq("IBI no MDB status", rdata, 32'h0001_0012, 32'h0001_ffff);
    send_apb(WR, REG_IBI_STATUS, 32'h0001_0000);
  endtask
endclass

class i3c_ibi_payload_seq extends i3c_seq;
  `uvm_object_utils(i3c_ibi_payload_seq)
  function new(string name = "i3c_ibi_payload_seq"); super.new(name); endfunction
  task body();
    bit [31:0] rdata;
    cfg_i3c_mode();
    send_apb(WR, REG_CTRL, 32'h0000_001b);
    repeat (8) @(posedge vif.clk);
    fork
      send_ibi(SLAVE_ADDR, 1'b1, 8'h5a);
    join_none
    wait_irq_asserted();
    apb_read(REG_IBI_STATUS, rdata);
    expect_eq("IBI MDB status", rdata, 32'h0001_0192, 32'h0001_ffff);
    apb_read(RX_PORT, rdata);
    expect_eq("IBI MDB byte", rdata, 32'h5a, 32'hff);
    send_apb(WR, REG_IBI_STATUS, 32'h0001_0000);
  endtask
endclass

class i3c_polling_access_seq extends i3c_sdr_private_write_seq;
  `uvm_object_utils(i3c_polling_access_seq)
  function new(string name = "i3c_polling_access_seq"); super.new(name); endfunction
endclass

class i3c_sw_reset_seq extends i3c_seq;
  `uvm_object_utils(i3c_sw_reset_seq)
  function new(string name = "i3c_sw_reset_seq"); super.new(name); endfunction
  task body();
    bit [31:0] rdata;
    cfg_i3c_mode(16'd7, 16'd5, 16'd4);

    // Leave a write command blocked waiting for TX, then reset it.  This
    // exercises the DUT FIFO reset and the verification-side epoch abort.
    vif.slave_ack_addr <= 1'b1;
    send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b0, 8'd1));
    wait (vif.slave_dbg_ack_phase === 1'b1);
    // 本场景故意不提供 TX 数据。地址 ACK 会一直保持到传输被软件复位中止，
    // 所以不能等待 ACK phase 清零后才发 sw_rst，否则会形成与 CMD-before-TX
    // 相同的环形等待。
    apb_read(REG_STATUS, rdata);
    expect_eq("busy before sw_rst", rdata, 32'h1, 32'h1);

    send_apb(WR, REG_CTRL, 32'h0000_0007);
    vif.slave_ack_addr <= 1'b0;
    // sync_fifo clears on the clock following the CSR reset pulse.
    repeat (3) @(posedge vif.clk);
    apb_read(REG_CTRL, rdata);
    expect_eq("CTRL sw_rst self clear", rdata, 32'h0000_0003, 32'h0000_001f);
    apb_read(REG_STATUS, rdata);
    expect_eq("busy cleared by sw_rst", rdata, 32'h0, 32'h1);
    apb_read(REG_BUS_TIMING_0, rdata);
    expect_eq("timing survives sw_rst", rdata, {16'd7, 16'd5});

    // A clean post-reset command proves that the target, monitor, predictor
    // and RTL dispatcher all left the aborted epoch.
    vif.slave_ack_addr <= 1'b1;
    send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b0, 8'd0));
    wait_status_idle();
    vif.slave_ack_addr <= 1'b0;
    apb_read(RESP_PORT, rdata);
    expect_eq("post-sw_rst response", rdata, 32'h0, 32'h3);
  endtask
endclass

class i3c_bus_timing_sweep_seq extends i3c_seq;
  `uvm_object_utils(i3c_bus_timing_sweep_seq)
  function new(string name = "i3c_bus_timing_sweep_seq"); super.new(name); endfunction
  task run_timing_case(input int case_id, input bit [15:0] high,
                       input bit [15:0] low, input bit [15:0] hold);
    bit [31:0] rdata;
    cfg_i3c_mode(high, low, hold);
    apb_read(REG_BUS_TIMING_0, rdata);
    expect_eq($sformatf("timing sweep high/low[%0d]", case_id), rdata, {high, low});
    apb_read(REG_BUS_TIMING_1, rdata);
    expect_eq($sformatf("timing sweep hold[%0d]", case_id), rdata, {16'd0, hold}, 32'h0000_ffff);
    vif.slave_ack_addr <= 1'b1;
    send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b0, 8'd0));
    wait_status_idle();
    vif.slave_ack_addr <= 1'b0;
    apb_read(RESP_PORT, rdata);
    expect_eq($sformatf("timing sweep response[%0d]", case_id), rdata, 32'h0, 32'h3);
  endtask

  task body();
    run_timing_case(0, 16'd2, 16'd3, 16'd1);
    run_timing_case(1, 16'd4, 16'd6, 16'd2);
    run_timing_case(2, 16'd8, 16'd5, 16'd4);
  endtask
endclass

class i3c_irq_access_seq extends i3c_seq;
  `uvm_object_utils(i3c_irq_access_seq)
  function new(string name = "i3c_irq_access_seq"); super.new(name); endfunction
  task body();
    bit [31:0] rdata;
    cfg_i3c_mode();
    vif.slave_ack_addr <= 1'b1;
    send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b0, 8'd0));
    wait_irq_asserted();
    vif.slave_ack_addr <= 1'b0;
    apb_read(RESP_PORT, rdata);
    expect_eq("IRQ response", rdata, 32'h0, 32'h3);
    repeat (2) @(posedge vif.clk);
    if (vif.irq)
      `uvm_error("IRQ", "IRQ did not clear after RESP read")
  endtask
endclass

task i3c_seq::send_ibi(bit [6:0] addr, bit has_mdb, bit [7:0] mdb);
  bit [7:0] ibi_addr_byte;
  ibi_addr_byte = {addr, 1'b1};

  // Publish the target's plan before creating the target-initiated START.
  // This path is intentionally separate from command target intents because
  // an IBI has no CMD_PORT descriptor to pair with.
  vif.ibi_plan_addr = addr;
  vif.ibi_plan_expect_addr_ack = 1'b1;
  vif.ibi_plan_has_mdb = has_mdb;
  vif.ibi_plan_mdb = mdb;
  vif.ibi_plan_expect_controller_t_low = has_mdb;
  vif.ibi_plan_valid = 1'b1;
  @(posedge vif.clk);
  vif.ibi_plan_valid = 1'b0;

  wait (vif.scl_in && vif.sda_in);
  vif.slave_drive_low <= 1'b1;

  for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
    @(negedge vif.scl_in);
    @(posedge vif.clk);
    vif.slave_drive_low <= !ibi_addr_byte[bit_idx];
    @(posedge vif.scl_in);
  end

  @(negedge vif.scl_in);
  @(posedge vif.clk);
  vif.slave_drive_low <= 1'b0;
  @(posedge vif.scl_in);

  if (has_mdb) begin
    for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
      @(negedge vif.scl_in);
      @(posedge vif.clk);
      vif.slave_drive_low <= !mdb[bit_idx];
      @(posedge vif.scl_in);
    end

    @(negedge vif.scl_in);
    @(posedge vif.clk);
    // MDB is the target's final byte, therefore the target drives T=0.  The
    // controller also pulls this wired-AND bit low because it accepts at most
    // one MDB; both drive contributors are checked independently.
    vif.slave_drive_low <= 1'b1;
    @(posedge vif.scl_in);
  end

  vif.slave_drive_low <= 1'b0;
  wait (vif.irq);
  wait (vif.scl_in && vif.sda_in);
  repeat (4) @(posedge vif.clk);
endtask
