typedef enum logic [1:0] {
  TARGET_INTENT_PRIVATE,
  TARGET_INTENT_CCC_BCAST,
  TARGET_INTENT_CCC_DIRECT,
  TARGET_INTENT_ENTDAA
} i3c_target_intent_kind_e;

// Independent target-side plan published before the target drives an address
// ACK.  The scoreboard can compare both the bus and RX data against this
// configured intent instead of using bus-monitor data as its own expectation.
class i3c_target_intent extends uvm_object;
  i3c_target_intent_kind_e kind;
  logic [6:0]              expected_addr;
  logic                    direction;    // 0=write, 1=read
  logic                    expect_ack;
  int unsigned             write_ack_count; // legacy I2C data ACKs before NACK
  int unsigned             read_length;  // target 准备发送的有效 byte 数
  logic [7:0]              read_data[$];
  logic                    entdaa_participate;
  logic [63:0]             entdaa_id;
  logic [6:0]              entdaa_expected_da;
  logic                    entdaa_expect_da_ack;

  `uvm_object_utils_begin(i3c_target_intent)
    `uvm_field_enum(i3c_target_intent_kind_e, kind, UVM_ALL_ON)
    `uvm_field_int(expected_addr, UVM_ALL_ON)
    `uvm_field_int(direction, UVM_ALL_ON)
    `uvm_field_int(expect_ack, UVM_ALL_ON)
    `uvm_field_int(write_ack_count, UVM_ALL_ON)
    `uvm_field_int(read_length, UVM_ALL_ON)
    `uvm_field_queue_int(read_data, UVM_ALL_ON)
    `uvm_field_int(entdaa_participate, UVM_ALL_ON)
    `uvm_field_int(entdaa_id, UVM_ALL_ON)
    `uvm_field_int(entdaa_expected_da, UVM_ALL_ON)
    `uvm_field_int(entdaa_expect_da_ack, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "i3c_target_intent");
    super.new(name);
  endfunction
endclass

