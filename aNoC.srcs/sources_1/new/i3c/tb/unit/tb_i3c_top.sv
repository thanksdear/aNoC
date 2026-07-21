`timescale 1ns/1ps
`default_nettype none

module tb_i3c_top;
  localparam int CLK_PERIOD_NS = 10;
  localparam int TB_SCL_HIGH_CYCLES = 4;

  localparam logic [7:0] REG_BUS_TIMING_0 = 8'h00;
  localparam logic [7:0] REG_BUS_TIMING_1 = 8'h04;
  localparam logic [7:0] REG_CTRL         = 8'h08;
  localparam logic [7:0] REG_STATUS       = 8'h0c;
  localparam logic [7:0] REG_IBI_STATUS   = 8'h10;
  localparam logic [7:0] REG_ERR_STATUS   = 8'h14;
  localparam logic [7:0] REG_ENTDAA_STATUS = 8'h18;
  localparam logic [7:0] REG_ENTDAA_PID_LO = 8'h1c;
  localparam logic [7:0] REG_ENTDAA_PID_HI = 8'h30;
  localparam logic [7:0] CMD_PORT         = 8'h20;
  localparam logic [7:0] RESP_PORT        = 8'h24;
  localparam logic [7:0] TX_PORT          = 8'h28;
  localparam logic [7:0] RX_PORT          = 8'h2c;

  logic        pclk;
  logic        presetn;
  logic        psel;
  logic        penable;
  logic        pwrite;
  logic [11:0] paddr;
  logic [31:0] pwdata;
  logic [3:0]  pstrb;
  logic [31:0] prdata;
  logic        pready;
  logic        pslverr;

  logic        scl_in;
  logic        scl_oe;
  logic        scl_out;
  logic        sda_in;
  logic        sda_oe;
  logic        sda_out;
  logic        irq;
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
  logic        scl_bus;
  logic        sda_bus;
  logic        slave_drive_low;
  logic        slave_dbg_active;
  logic [1:0]  slave_dbg_branch; // 1=CCC target, 2=CCC broadcast, 3=private
  logic [7:0]  slave_dbg_addr_byte;
  logic [7:0]  slave_dbg_ccc_byte;
  logic [7:0]  slave_dbg_write_byte;
  logic [7:0]  slave_dbg_entdaa_da;
  logic        slave_dbg_matched;
  logic        slave_dbg_ack_phase;
  logic [7:0]  slave_read_data [0:3];

  localparam logic [6:0] SLAVE_ADDR = 7'h12;
  localparam logic [7:0] CCC_ENEC = 8'h00;
  localparam logic [7:0] CCC_ENTDAA = 8'h07;
  localparam logic [7:0] CCC_GETSTATUS = 8'h90;
  localparam logic [63:0] ENTDAA_ID = 64'h1234_5678_9abc_de01;
  localparam logic [6:0] ENTDAA_EXPECTED_DA = 7'h01;

  int errors;

  task automatic slave_wait_entdaa_start();
    forever begin
      @(negedge sda_bus);
      if (scl_bus === 1'b1)
        return;
    end
  endtask

  task automatic slave_wait_entdaa_stop();
    forever begin
      @(posedge sda_bus);
      if (scl_bus === 1'b1)
        return;
    end
  endtask

  task automatic slave_handle_entdaa();
    logic [7:0] header_byte;
    logic [7:0] da_byte;
    logic       assigned;
    logic       participate;
    logic       da_valid;

    participate = entdaa_slave_en;
    assigned = 1'b0;

    forever begin
      slave_wait_entdaa_start();
      for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
        @(posedge scl_bus);
        header_byte[bit_idx] = sda_bus;
      end

      if (header_byte !== 8'hfd) begin
        errors++;
        $error("Expected ENTDAA 7E/R header 0xfd, got 0x%02h",
               header_byte);
      end

      // NACK the final discovery header after this target is assigned.  A
      // header NACK is ENTDAA's normal no-more-unassigned-targets terminator.
      if (!participate || assigned || header_byte !== 8'hfd) begin
        @(negedge scl_bus);
        slave_dbg_ack_phase <= 1'b1;
        slave_drive_low <= 1'b0;
        @(posedge scl_bus);
        slave_dbg_ack_phase <= 1'b0;
        slave_wait_entdaa_stop();
        return;
      end

      @(negedge scl_bus);
      slave_dbg_ack_phase <= 1'b1;
      slave_drive_low <= 1'b1; // ACK the first 7E/R header.
      @(posedge scl_bus);
      @(negedge scl_bus);
      slave_drive_low <= 1'b0;
      slave_dbg_ack_phase <= 1'b0;

      for (int bit_idx = 63; bit_idx >= 0; bit_idx--) begin
        slave_drive_low <= !ENTDAA_ID[bit_idx];
        @(posedge scl_bus);
        @(negedge scl_bus);
      end
      slave_drive_low <= 1'b0;

      for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
        @(posedge scl_bus);
        da_byte[bit_idx] = sda_bus;
      end
      slave_dbg_entdaa_da <= da_byte;

      da_valid = ((^da_byte) === 1'b1) &&
                 (da_byte[7:1] === ENTDAA_EXPECTED_DA);
      if (!da_valid) begin
        errors++;
        $error("Invalid assigned DA/parity: got byte=0x%02h expected DA=0x%02h",
               da_byte, ENTDAA_EXPECTED_DA);
      end

      @(negedge scl_bus);
      slave_dbg_ack_phase <= 1'b1;
      slave_drive_low <= da_valid; // ACK only a valid expected DA.
      @(posedge scl_bus);
      @(negedge scl_bus);
      slave_drive_low <= 1'b0;
      slave_dbg_ack_phase <= 1'b0;

      if (!da_valid) begin
        slave_wait_entdaa_stop();
        return;
      end

      assigned = 1'b1;
    end
  endtask

  task automatic slave_send_ibi(input logic [6:0] addr,
                                input logic       has_mdb,
                                input logic [7:0] mdb);
    logic [7:0] ibi_addr_byte;

    ibi_addr_byte = {addr, 1'b1};

    wait (scl_bus && sda_bus);
    slave_drive_low <= 1'b1; // IBI request: SDA low while bus is idle.

    for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
      @(negedge scl_bus);
      @(posedge pclk);
      slave_drive_low <= !ibi_addr_byte[bit_idx];
      @(posedge scl_bus);
    end

    @(negedge scl_bus);
    @(posedge pclk);
    slave_drive_low <= 1'b0; // ACK/NACK bit is driven by master.
    @(posedge scl_bus);
    if (sda_bus !== 1'b0 || slave_drive_low !== 1'b0 ||
        sda_oe !== 1'b1 || sda_out !== 1'b0) begin
      errors++;
      $error("IBI address ACK ownership/value incorrect: bus=%b target_low=%b controller_oe/out=%b/%b",
             sda_bus, slave_drive_low, sda_oe, sda_out);
    end

    if (has_mdb) begin
      for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
        @(negedge scl_bus);
        @(posedge pclk);
        slave_drive_low <= !mdb[bit_idx];
        @(posedge scl_bus);
      end

      @(negedge scl_bus);
      @(posedge pclk);
      // The target owns End-of-Data for its final MDB and drives T low.  This
      // one-byte controller also limits the read by pulling the same OD bit
      // low, so the unit check below requires both contributors.
      slave_drive_low <= 1'b1;
      @(posedge scl_bus);
      if (sda_bus !== 1'b0 || slave_drive_low !== 1'b1 ||
          sda_oe !== 1'b1 || sda_out !== 1'b0) begin
        errors++;
        $error("IBI MDB T ownership/value incorrect: bus=%b target_low=%b controller_oe/out=%b/%b",
               sda_bus, slave_drive_low, sda_oe, sda_out);
      end
    end

    slave_drive_low <= 1'b0;
    wait (irq);
    wait (scl_bus && sda_bus);
    repeat (4) @(posedge pclk);
  endtask

  i3c_top dut (
    .PCLK    (pclk),
    .PRESETn (presetn),
    .PSEL    (psel),
    .PENABLE (penable),
    .PWRITE  (pwrite),
    .PADDR   (paddr),
    .PWDATA  (pwdata),
    .PSTRB   (pstrb),
    .PRDATA  (prdata),
    .PREADY  (pready),
    .PSLVERR (pslverr),
    .SCL_IN  (scl_in),
    .SCL_OE  (scl_oe),
    .SCL_OUT (scl_out),
    .SDA_IN  (sda_in),
    .SDA_OE  (sda_oe),
    .SDA_OUT (sda_out),
    .IRQ     (irq)
  );

  initial begin
    pclk = 1'b0;
    forever #(CLK_PERIOD_NS / 2) pclk = ~pclk;
  end

  // Pad loopback/pull-up model plus a simple external slave. The slave model
  // observes only the resolved bus and drives SDA low for ACK/data zero bits.
  assign scl_bus = scl_oe ? scl_out : 1'b1;
  assign sda_bus = (slave_drive_low || (sda_oe && !sda_out)) ? 1'b0 : 1'b1;

  always @(posedge pclk) begin
    if (presetn === 1'b1 && sda_oe === 1'b1 && sda_out === 1'b1 &&
        slave_drive_low === 1'b1)
      $error("SDA contention: controller drove high while slave drove low");
  end

  always_comb begin
    scl_in = scl_bus;
    sda_in = sda_bus;
  end

  task automatic slave_handle_frame();
    logic [7:0] addr_byte;
    logic [7:0] ccc_byte;
    logic [7:0] read_byte;
    logic       matched;
    logic       cont;
    logic       target_more;
    int         byte_idx;
    int         write_ack_count;

    slave_drive_low <= 1'b0;
    slave_dbg_active <= 1'b1;
    slave_dbg_branch <= 2'd0;
    slave_dbg_matched <= 1'b0;
    slave_dbg_ack_phase <= 1'b0;

    for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
      @(posedge scl_bus);
      addr_byte[bit_idx] = sda_bus;
    end
    slave_dbg_addr_byte <= addr_byte;

    if (expect_ccc_target) begin
      slave_dbg_branch <= 2'd1;
      expect_ccc_target <= 1'b0;
      matched = slave_ack_addr && (addr_byte[7:1] == SLAVE_ADDR);
      slave_dbg_matched <= matched;
      @(negedge scl_bus);
      slave_dbg_ack_phase <= 1'b1;
      if (matched)
        slave_drive_low <= 1'b1;

      @(posedge scl_bus);
      @(negedge scl_bus);
      slave_drive_low <= 1'b0;
      slave_dbg_ack_phase <= 1'b0;
    end else if (ccc_ack_en && addr_byte == 8'hfc) begin
      slave_dbg_branch <= 2'd2;
      matched = 1'b1;
      slave_dbg_matched <= matched;
      @(negedge scl_bus);
      slave_dbg_ack_phase <= 1'b1;
      slave_drive_low <= 1'b1;

      @(posedge scl_bus);     // Broadcast address ACK bit sampled by master.
      @(negedge scl_bus);
      slave_drive_low <= 1'b0;
      slave_dbg_ack_phase <= 1'b0;

      for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
        @(posedge scl_bus);
        ccc_byte[bit_idx] = sda_bus;
      end
      slave_dbg_ccc_byte <= ccc_byte;

      // CCC Code is an I3C write byte. Its ninth bit is controller-driven
      // odd parity, so the target must leave SDA released rather than ACK it.
      @(negedge scl_bus);
      slave_drive_low <= 1'b0;
      slave_dbg_ack_phase <= 1'b0;
      @(posedge scl_bus);

      if (!ccc_direct_en)
        @(negedge scl_bus);

      if (!ccc_direct_en) begin
        if (ccc_byte == CCC_ENTDAA)
          slave_handle_entdaa();
        slave_dbg_active <= 1'b0;
        return;
      end

      // Return before Sr so the outer loop can recognize and handle the
      // following direct-target address segment.
      expect_ccc_target <= 1'b1;
      slave_dbg_active <= 1'b0;
      return;
    end else begin
      slave_dbg_branch <= 2'd3;
      matched = slave_ack_addr && (addr_byte[7:1] == SLAVE_ADDR);
      slave_dbg_matched <= matched;
      @(negedge scl_bus);
      slave_dbg_ack_phase <= 1'b1;
      if (matched)
        slave_drive_low <= 1'b1;

      @(posedge scl_bus);     // Address ACK bit sampled by the master.
      @(negedge scl_bus);
      slave_drive_low <= 1'b0;
      slave_dbg_ack_phase <= 1'b0;
    end

    if (matched && !addr_byte[0] && slave_i2c_write_ack_count > 0) begin
      write_ack_count = slave_i2c_write_ack_count;
      for (byte_idx = 0; byte_idx < write_ack_count; byte_idx++) begin
        for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
          @(posedge scl_bus);
          read_byte[bit_idx] = sda_bus;
        end
        slave_dbg_write_byte <= read_byte;

        @(negedge scl_bus);
        if (slave_i3c_write_tbit_mode) begin
          slave_dbg_ack_phase <= 1'b0;
          slave_drive_low <= 1'b0;
        end else begin
          slave_dbg_ack_phase <= 1'b1;
          slave_drive_low <= 1'b1;
        end
        @(posedge scl_bus);
        @(negedge scl_bus);
        slave_drive_low <= 1'b0;
        slave_dbg_ack_phase <= 1'b0;
      end

      slave_dbg_active <= 1'b0;
      return;
    end

    if (!matched || !addr_byte[0] || !slave_read_en) begin
      slave_dbg_active <= 1'b0;
      return;
    end

    byte_idx = 0;
    forever begin
      if (byte_idx >= slave_read_length || byte_idx >= 4) begin
        errors++;
        $error("Target read plan exhausted unexpectedly at byte %0d", byte_idx);
        slave_dbg_active <= 1'b0;
        return;
      end
      read_byte = slave_read_data[byte_idx];

      for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
        slave_drive_low <= !read_byte[bit_idx];
        @(posedge scl_bus);
        @(negedge scl_bus);
      end

      target_more = ((byte_idx + 1) < slave_read_length);
      // I3C target drives T first: 1=more (release), 0=end (pull low).
      // The controller may also pull a target T=1 low to terminate early.
      slave_drive_low <= slave_i2c_read_mode ? 1'b0 : !target_more;
      @(posedge scl_bus);
      cont = slave_i2c_read_mode ? !sda_bus : sda_bus;
      @(negedge scl_bus);
      slave_drive_low <= 1'b0;

      byte_idx++;
      if (!cont) begin
        slave_dbg_active <= 1'b0;
        return;
      end
    end
  endtask

  initial begin
    slave_drive_low <= 1'b0;
    slave_read_length <= 0;
    slave_i2c_read_mode <= 1'b0;
    slave_i3c_write_tbit_mode <= 1'b0;
    slave_i2c_write_ack_count <= 0;
    slave_dbg_active <= 1'b0;
    slave_dbg_branch <= 2'd0;
    slave_dbg_addr_byte <= 8'h00;
    slave_dbg_ccc_byte <= 8'h00;
    slave_dbg_write_byte <= 8'h00;
    slave_dbg_entdaa_da <= 8'h00;
    slave_dbg_matched <= 1'b0;
    slave_dbg_ack_phase <= 1'b0;
    forever begin
      wait ((presetn === 1'b1) && (dut.sw_rst !== 1'b1));
      fork : slave_reset_epoch
        begin
          wait ((presetn !== 1'b1) || (dut.sw_rst === 1'b1));
        end
        begin
          forever begin
            @(negedge sda_bus);
            if (scl_bus && !slave_drive_low &&
                (slave_ack_addr || slave_read_en || ccc_ack_en))
              slave_handle_frame();
          end
        end
      join_any
      disable slave_reset_epoch;
      slave_drive_low <= 1'b0;
      slave_dbg_active <= 1'b0;
      slave_dbg_ack_phase <= 1'b0;
    end
  end

  task automatic apb_idle();
    psel    <= 1'b0;
    penable <= 1'b0;
    pwrite  <= 1'b0;
    paddr   <= '0;
    pwdata  <= '0;
    pstrb   <= '0;
  endtask

  task automatic apb_write(input logic [7:0] addr, input logic [31:0] data);
    @(posedge pclk);
    paddr   <= {4'd0, addr};
    pwdata  <= data;
    pstrb   <= 4'hf;
    pwrite  <= 1'b1;
    psel    <= 1'b1;
    penable <= 1'b0;

    @(posedge pclk);
    penable <= 1'b1;
    while (!pready) @(posedge pclk);

    @(posedge pclk);
    apb_idle();
  endtask

  task automatic apb_read(input logic [7:0] addr, output logic [31:0] data);
    @(posedge pclk);
    paddr   <= {4'd0, addr};
    pwdata  <= '0;
    pstrb   <= 4'h0;
    pwrite  <= 1'b0;
    psel    <= 1'b1;
    penable <= 1'b0;

    @(posedge pclk);
    penable <= 1'b1;
    while (!pready) @(posedge pclk);
    #1 data = prdata;

    @(posedge pclk);
    apb_idle();
  endtask

  task automatic expect_eq(input string name,
                           input logic [31:0] got,
                           input logic [31:0] exp,
                           input logic [31:0] mask = 32'hffff_ffff);
    if ((got & mask) !== (exp & mask)) begin
      errors++;
      $error("%s mismatch: got=0x%08h exp=0x%08h mask=0x%08h",
             name, got, exp, mask);
    end else begin
      $display("[%0t] PASS %s: 0x%08h", $time, name, got & mask);
    end
  endtask

  task automatic wait_status_idle();
    logic [31:0] status;
    int timeout;
    timeout = 2000;
    do begin
      apb_read(REG_STATUS, status);
      timeout--;
      if (timeout == 0) begin
        errors++;
        $error("Timeout waiting for STATUS.busy to assert");
        return;
      end
    end while (!status[0]);

    timeout = 2000;
    do begin
      apb_read(REG_STATUS, status);
      timeout--;
      if (timeout == 0) begin
        errors++;
        $error("Timeout waiting for STATUS.busy to deassert");
        return;
      end
    end while (status[0]);
  endtask

  task automatic wait_irq_asserted();
    int timeout;
    timeout = 2000;
    while (!irq) begin
      @(posedge pclk);
      timeout--;
      if (timeout == 0) begin
        errors++;
        $error("Timeout waiting for IRQ/response");
        return;
      end
    end
  endtask

  function automatic logic [31:0] private_cmd(input logic [6:0] addr,
                                              input logic rw,
                                              input logic [7:0] len);
    private_cmd = '0;
    private_cmd[31:24] = len;
    private_cmd[23:17] = addr;
    private_cmd[16]    = rw;
    private_cmd[1]     = 1'b0; // private transfer, not CCC
    private_cmd[0]     = 1'b0;
  endfunction

  function automatic logic [31:0] ccc_cmd(input logic is_direct,
                                          input logic [7:0] code,
                                          input logic [6:0] addr,
                                          input logic rw,
                                          input logic [7:0] len);
    ccc_cmd = '0;
    ccc_cmd[31:24] = len;
    ccc_cmd[23:17] = addr;
    ccc_cmd[16]    = rw;
    ccc_cmd[15:8]  = code;
    ccc_cmd[1]     = 1'b1;      // CCC frame
    ccc_cmd[0]     = is_direct; // 0=broadcast, 1=direct
  endfunction

  initial begin
    logic [31:0] rdata;
    logic [31:0] response;

    errors = 0;
    slave_ack_addr = 1'b0;
    slave_read_en = 1'b0;
    slave_read_length = 0;
    slave_i2c_read_mode <= 1'b0;
    ccc_ack_en = 1'b0;
    ccc_direct_en = 1'b0;
    entdaa_slave_en = 1'b0;
    expect_ccc_target <= 1'b0;
    slave_read_data[0] = 8'h00;
    slave_read_data[1] = 8'h00;
    slave_read_data[2] = 8'h00;
    slave_read_data[3] = 8'h00;
    apb_idle();
    presetn = 1'b0;

    repeat (5) @(posedge pclk);
    presetn = 1'b1;
    repeat (2) @(posedge pclk);

    $display("[%0t] Configure timing and enable core", $time);
    apb_write(REG_BUS_TIMING_0, {16'd4, 16'd4});
    apb_write(REG_BUS_TIMING_1, 32'd2);
    apb_write(REG_CTRL, 32'h0000_0003); // i3c_mode=1, core_en=1, ibi_en=0

    apb_read(REG_BUS_TIMING_0, rdata);
    expect_eq("BUS_TIMING_0", rdata, {16'd4, 16'd4});
    apb_read(REG_BUS_TIMING_1, rdata);
    expect_eq("BUS_TIMING_1", rdata, 32'd2, 32'h0000_ffff);
    apb_read(REG_CTRL, rdata);
    expect_eq("CTRL", rdata, 32'h0000_0003, 32'h0000_000f);

    $display("[%0t] Verify interrupt-driven access on successful response", $time);
    slave_ack_addr <= 1'b1;
    apb_write(CMD_PORT, private_cmd(7'h12, 1'b0, 8'd0));
    wait_irq_asserted();
    slave_ack_addr <= 1'b0;

    apb_read(RESP_PORT, response);
    expect_eq("RESP.irq.ok", response, 32'h0000_0000, 32'h0000_0003);
    repeat (2) @(posedge pclk);
    if (irq) begin
      errors++;
      $error("IRQ did not clear after RESP read");
    end else begin
      $display("[%0t] PASS IRQ cleared after RESP read", $time);
    end

    $display("[%0t] Push private header-only write; no slave ACK expected", $time);
    apb_write(CMD_PORT, private_cmd(7'h12, 1'b0, 8'd0));

    wait_status_idle();
    wait_irq_asserted();
    if (!irq) begin
      errors++;
      $error("IRQ did not assert after NACK response");
    end

    apb_read(RESP_PORT, response);
    expect_eq("RESP.nack", response, 32'h0000_0002, 32'h0000_0002);

    apb_read(REG_ERR_STATUS, rdata);
    expect_eq("ERR_STATUS.nack_err", rdata, 32'h0000_0002, 32'h0000_0002);

    $display("[%0t] Clear NACK error and run private 3-byte write with slave ACK", $time);
    apb_write(REG_ERR_STATUS, 32'h0000_0002);
    apb_read(REG_ERR_STATUS, rdata);
    expect_eq("ERR_STATUS cleared", rdata, 32'h0000_0000, 32'h0000_0003);

    apb_write(TX_PORT, 32'h0000_00a5);
    apb_write(TX_PORT, 32'h0000_005a);
    apb_write(TX_PORT, 32'h0000_00c3);

    slave_ack_addr = 1'b1;
    apb_write(CMD_PORT, private_cmd(7'h12, 1'b0, 8'd3));
    wait_status_idle();
    slave_ack_addr = 1'b0;

    apb_read(RESP_PORT, response);
    expect_eq("RESP.ok", response, 32'h0000_0000, 32'h0000_0003);

    apb_read(REG_ERR_STATUS, rdata);
    expect_eq("ERR_STATUS after ACK write", rdata, 32'h0000_0000, 32'h0000_0003);

    $display("[%0t] Run CMD-before-TX streaming write", $time);
    slave_ack_addr <= 1'b1;
    slave_i2c_write_ack_count <= 2;
    slave_i3c_write_tbit_mode <= 1'b1;
    apb_write(CMD_PORT, private_cmd(7'h12, 1'b0, 8'd2));
    wait (dut.u_sched.state == 3'd3); // S_DATA_WR: address ACK completed.
    repeat (4) @(posedge pclk);
    if (!dut.hw_busy) begin
      errors++;
      $error("CMD-before-TX command did not remain busy waiting for payload");
    end

    apb_write(TX_PORT, 32'h0000_00d1);
    wait (slave_dbg_write_byte === 8'hd1);
    if (!dut.hw_busy) begin
      errors++;
      $error("CMD-before-TX command completed before byte[1] arrived");
    end
    apb_write(TX_PORT, 32'h0000_00e2);
    wait_status_idle();
    slave_ack_addr <= 1'b0;
    slave_i2c_write_ack_count <= 0;
    slave_i3c_write_tbit_mode <= 1'b0;
    apb_read(RESP_PORT, response);
    expect_eq("RESP.cmd_before_tx", response,
              32'h0000_0000, 32'h0000_0003);

    $display("[%0t] Run private 2-byte read with slave data", $time);
    slave_read_data[0] = 8'h3c;
    slave_read_data[1] = 8'ha7;
    slave_read_data[2] = 8'hd2;
    slave_read_length = 3;
    slave_ack_addr = 1'b1;
    slave_read_en = 1'b1;

    apb_write(CMD_PORT, private_cmd(7'h12, 1'b1, 8'd2));
    wait_status_idle();

    slave_ack_addr = 1'b0;
    slave_read_en = 1'b0;
    slave_read_length = 0;

    apb_read(RESP_PORT, response);
    expect_eq("RESP.read.ok", response, 32'h0000_0000, 32'h0000_0003);

    apb_read(RX_PORT, rdata);
    expect_eq("RX byte0", rdata, 32'h0000_003c, 32'h0000_00ff);
    apb_read(RX_PORT, rdata);
    expect_eq("RX byte1", rdata, 32'h0000_00a7, 32'h0000_00ff);

    apb_read(REG_ERR_STATUS, rdata);
    expect_eq("ERR_STATUS after read", rdata, 32'h0000_0000, 32'h0000_0003);

    $display("[%0t] Run target-terminated private short read", $time);
    slave_read_data[0] = 8'he1;
    slave_read_length = 1;
    slave_ack_addr = 1'b1;
    slave_read_en = 1'b1;

    apb_write(CMD_PORT, private_cmd(7'h12, 1'b1, 8'd3));
    wait_status_idle();

    slave_ack_addr = 1'b0;
    slave_read_en = 1'b0;
    slave_read_length = 0;

    apb_read(RESP_PORT, response);
    expect_eq("RESP.read.short.ok", response, 32'h0000_0000, 32'h0000_0003);
    apb_read(RX_PORT, rdata);
    expect_eq("RX short byte0", rdata, 32'h0000_00e1, 32'h0000_00ff);
    // apb_read() returns in the same time slot in which the FIFO read pointer
    // advances.  Let that NBA update settle before inspecting empty directly.
    #1;
    if (!dut.rx_empty) begin
      errors++;
      $error("Target short read wrote more than one byte into RX FIFO");
    end

    $display("[%0t] Abort a TX-starved command with software reset", $time);
    slave_ack_addr <= 1'b1;
    apb_write(CMD_PORT, private_cmd(7'h12, 1'b0, 8'd1));
    wait (dut.u_sched.state == 3'd3); // S_DATA_WR: blocked on empty TX FIFO.
    if (!dut.hw_busy) begin
      errors++;
      $error("software-reset setup command was not busy");
    end
    apb_write(REG_CTRL, 32'h0000_0007);
    slave_ack_addr <= 1'b0;
    repeat (3) @(posedge pclk);
    apb_read(REG_CTRL, rdata);
    expect_eq("CTRL after sw_rst", rdata,
              32'h0000_0003, 32'h0000_001f);
    apb_read(REG_STATUS, rdata);
    expect_eq("STATUS after sw_rst", rdata,
              32'h0000_0000, 32'h0000_0001);
    if (irq) begin
      errors++;
      $error("IRQ remained asserted after software reset");
    end

    slave_ack_addr <= 1'b1;
    apb_write(CMD_PORT, private_cmd(7'h12, 1'b0, 8'd0));
    wait_status_idle();
    slave_ack_addr <= 1'b0;
    apb_read(RESP_PORT, response);
    expect_eq("RESP.post_sw_rst", response,
              32'h0000_0000, 32'h0000_0003);

    $display("[%0t] Run broadcast CCC ENEC header-only", $time);
    ccc_ack_en = 1'b1;
    ccc_direct_en = 1'b0;
    apb_write(CMD_PORT, ccc_cmd(1'b0, CCC_ENEC, 7'h00, 1'b0, 8'd0));
    wait_status_idle();
    ccc_ack_en = 1'b0;

    apb_read(RESP_PORT, response);
    expect_eq("RESP.ccc.broadcast.ok", response, 32'h0000_0000, 32'h0000_0003);

    apb_read(REG_ERR_STATUS, rdata);
    expect_eq("ERR_STATUS after broadcast CCC", rdata, 32'h0000_0000, 32'h0000_0003);

    $display("[%0t] Run direct CCC GETSTATUS read with slave data", $time);
    slave_read_data[0] <= 8'h55;
    slave_read_data[1] <= 8'haa;
    slave_read_length <= 2;
    slave_ack_addr <= 1'b1;
    slave_read_en <= 1'b1;
    ccc_ack_en <= 1'b1;
    ccc_direct_en <= 1'b1;

    apb_write(CMD_PORT, ccc_cmd(1'b1, CCC_GETSTATUS, 7'h12, 1'b1, 8'd2));
    wait_status_idle();

    slave_ack_addr <= 1'b0;
    slave_read_en <= 1'b0;
    slave_read_length <= 0;
    ccc_ack_en <= 1'b0;
    ccc_direct_en <= 1'b0;

    apb_read(RESP_PORT, response);
    expect_eq("RESP.ccc.direct.read.ok", response, 32'h0000_0000, 32'h0000_0003);

    apb_read(RX_PORT, rdata);
    expect_eq("CCC RX byte0", rdata, 32'h0000_0055, 32'h0000_00ff);
    apb_read(RX_PORT, rdata);
    expect_eq("CCC RX byte1", rdata, 32'h0000_00aa, 32'h0000_00ff);

    apb_read(REG_ERR_STATUS, rdata);
    expect_eq("ERR_STATUS after direct CCC", rdata, 32'h0000_0000, 32'h0000_0003);

    $display("[%0t] Run ENTDAA with one simulated unassigned slave", $time);
    ccc_ack_en <= 1'b1;
    ccc_direct_en <= 1'b0;
    entdaa_slave_en <= 1'b1;

    apb_write(CMD_PORT, ccc_cmd(1'b0, CCC_ENTDAA, 7'h00, 1'b0, 8'd0));
    wait_status_idle();

    ccc_ack_en <= 1'b0;
    entdaa_slave_en <= 1'b0;

    apb_read(RESP_PORT, response);
    expect_eq("RESP.ccc.entdaa.ok", response, 32'h0000_0000, 32'h0000_0003);

    apb_read(REG_ERR_STATUS, rdata);
    expect_eq("ERR_STATUS after ENTDAA", rdata, 32'h0000_0000, 32'h0000_0003);

    apb_read(REG_ENTDAA_STATUS, rdata);
    expect_eq("ENTDAA assigned DA", rdata, 32'h0000_0101, 32'h0000_01ff);
    apb_read(REG_ENTDAA_PID_LO, rdata);
    expect_eq("ENTDAA PID low", rdata, ENTDAA_ID[31:0]);
    apb_read(REG_ENTDAA_PID_HI, rdata);
    expect_eq("ENTDAA PID high", rdata, ENTDAA_ID[63:32]);

    $display("[%0t] Switch to I2C mode and run private 2-byte write", $time);
    apb_write(REG_CTRL, 32'h0000_0002); // i3c_mode=0, core_en=1, ibi_en=0
    apb_read(REG_CTRL, rdata);
    expect_eq("CTRL.i2c_mode", rdata, 32'h0000_0002, 32'h0000_000f);

    apb_write(TX_PORT, 32'h0000_0011);
    apb_write(TX_PORT, 32'h0000_0022);

    slave_ack_addr <= 1'b1;
    slave_i2c_write_ack_count <= 2;
    apb_write(CMD_PORT, private_cmd(7'h12, 1'b0, 8'd2));
    wait_status_idle();

    slave_ack_addr <= 1'b0;
    slave_i2c_write_ack_count <= 0;

    apb_read(RESP_PORT, response);
    expect_eq("RESP.i2c.write.ok", response, 32'h0000_0000, 32'h0000_0003);

    apb_read(REG_ERR_STATUS, rdata);
    expect_eq("ERR_STATUS after I2C write", rdata, 32'h0000_0000, 32'h0000_0003);

    $display("[%0t] Run I2C write with NACK on the second data byte", $time);
    apb_write(TX_PORT, 32'h0000_0033);
    apb_write(TX_PORT, 32'h0000_0044);
    slave_ack_addr <= 1'b1;
    // ACK byte[0], then release byte[1]'s ninth bit to generate NACK.
    slave_i2c_write_ack_count <= 1;
    apb_write(CMD_PORT, private_cmd(7'h12, 1'b0, 8'd2));
    wait_status_idle();
    slave_ack_addr <= 1'b0;
    slave_i2c_write_ack_count <= 0;

    apb_read(RESP_PORT, response);
    expect_eq("RESP.i2c.data_nack", response,
              32'h0000_0002, 32'h0000_0003);
    apb_read(REG_ERR_STATUS, rdata);
    expect_eq("ERR_STATUS after I2C data NACK", rdata,
              32'h0000_0002, 32'h0000_0002);
    apb_write(REG_ERR_STATUS, 32'h0000_0002);

    $display("[%0t] Run I2C private 2-byte read with slave data", $time);
    slave_read_data[0] <= 8'h11;
    slave_read_data[1] <= 8'h22;
    slave_read_length <= 2;
    slave_ack_addr <= 1'b1;
    slave_read_en <= 1'b1;
    slave_i2c_read_mode <= 1'b1;

    apb_write(CMD_PORT, private_cmd(7'h12, 1'b1, 8'd2));
    wait_status_idle();

    slave_ack_addr <= 1'b0;
    slave_read_en <= 1'b0;
    slave_read_length <= 0;
    slave_i2c_read_mode <= 1'b0;

    apb_read(RESP_PORT, response);
    expect_eq("RESP.i2c.read.ok", response, 32'h0000_0000, 32'h0000_0003);

    apb_read(RX_PORT, rdata);
    expect_eq("I2C RX byte0", rdata, 32'h0000_0011, 32'h0000_00ff);
    apb_read(RX_PORT, rdata);
    expect_eq("I2C RX byte1", rdata, 32'h0000_0022, 32'h0000_00ff);

    apb_read(REG_ERR_STATUS, rdata);
    expect_eq("ERR_STATUS after I2C read", rdata, 32'h0000_0000, 32'h0000_0003);

    apb_write(REG_CTRL, 32'h0000_0003); // restore I3C mode

    $display("[%0t] Run IBI without MDB payload", $time);
    apb_write(REG_CTRL, 32'h0000_000b); // i3c_mode=1, core_en=1, ibi_en=1, ibi_mdb_en=0
    apb_read(REG_CTRL, rdata);
    expect_eq("CTRL.ibi.no_mdb", rdata, 32'h0000_000b, 32'h0000_001f);

    slave_send_ibi(7'h12, 1'b0, 8'h00);
    wait_irq_asserted();

    apb_read(REG_IBI_STATUS, rdata);
    expect_eq("IBI_STATUS.no_mdb", rdata, 32'h0001_0012, 32'h0001_ffff);
    apb_write(REG_IBI_STATUS, 32'h0001_0000);
    apb_read(REG_IBI_STATUS, rdata);
    expect_eq("IBI_STATUS.no_mdb cleared", rdata, 32'h0000_0012, 32'h0001_0000);

    apb_write(REG_CTRL, 32'h0000_0003); // disable IBI between back-to-back cases
    repeat (8) @(posedge pclk);

    $display("[%0t] Run IBI with one MDB payload byte", $time);
    apb_write(REG_CTRL, 32'h0000_001b); // i3c_mode=1, core_en=1, ibi_en=1, ibi_mdb_en=1
    apb_read(REG_CTRL, rdata);
    expect_eq("CTRL.ibi.mdb", rdata, 32'h0000_001b, 32'h0000_001f);
    repeat (8) @(posedge pclk);

    slave_send_ibi(7'h12, 1'b1, 8'h5a);
    wait_irq_asserted();

    apb_read(REG_IBI_STATUS, rdata);
    expect_eq("IBI_STATUS.mdb", rdata, 32'h0001_0192, 32'h0001_ffff);
    apb_read(RX_PORT, rdata);
    expect_eq("IBI MDB byte", rdata, 32'h0000_005a, 32'h0000_00ff);
    apb_write(REG_IBI_STATUS, 32'h0001_0000);
    apb_read(REG_IBI_STATUS, rdata);
    expect_eq("IBI_STATUS.mdb cleared", rdata, 32'h0000_0092, 32'h0001_0000);

    apb_write(REG_CTRL, 32'h0000_0003); // restore I3C mode, IBI disabled

    if (errors == 0) begin
      $display("[%0t] TEST PASSED", $time);
    end else begin
      $fatal(1, "TEST FAILED with %0d error(s)", errors);
    end

    repeat (10) @(posedge pclk);
    $finish;
  end
endmodule

`default_nettype wire
