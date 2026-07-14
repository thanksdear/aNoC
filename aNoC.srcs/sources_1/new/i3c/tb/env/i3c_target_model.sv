class i3c_target_model extends uvm_component;
  `uvm_component_utils(i3c_target_model)

  localparam logic [6:0] SLAVE_ADDR = 7'h12;
  localparam logic [7:0] CCC_ENTDAA = 8'h07;
  localparam logic [63:0] ENTDAA_ID = 64'h1234_5678_9abc_de01;

  virtual i3c_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual i3c_if)::get(this, "", "vif", vif))
      `uvm_fatal("TGT", "target model 拿不到 vif")
  endfunction

  task run_phase(uvm_phase phase);
    init_slave();
    wait (vif.rst_n === 1'b1);
    forever begin
      @(negedge vif.sda_in);
      if (vif.scl_in && !vif.slave_drive_low &&
          (vif.slave_ack_addr || vif.slave_read_en || vif.ccc_ack_en))
        handle_frame();
    end
  endtask

  task init_slave();
    vif.slave_drive_low <= 1'b0;
    vif.slave_ack_addr <= 1'b0;
    vif.slave_read_en <= 1'b0;
    vif.slave_i2c_read_mode <= 1'b0;
    vif.slave_i3c_write_tbit_mode <= 1'b0;
    vif.slave_i2c_write_ack_count <= 0;
    vif.ccc_ack_en <= 1'b0;
    vif.ccc_direct_en <= 1'b0;
    vif.entdaa_slave_en <= 1'b0;
    vif.expect_ccc_target <= 1'b0;
    foreach (vif.slave_read_data[i])
      vif.slave_read_data[i] <= 8'h00;
  endtask

  task handle_entdaa();
    logic [7:0] da_byte;

    for (int bit_idx = 63; bit_idx >= 0; bit_idx--) begin
      vif.slave_drive_low <= !ENTDAA_ID[bit_idx];
      @(posedge vif.scl_in);
      @(negedge vif.scl_in);
    end
    vif.slave_drive_low <= 1'b0;

    for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
      @(posedge vif.scl_in);
      da_byte[bit_idx] = vif.sda_in;
    end
    vif.slave_dbg_entdaa_da <= da_byte;

    @(negedge vif.scl_in);
    vif.slave_dbg_ack_phase <= 1'b1;
    vif.slave_drive_low <= 1'b1;
    @(posedge vif.scl_in);
    @(negedge vif.scl_in);
    vif.slave_drive_low <= 1'b0;
    vif.slave_dbg_ack_phase <= 1'b0;

    for (int bit_idx = 63; bit_idx >= 0; bit_idx--) begin
      @(posedge vif.scl_in);
      @(negedge vif.scl_in);
    end

    for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
      @(posedge vif.scl_in);
      da_byte[bit_idx] = vif.sda_in;
    end
    vif.slave_dbg_entdaa_da <= da_byte;

    @(posedge vif.scl_in);
    @(negedge vif.scl_in);
  endtask

  task handle_frame();
    logic [7:0] addr_byte;
    logic [7:0] ccc_byte;
    logic [7:0] read_byte;
    logic       matched;
    logic       cont;
    int         byte_idx;
    int         write_ack_count;
    bit         tbit_drive_low;

    vif.slave_drive_low <= 1'b0;
    vif.slave_dbg_matched <= 1'b0;
    vif.slave_dbg_ack_phase <= 1'b0;

    for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
      @(posedge vif.scl_in);
      addr_byte[bit_idx] = vif.sda_in;
    end
    vif.slave_dbg_addr_byte <= addr_byte;

    if (vif.expect_ccc_target) begin
      vif.expect_ccc_target <= 1'b0;
      matched = vif.slave_ack_addr && (addr_byte[7:1] == SLAVE_ADDR);
      vif.slave_dbg_matched <= matched;
      @(negedge vif.scl_in);
      vif.slave_dbg_ack_phase <= 1'b1;
      if (matched)
        vif.slave_drive_low <= 1'b1;
      @(posedge vif.scl_in);
      @(negedge vif.scl_in);
      vif.slave_drive_low <= 1'b0;
      vif.slave_dbg_ack_phase <= 1'b0;
    end else if (vif.ccc_ack_en && addr_byte == 8'hfc) begin
      matched = 1'b1;
      vif.slave_dbg_matched <= matched;
      @(negedge vif.scl_in);
      vif.slave_dbg_ack_phase <= 1'b1;
      vif.slave_drive_low <= 1'b1;
      @(posedge vif.scl_in);
      @(negedge vif.scl_in);
      vif.slave_drive_low <= 1'b0;
      vif.slave_dbg_ack_phase <= 1'b0;

      for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
        @(posedge vif.scl_in);
        ccc_byte[bit_idx] = vif.sda_in;
      end
      vif.slave_dbg_ccc_byte <= ccc_byte;

      @(negedge vif.scl_in);
      vif.slave_dbg_ack_phase <= 1'b1;
      vif.slave_drive_low <= 1'b1;
      @(posedge vif.scl_in);
      if (vif.ccc_direct_en)
        repeat (4) @(posedge vif.clk);
      else
        @(negedge vif.scl_in);
      vif.slave_drive_low <= 1'b0;
      vif.slave_dbg_ack_phase <= 1'b0;

      if (!vif.ccc_direct_en) begin
        if (vif.entdaa_slave_en && ccc_byte == CCC_ENTDAA)
          handle_entdaa();
        return;
      end

      vif.expect_ccc_target <= 1'b1;
      return;
    end else begin
      matched = vif.slave_ack_addr && (addr_byte[7:1] == SLAVE_ADDR);
      vif.slave_dbg_matched <= matched;
      @(negedge vif.scl_in);
      vif.slave_dbg_ack_phase <= 1'b1;
      if (matched)
        vif.slave_drive_low <= 1'b1;
      @(posedge vif.scl_in);
      @(negedge vif.scl_in);
      vif.slave_drive_low <= 1'b0;
      vif.slave_dbg_ack_phase <= 1'b0;
    end

    if (matched && !addr_byte[0] && vif.slave_i2c_write_ack_count > 0) begin
      write_ack_count = vif.slave_i2c_write_ack_count;
      for (byte_idx = 0; byte_idx < write_ack_count; byte_idx++) begin
        for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
          @(posedge vif.scl_in);
          read_byte[bit_idx] = vif.sda_in;
        end
        vif.slave_dbg_write_byte <= read_byte;

        @(negedge vif.scl_in);
        vif.slave_dbg_ack_phase <= 1'b1;
        if (vif.slave_i3c_write_tbit_mode) begin
          tbit_drive_low = ^read_byte;
          vif.slave_drive_low <= tbit_drive_low;
        end else begin
          vif.slave_drive_low <= 1'b1;
        end
        @(posedge vif.scl_in);
        @(negedge vif.scl_in);
        vif.slave_drive_low <= 1'b0;
        vif.slave_dbg_ack_phase <= 1'b0;
      end
      return;
    end

    if (!matched || !addr_byte[0] || !vif.slave_read_en)
      return;

    byte_idx = 0;
    forever begin
      read_byte = (byte_idx < 4) ? vif.slave_read_data[byte_idx] : 8'hff;
      for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
        vif.slave_drive_low <= !read_byte[bit_idx];
        @(posedge vif.scl_in);
        @(negedge vif.scl_in);
      end

      vif.slave_drive_low <= 1'b0;
      @(posedge vif.scl_in);
      cont = vif.slave_i2c_read_mode ? !vif.sda_in : vif.sda_in;
      @(negedge vif.scl_in);

      byte_idx++;
      if (!cont)
        return;
    end
  endtask
endclass