// IBI is target-initiated and has no APB command descriptor.  Keep its plan
// on a dedicated analysis path so it cannot consume or reorder the target
// intents paired with controller-initiated private/CCC commands.
class i3c_ibi_intent extends uvm_object;
  logic [6:0] expected_addr;
  logic       expect_addr_ack;
  logic       has_mdb;
  logic [7:0] mdb;
  logic       expect_target_t_low;
  logic       expect_controller_t_low;

  `uvm_object_utils_begin(i3c_ibi_intent)
    `uvm_field_int(expected_addr, UVM_ALL_ON)
    `uvm_field_int(expect_addr_ack, UVM_ALL_ON)
    `uvm_field_int(has_mdb, UVM_ALL_ON)
    `uvm_field_int(mdb, UVM_ALL_ON)
    `uvm_field_int(expect_target_t_low, UVM_ALL_ON)
    `uvm_field_int(expect_controller_t_low, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "i3c_ibi_intent");
    super.new(name);
  endfunction
endclass

class i3c_target_model extends uvm_component;
  `uvm_component_utils(i3c_target_model)

  localparam logic [6:0] SLAVE_ADDR = 7'h12;
  localparam logic [7:0] CCC_ENTDAA = 8'h07;
  localparam logic [63:0] ENTDAA_ID = 64'h1234_5678_9abc_de01;
  localparam logic [6:0] ENTDAA_EXPECTED_DA = 7'h01;

  virtual i3c_if vif;
  uvm_analysis_port #(i3c_target_intent) intent_ap;
  uvm_analysis_port #(i3c_ibi_intent) ibi_intent_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    intent_ap = new("intent_ap", this);
    ibi_intent_ap = new("ibi_intent_ap", this);
    if (!uvm_config_db#(virtual i3c_if)::get(this, "", "vif", vif))
      `uvm_fatal("TGT", "target model 拿不到 vif")
  endfunction

  task publish_intent(i3c_target_intent_kind_e kind,
                      logic [6:0] expected_addr,
                      logic direction,
                      logic expect_ack);
    i3c_target_intent intent;

    intent = i3c_target_intent::type_id::create("intent");
    intent.kind = kind;
    intent.expected_addr = expected_addr;
    intent.direction = direction;
    intent.expect_ack = expect_ack;
    intent.write_ack_count = direction ? 0 :
                             vif.slave_i2c_write_ack_count;
    intent.read_length = direction ? vif.slave_read_length : 0;
    intent.entdaa_participate = 1'b0;
    intent.entdaa_id = '0;
    intent.entdaa_expected_da = '0;
    intent.entdaa_expect_da_ack = 1'b0;

    if (direction && expect_ack) begin
      if (intent.read_length == 0 || intent.read_length > 4)
        `uvm_error(
          "TGT_READ_PLAN",
          $sformatf(
            "read_length must be in 1..4 for this target model, got %0d",
            intent.read_length
          )
        )
      for (int i = 0; i < intent.read_length && i < 4; i++)
        intent.read_data.push_back(vif.slave_read_data[i]);
    end
    intent_ap.write(intent);
  endtask

  task publish_ibi_intent();
    i3c_ibi_intent intent;

    intent = i3c_ibi_intent::type_id::create("ibi_intent");
    intent.expected_addr = vif.ibi_plan_addr;
    intent.expect_addr_ack = vif.ibi_plan_expect_addr_ack;
    intent.has_mdb = vif.ibi_plan_has_mdb;
    intent.mdb = vif.ibi_plan_mdb;
    // For the one-MDB model the MDB is also the target's final byte, so the
    // target owns End-of-Data and drives T low.  The controller may pull the
    // same OD bit low because this RTL intentionally accepts at most one MDB.
    intent.expect_target_t_low = vif.ibi_plan_has_mdb;
    intent.expect_controller_t_low =
      vif.ibi_plan_expect_controller_t_low;
    ibi_intent_ap.write(intent);
  endtask

  // One ENTDAA intent describes the complete single-target plan.  A target
  // that participates ACKs the first 7E/R header, arbitrates its ID, ACKs the
  // expected assigned DA, then implicitly NACKs the next 7E/R round.
  task publish_entdaa_intent(logic participate);
    i3c_target_intent intent;

    intent = i3c_target_intent::type_id::create("entdaa_intent");
    intent.kind = TARGET_INTENT_ENTDAA;
    intent.expected_addr = 7'h7e;
    intent.direction = 1'b1;
    intent.expect_ack = participate;
    intent.write_ack_count = 0;
    intent.read_length = 0;
    intent.entdaa_participate = participate;
    intent.entdaa_id = ENTDAA_ID;
    intent.entdaa_expected_da = ENTDAA_EXPECTED_DA;
    intent.entdaa_expect_da_ack = participate;
    intent_ap.write(intent);
  endtask

  task run_phase(uvm_phase phase);
    longint unsigned target_epoch;

    forever begin
      // A hard reset can arrive while handle_frame() is blocked waiting for an
      // SCL edge.  Run frame handling in a reset epoch so reset immediately
      // aborts the in-flight target task and releases the bus.
      init_slave();
      wait (vif.rst_n === 1'b1);
      target_epoch = vif.tb_reset_epoch;
      fork : target_reset_epoch
        begin
          wait ((vif.rst_n !== 1'b1) ||
                (vif.tb_reset_epoch != target_epoch));
        end
        begin
          forever begin
            @(negedge vif.sda_in);
            if (vif.rst_n === 1'b1 && vif.scl_in && !vif.slave_drive_low)
              handle_frame();
          end
        end
        begin
          forever begin
            @(posedge vif.ibi_plan_valid);
            if (vif.rst_n === 1'b1)
              publish_ibi_intent();
          end
        end
      join_any
      disable target_reset_epoch;
    end
  endtask

  task init_slave();
    vif.slave_drive_low <= 1'b0;
    vif.slave_ack_addr <= 1'b0;
    vif.slave_read_en <= 1'b0;
    vif.slave_read_length <= 0;
    vif.slave_i2c_read_mode <= 1'b0;
    vif.slave_i3c_write_tbit_mode <= 1'b0;
    vif.slave_i2c_write_ack_count <= 0;
    vif.ccc_ack_en <= 1'b0;
    vif.ccc_direct_en <= 1'b0;
    vif.entdaa_slave_en <= 1'b0;
    vif.expect_ccc_target <= 1'b0;
    foreach (vif.slave_read_data[i])
      vif.slave_read_data[i] <= 8'h00;
    vif.slave_dbg_addr_byte <= 8'h00;
    vif.slave_dbg_ccc_byte <= 8'h00;
    vif.slave_dbg_write_byte <= 8'h00;
    vif.slave_dbg_entdaa_da <= 8'h00;
    vif.slave_dbg_matched <= 1'b0;
    vif.slave_dbg_ack_phase <= 1'b0;
  endtask

  task wait_entdaa_start();
    forever begin
      @(negedge vif.sda_in);
      if (vif.scl_in === 1'b1)
        return;
    end
  endtask

  task wait_entdaa_stop();
    forever begin
      @(posedge vif.sda_in);
      if (vif.scl_in === 1'b1)
        return;
    end
  endtask

  task handle_entdaa();
    logic [7:0] header_byte;
    logic [7:0] da_byte;
    logic       assigned;
    logic       participate;
    logic       da_valid;

    participate = vif.entdaa_slave_en;
    assigned = 1'b0;
    publish_entdaa_intent(participate);

    forever begin
      // The CCC prefix has completed.  Every discovery round starts with a
      // repeated START and the broadcast read header 7E/R (8'hfd).
      wait_entdaa_start();
      for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
        @(posedge vif.scl_in);
        header_byte[bit_idx] = vif.sda_in;
      end

      if (header_byte !== 8'hfd)
        `uvm_error(
          "TGT_ENTDAA",
          $sformatf("expected ENTDAA 7E/R header 0xfd, got 0x%02h",
                    header_byte)
        )

      // The single target participates once.  After successful assignment it
      // NACKs the next header, which is the controller's normal termination
      // condition when no unaddressed target remains.
      if (!participate || assigned || header_byte !== 8'hfd) begin
        @(negedge vif.scl_in);
        vif.slave_dbg_ack_phase <= 1'b1;
        vif.slave_drive_low <= 1'b0;
        @(posedge vif.scl_in);
        vif.slave_dbg_ack_phase <= 1'b0;
        wait_entdaa_stop();
        return;
      end

      @(negedge vif.scl_in);
      vif.slave_dbg_ack_phase <= 1'b1;
      vif.slave_drive_low <= 1'b1; // ACK the first 7E/R header.
      @(posedge vif.scl_in);
      @(negedge vif.scl_in);
      vif.slave_drive_low <= 1'b0;
      vif.slave_dbg_ack_phase <= 1'b0;

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

      da_valid = ((^da_byte) === 1'b1) &&
                 (da_byte[7:1] === ENTDAA_EXPECTED_DA);
      if (!da_valid)
        `uvm_error(
          "TGT_ENTDAA",
          $sformatf(
            "invalid assigned DA/parity: got byte=0x%02h expected DA=0x%02h",
            da_byte, ENTDAA_EXPECTED_DA
          )
        )

      @(negedge vif.scl_in);
      vif.slave_dbg_ack_phase <= 1'b1;
      vif.slave_drive_low <= da_valid; // ACK only a valid expected DA.
      @(posedge vif.scl_in);
      @(negedge vif.scl_in);
      vif.slave_drive_low <= 1'b0;
      vif.slave_dbg_ack_phase <= 1'b0;

      if (!da_valid) begin
        wait_entdaa_stop();
        return;
      end

      assigned = 1'b1;
    end
  endtask

  task handle_frame();
    logic [7:0] addr_byte;
    logic [7:0] ccc_byte;
    logic [7:0] read_byte;
    logic       matched;
    logic       cont;
    logic       target_more;
    int         byte_idx;
    int unsigned read_length;
    int         write_ack_count;

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
      publish_intent(TARGET_INTENT_CCC_DIRECT, SLAVE_ADDR,
                     vif.slave_read_en, vif.slave_ack_addr);
      @(negedge vif.scl_in);
      vif.slave_dbg_ack_phase <= 1'b1;
      if (matched)
        vif.slave_drive_low <= 1'b1;
      @(posedge vif.scl_in);
      @(negedge vif.scl_in);
      vif.slave_drive_low <= 1'b0;
      vif.slave_dbg_ack_phase <= 1'b0;
    end else if (addr_byte == 8'hfc) begin
      matched = vif.ccc_ack_en;
      vif.slave_dbg_matched <= matched;
      publish_intent(TARGET_INTENT_CCC_BCAST, 7'h7e,
                     1'b0, vif.ccc_ack_en);
      @(negedge vif.scl_in);
      vif.slave_dbg_ack_phase <= 1'b1;
      if (matched)
        vif.slave_drive_low <= 1'b1;
      @(posedge vif.scl_in);
      @(negedge vif.scl_in);
      vif.slave_drive_low <= 1'b0;
      vif.slave_dbg_ack_phase <= 1'b0;

      if (!matched)
        return;

      for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
        @(posedge vif.scl_in);
        ccc_byte[bit_idx] = vif.sda_in;
      end
      vif.slave_dbg_ccc_byte <= ccc_byte;

      // CCC Code is an I3C write byte.  Its ninth bit is odd parity (T),
      // driven by the controller; it is not an ACK driven by the target.
      @(negedge vif.scl_in);
      vif.slave_drive_low <= 1'b0;
      @(posedge vif.scl_in);

      if (vif.ccc_direct_en) begin
        // Return before the controller creates Sr so run_phase can recognize
        // the following target-address START and ACK that address normally.
        vif.expect_ccc_target <= 1'b1;
        return;
      end else begin
        @(negedge vif.scl_in);
        if (ccc_byte == CCC_ENTDAA)
          handle_entdaa();
        return;
      end
    end else begin
      matched = vif.slave_ack_addr && (addr_byte[7:1] == SLAVE_ADDR);
      vif.slave_dbg_matched <= matched;
      publish_intent(TARGET_INTENT_PRIVATE, SLAVE_ADDR,
                     vif.slave_read_en, vif.slave_ack_addr);
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
        if (vif.slave_i3c_write_tbit_mode) begin
          // I3C write byte ninth bit is controller-driven odd parity (T).
          // The target only observes it and must not mask a bad controller T.
          vif.slave_dbg_ack_phase <= 1'b0;
          vif.slave_drive_low <= 1'b0;
        end else begin
          // Legacy I2C write byte ninth bit is target-driven ACK.
          vif.slave_dbg_ack_phase <= 1'b1;
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

    read_length = vif.slave_read_length;
    if (read_length == 0 || read_length > 4) begin
      `uvm_error(
        "TGT_READ_PLAN",
        $sformatf(
          "cannot drive read with read_length=%0d; supported range is 1..4",
          read_length
        )
      )
      return;
    end

    byte_idx = 0;
    forever begin
      read_byte = vif.slave_read_data[byte_idx];
      for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
        vif.slave_drive_low <= !read_byte[bit_idx];
        @(posedge vif.scl_in);
        @(negedge vif.scl_in);
      end

      target_more = ((byte_idx + 1) < read_length);
      // I3C read: target drives the initial T-bit (1=more, 0=end).  Because
      // SDA is OD, the controller can still pull a target T=1 low to terminate
      // before the target's planned end.  I2C keeps the target released while
      // the controller drives ACK/NACK.
      vif.slave_drive_low <= vif.slave_i2c_read_mode ? 1'b0 : !target_more;
      @(posedge vif.scl_in);
      cont = vif.slave_i2c_read_mode ? !vif.sda_in : vif.sda_in;
      @(negedge vif.scl_in);
      vif.slave_drive_low <= 1'b0;

      byte_idx++;
      if (!cont)
        return;
    end
  endtask
endclass
