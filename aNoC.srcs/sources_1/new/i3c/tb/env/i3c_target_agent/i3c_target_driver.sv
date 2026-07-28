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
  int                      write_parity_error_index;
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
    `uvm_field_int(write_parity_error_index, UVM_ALL_ON)
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

class i3c_target_driver extends uvm_driver #(i3c_target_txn);
  `uvm_component_utils(i3c_target_driver)

  localparam logic [7:0] CCC_ENTDAA = 8'h07;
  localparam logic [7:0] CCC_SETDASA = 8'h87;

  virtual i3c_if vif;
  i3c_target_cfg cfg;
  uvm_analysis_port #(i3c_target_intent) intent_ap;
  uvm_analysis_port #(i3c_ibi_intent) ibi_intent_ap;

  // Runtime protocol policy belongs to the active target component.  Keeping
  // it here prevents controller sequences from driving target behavior through
  // shared interface variables.
  logic       ack_addr;
  logic       read_enable;
  logic       i2c_read_mode;
  logic       i3c_write_tbit_mode;
  int         write_ack_count;
  int         write_parity_error_index;
  logic       ccc_ack_enable;
  logic       ccc_direct_enable;
  logic       entdaa_participate;
  logic       expect_ccc_target;
  logic [7:0] pending_direct_ccc_code;
  logic [7:0] read_data[$];
  logic [6:0] dynamic_addr;
  logic       dynamic_addr_valid;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    intent_ap = new("intent_ap", this);
    ibi_intent_ap = new("ibi_intent_ap", this);
    if (!uvm_config_db#(virtual i3c_if)::get(this, "", "vif", vif))
      `uvm_fatal("TGT", "target model 拿不到 vif")
    if (!uvm_config_db#(i3c_target_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("TGT", "target driver 拿不到 cfg")
  endfunction

  function logic [6:0] effective_addr();
    return dynamic_addr_valid ? dynamic_addr : cfg.static_addr;
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
    intent.write_ack_count = direction ? 0 : write_ack_count;
    intent.write_parity_error_index =
      direction ? -1 : write_parity_error_index;
    intent.read_length = direction ? read_data.size() : 0;
    intent.entdaa_participate = 1'b0;
    intent.entdaa_id = '0;
    intent.entdaa_expected_da = '0;
    intent.entdaa_expect_da_ack = 1'b0;

    if (direction && expect_ack) begin
      if (intent.read_length == 0 ||
          intent.read_length > cfg.max_read_bytes)
        `uvm_error(
          "TGT_READ_PLAN",
          $sformatf(
            "read_length must be in 1..%0d for this target model, got %0d",
            cfg.max_read_bytes, intent.read_length
          )
        )
      foreach (read_data[i])
        intent.read_data.push_back(read_data[i]);
    end
    intent_ap.write(intent);
  endtask

  task publish_ibi_intent(i3c_target_txn req);
    i3c_ibi_intent intent;

    intent = i3c_ibi_intent::type_id::create("ibi_intent");
    intent.expected_addr = req.ibi_addr;
    intent.expect_addr_ack = req.ibi_expect_addr_ack;
    intent.has_mdb = req.ibi_has_mdb;
    intent.mdb = req.ibi_mdb;
    // For the one-MDB model the MDB is also the target's final byte, so the
    // target owns End-of-Data and drives T low.  The controller may pull the
    // same OD bit low because this RTL intentionally accepts at most one MDB.
    intent.expect_target_t_low = req.ibi_has_mdb;
    intent.expect_controller_t_low = req.ibi_has_mdb;
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
    intent.write_parity_error_index = -1;
    intent.read_length = 0;
    intent.entdaa_participate = participate;
    intent.entdaa_id = cfg.entdaa_id;
    intent.entdaa_expected_da = cfg.entdaa_expected_da;
    intent.entdaa_expect_da_ack = participate;
    intent_ap.write(intent);
  endtask

  task respond_to_bus();
    longint unsigned target_epoch;

    forever begin
      // A hard reset can arrive while handle_frame() is blocked waiting for an
      // SCL edge.  Run frame handling in a reset epoch so reset immediately
      // aborts the in-flight target task and releases the bus.
      // A controller software reset advances tb_reset_epoch without asserting
      // rst_n.  It aborts the in-flight BFM response but must not erase an
      // external target's assigned dynamic address.  A hard reset clears it.
      init_target(vif.rst_n !== 1'b1);
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
            if (vif.rst_n === 1'b1 && vif.scl_in && !vif.target_drive_low)
              handle_frame();
          end
        end
      join_any
      disable target_reset_epoch;
    end
  endtask

  task apply_config(i3c_target_txn req);
    ack_addr = req.ack_addr;
    read_enable = req.read_enable;
    i2c_read_mode = req.i2c_read_mode;
    i3c_write_tbit_mode = req.i3c_write_tbit_mode;
    write_ack_count = req.i2c_write_ack_count;
    write_parity_error_index = req.write_parity_error_index;
    ccc_ack_enable = req.ccc_ack_enable;
    ccc_direct_enable = req.ccc_direct_enable;
    entdaa_participate = req.entdaa_participate;

    if ((req.write_parity_error_index >= 0) &&
        (!req.i3c_write_tbit_mode ||
         (req.write_parity_error_index >= req.i2c_write_ack_count)))
      `uvm_error(
        "TGT_CFG",
        $sformatf(
          "parity-error byte index %0d requires I3C T-bit mode and write count greater than the index",
          req.write_parity_error_index
        )
      )

    if (req.read_data.size() > cfg.max_read_bytes)
      `uvm_error(
        "TGT_CFG",
        $sformatf(
          "target supports at most %0d read bytes, got %0d",
          cfg.max_read_bytes, req.read_data.size()
        )
      )
    read_data.delete();
    foreach (req.read_data[i])
      read_data.push_back(req.read_data[i]);
  endtask

  task drive_ibi(i3c_target_txn req);
    logic [7:0] ibi_addr_byte;

    ibi_addr_byte = {req.ibi_addr, 1'b1};
    publish_ibi_intent(req);

    wait (vif.scl_in && vif.sda_in);
    vif.target_drive_low <= 1'b1;

    for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
      @(negedge vif.scl_in);
      @(posedge vif.clk);
      vif.target_drive_low <= !ibi_addr_byte[bit_idx];
      @(posedge vif.scl_in);
    end

    @(negedge vif.scl_in);
    @(posedge vif.clk);
    vif.target_drive_low <= 1'b0;
    @(posedge vif.scl_in);

    if (req.ibi_has_mdb && req.ibi_expect_addr_ack) begin
      for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
        @(negedge vif.scl_in);
        @(posedge vif.clk);
        vif.target_drive_low <= !req.ibi_mdb[bit_idx];
        @(posedge vif.scl_in);
      end

      @(negedge vif.scl_in);
      @(posedge vif.clk);
      vif.target_drive_low <= 1'b1;
      @(posedge vif.scl_in);
    end

    vif.target_drive_low <= 1'b0;
    wait (vif.scl_in && vif.sda_in);
    repeat (4) @(posedge vif.clk);
  endtask

  task process_items();
    forever begin
      i3c_target_txn req;
      seq_item_port.get_next_item(req);
      case (req.op)
        I3C_TARGET_CONFIG: apply_config(req);
        I3C_TARGET_IBI:    drive_ibi(req);
        default:
          `uvm_error("TGT_DRV", "unsupported target operation")
      endcase
      seq_item_port.item_done();
    end
  endtask

  task run_phase(uvm_phase phase);
    fork
      respond_to_bus(); // 监听并响应 I3C 总线。
      process_items();  // 接收 target sequence 发来的配置/IBI。
    join
  endtask

  task init_target(bit clear_dynamic_addr);
    vif.target_drive_low <= 1'b0;
    vif.target_fault_drive_low <= 1'b0;
    ack_addr = 1'b0;
    read_enable = 1'b0;
    i2c_read_mode = 1'b0;
    i3c_write_tbit_mode = 1'b0;
    write_ack_count = 0;
    write_parity_error_index = -1;
    ccc_ack_enable = 1'b0;
    ccc_direct_enable = 1'b0;
    entdaa_participate = 1'b0;
    expect_ccc_target = 1'b0;
    pending_direct_ccc_code = 8'h00;
    read_data.delete();
    if (clear_dynamic_addr) begin
      dynamic_addr = '0;
      dynamic_addr_valid = 1'b0;
    end
    vif.target_dbg_addr_byte <= 8'h00;
    vif.target_dbg_ccc_byte <= 8'h00;
    vif.target_dbg_write_byte <= 8'h00;
    vif.target_dbg_ack_phase <= 1'b0;
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

    // An already-addressed target is no longer part of the unaddressed
    // population, even if a stale test configuration still requests ENTDAA.
    participate = entdaa_participate && !dynamic_addr_valid;
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
        vif.target_dbg_ack_phase <= 1'b1;
        vif.target_drive_low <= 1'b0;
        @(posedge vif.scl_in);
        vif.target_dbg_ack_phase <= 1'b0;
        wait_entdaa_stop();
        return;
      end

      @(negedge vif.scl_in);
      vif.target_dbg_ack_phase <= 1'b1;
      vif.target_drive_low <= 1'b1; // ACK the first 7E/R header.
      @(posedge vif.scl_in);
      @(negedge vif.scl_in);
      vif.target_drive_low <= 1'b0;
      vif.target_dbg_ack_phase <= 1'b0;

      for (int bit_idx = 63; bit_idx >= 0; bit_idx--) begin
        vif.target_drive_low <= !cfg.entdaa_id[bit_idx];
        @(posedge vif.scl_in);
        @(negedge vif.scl_in);
      end
      vif.target_drive_low <= 1'b0;

      for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
        @(posedge vif.scl_in);
        da_byte[bit_idx] = vif.sda_in;
      end

      da_valid = ((^da_byte) === 1'b1) &&
                 (da_byte[7:1] === cfg.entdaa_expected_da);
      if (!da_valid)
        `uvm_error(
          "TGT_ENTDAA",
          $sformatf(
            "invalid assigned DA/parity: got byte=0x%02h expected DA=0x%02h",
            da_byte, cfg.entdaa_expected_da
          )
        )

      @(negedge vif.scl_in);
      vif.target_dbg_ack_phase <= 1'b1;
      vif.target_drive_low <= da_valid; // ACK only a valid expected DA.
      @(posedge vif.scl_in);
      @(negedge vif.scl_in);
      vif.target_drive_low <= 1'b0;
      vif.target_dbg_ack_phase <= 1'b0;

      if (!da_valid) begin
        wait_entdaa_stop();
        return;
      end

      // The address becomes active only after this target has accepted the
      // complete DA/parity byte and ACKed it.
      dynamic_addr = da_byte[7:1];
      dynamic_addr_valid = 1'b1;
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
    logic       direct_target_frame;
    logic [7:0] active_direct_ccc_code;
    logic       write_parity_valid;
    logic       observed_ninth;
    int         byte_idx;
    int unsigned read_length;

    vif.target_drive_low <= 1'b0;
    vif.target_fault_drive_low <= 1'b0;
    vif.target_dbg_ack_phase <= 1'b0;
    direct_target_frame = 1'b0;
    active_direct_ccc_code = 8'h00;
    write_parity_valid = 1'b1;

    for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
      @(posedge vif.scl_in);
      addr_byte[bit_idx] = vif.sda_in;
    end//存地址
    vif.target_dbg_addr_byte <= addr_byte;

    if (expect_ccc_target) begin
      expect_ccc_target = 1'b0;
      direct_target_frame = 1'b1;
      active_direct_ccc_code = pending_direct_ccc_code;
      pending_direct_ccc_code = 8'h00;
      matched = ack_addr &&
                (addr_byte[7:1] == effective_addr());
      publish_intent(TARGET_INTENT_CCC_DIRECT, effective_addr(),
                     addr_byte[0], ack_addr);
      @(negedge vif.scl_in);
      vif.target_dbg_ack_phase <= 1'b1;
      if (matched)
        vif.target_drive_low <= 1'b1;
      @(posedge vif.scl_in);
      @(negedge vif.scl_in);
      vif.target_drive_low <= 1'b0;
      vif.target_dbg_ack_phase <= 1'b0;
    end else if (addr_byte == 8'hfc) begin // CCC broadcast write
      matched = ccc_ack_enable;
      publish_intent(TARGET_INTENT_CCC_BCAST, 7'h7e,
                     1'b0, ccc_ack_enable);
      @(negedge vif.scl_in);
      vif.target_dbg_ack_phase <= 1'b1;
      if (matched)
        vif.target_drive_low <= 1'b1;
      @(posedge vif.scl_in);
      @(negedge vif.scl_in);
      vif.target_drive_low <= 1'b0;
      vif.target_dbg_ack_phase <= 1'b0;

      if (!matched)
        return;

      for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
        @(posedge vif.scl_in);
        ccc_byte[bit_idx] = vif.sda_in;
      end
      vif.target_dbg_ccc_byte <= ccc_byte;

      // CCC Code is an I3C write byte.  Its ninth bit is odd parity (T),
      // driven by the controller; it is not an ACK driven by the target.
      @(negedge vif.scl_in);
      vif.target_drive_low <= 1'b0;
      @(posedge vif.scl_in);

      if (ccc_direct_enable) begin
        // Return before the controller creates Sr so run_phase can recognize
        // the following target-address START and ACK that address normally.
        pending_direct_ccc_code = ccc_byte;
        expect_ccc_target = 1'b1;
        return;
      end else begin
        @(negedge vif.scl_in);
        if (ccc_byte == CCC_ENTDAA)
          handle_entdaa();
        return;
      end
    end else begin
      matched = ack_addr &&
                (addr_byte[7:1] == effective_addr());
      publish_intent(TARGET_INTENT_PRIVATE, effective_addr(),
                     addr_byte[0], ack_addr);
      @(negedge vif.scl_in);
      vif.target_dbg_ack_phase <= 1'b1;
      if (matched)
        vif.target_drive_low <= 1'b1;
      @(posedge vif.scl_in);
      @(negedge vif.scl_in);
      vif.target_drive_low <= 1'b0;
      vif.target_dbg_ack_phase <= 1'b0;
    end

    if (matched && !addr_byte[0] && write_ack_count > 0) begin
      for (byte_idx = 0; byte_idx < write_ack_count; byte_idx++) begin
        for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
          @(posedge vif.scl_in);
          read_byte[bit_idx] = vif.sda_in;
        end
        vif.target_dbg_write_byte <= read_byte;

        @(negedge vif.scl_in);
        if (i3c_write_tbit_mode) begin
          // I3C write byte ninth bit is controller-driven odd parity (T).
          // Fault injection uses a separate wired-low contribution so it
          // cannot masquerade as a legal target ACK.
          vif.target_dbg_ack_phase <= 1'b0;
          vif.target_drive_low <= 1'b0;
          if (byte_idx == write_parity_error_index) begin
            if ((~^read_byte) !== 1'b1)
              `uvm_error(
                "TGT_PARITY_INJECT",
                $sformatf(
                  "cannot corrupt byte[%0d]: data 0x%02x already has a low T-bit",
                  byte_idx, read_byte
                )
              )
            else
              vif.target_fault_drive_low <= 1'b1;
          end
        end else begin
          // Legacy I2C write byte ninth bit is target-driven ACK.
          vif.target_dbg_ack_phase <= 1'b1;
          vif.target_drive_low <= 1'b1;
        end
        @(posedge vif.scl_in);
        observed_ninth = vif.sda_in;
        if (i3c_write_tbit_mode) begin
          if (byte_idx == write_parity_error_index) begin
            write_parity_valid = 1'b0;
            if (observed_ninth !== 1'b0)
              `uvm_error(
                "TGT_WRITE_PARITY",
                "configured parity fault did not force the observed T-bit low"
              )
          end
          else if (observed_ninth !== (~^read_byte)) begin
            write_parity_valid = 1'b0;
            `uvm_error(
              "TGT_WRITE_PARITY",
              $sformatf(
                "write byte[%0d] data=0x%02h has T=%b, expected %b",
                byte_idx, read_byte, observed_ninth, ~^read_byte
              )
            )
          end
        end
        @(negedge vif.scl_in);
        vif.target_fault_drive_low <= 1'b0;
        vif.target_drive_low <= 1'b0;
        vif.target_dbg_ack_phase <= 1'b0;
      end

      if (direct_target_frame &&
          (active_direct_ccc_code == CCC_SETDASA)) begin
        if ((write_ack_count != 1) || !write_parity_valid ||
            (read_byte[0] !== 1'b0) ||
            (read_byte[7:1] inside {7'h00, 7'h7e, 7'h7f})) begin
          `uvm_error(
            "TGT_SETDASA",
            $sformatf(
              "SETDASA rejected: payload=0x%02h count=%0d parity_valid=%0b",
              read_byte, write_ack_count, write_parity_valid
            )
          )
        end
        else begin
          dynamic_addr = read_byte[7:1];
          dynamic_addr_valid = 1'b1;
          `uvm_info(
            "TGT_SETDASA",
            $sformatf("dynamic address committed: 0x%02h", dynamic_addr),
            UVM_LOW
          )
        end
      end
      return;
    end

    if (!matched || !addr_byte[0] || !read_enable)
      return;

    read_length = read_data.size();
    if (read_length == 0 || read_length > cfg.max_read_bytes) begin
      `uvm_error(
        "TGT_READ_PLAN",
        $sformatf(
          "cannot drive read with read_length=%0d; supported range is 1..%0d",
          read_length, cfg.max_read_bytes
        )
      )
      return;
    end

    byte_idx = 0;
    forever begin
      read_byte = read_data[byte_idx];
      for (int bit_idx = 7; bit_idx >= 0; bit_idx--) begin
        vif.target_drive_low <= !read_byte[bit_idx];
        @(posedge vif.scl_in);
        @(negedge vif.scl_in);
      end

      target_more = ((byte_idx + 1) < read_length);
      // I3C read: target drives the initial T-bit (1=more, 0=end).  Because
      // SDA is OD, the controller can still pull a target T=1 low to terminate
      // before the target's planned end.  I2C keeps the target released while
      // the controller drives ACK/NACK.
      vif.target_drive_low <= i2c_read_mode ? 1'b0 : !target_more;
      @(posedge vif.scl_in);
      cont = i2c_read_mode ? !vif.sda_in : vif.sda_in;
      @(negedge vif.scl_in);
      vif.target_drive_low <= 1'b0;

      byte_idx++;
      if (!cont)
        return;
    end
  endtask
endclass
