class i3c_virtual_seq extends uvm_sequence;
  `uvm_object_utils(i3c_virtual_seq)
  `uvm_declare_p_sequencer(i3c_virtual_sequencer)

  virtual i3c_if vif;

  function new(string name = "i3c_virtual_seq");
    super.new(name);
  endfunction

  task pre_body();
    super.pre_body();
    if (vif == null) begin
      if (!uvm_config_db#(virtual i3c_if)::get(null, "*", "vif", vif))
        `uvm_fatal("VSEQ", "virtual sequence cannot get vif")
    end
    if (p_sequencer.apb_sqr == null)
      `uvm_fatal("VSEQ", "virtual sequencer APB handle is null")
    if (p_sequencer.target_sqr == null)
      `uvm_fatal("VSEQ", "virtual sequencer target handle is null")
  endtask

  task configure_target(i3c_target_txn cfg_req);
    i3c_target_seq cfg_seq;

    cfg_seq = i3c_target_seq::type_id::create("cfg_seq");
    cfg_seq.req = cfg_req;
    cfg_seq.start(p_sequencer.target_sqr);
  endtask

  task idle_target();
    i3c_target_idle_seq idle_seq;

    idle_seq = i3c_target_idle_seq::type_id::create("idle_seq");
    idle_seq.start(p_sequencer.target_sqr);
  endtask
endclass

class i3c_target_agent_private_read_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_target_agent_private_read_vseq)

  function new(string name = "i3c_target_agent_private_read_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn                    cfg_req;
    i3c_target_agent_private_read_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.read_enable = 1'b1;
    cfg_req.read_data = new[2];
    cfg_req.read_data[0] = 8'hbe;
    cfg_req.read_data[1] = 8'hef;
    configure_target(cfg_req);

    controller_seq =
      i3c_target_agent_private_read_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_sdr_private_write_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_sdr_private_write_vseq)

  function new(string name = "i3c_sdr_private_write_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn          cfg_req;
    i3c_sdr_private_write_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    // Tell the target model how many controller write bytes to observe. In
    // I3C mode it releases, rather than ACKs, each T-bit.
    cfg_req.i2c_write_ack_count = 3;
    cfg_req.i3c_write_tbit_mode = 1'b1;
    configure_target(cfg_req);

    controller_seq =
      i3c_sdr_private_write_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_sdr_write_parity_error_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_sdr_write_parity_error_vseq)

  function new(string name = "i3c_sdr_write_parity_error_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn                   cfg_req;
    i3c_sdr_write_parity_error_seq   controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.i2c_write_ack_count = 1;
    cfg_req.i3c_write_tbit_mode = 1'b1;
    cfg_req.write_parity_error_index = 0;
    configure_target(cfg_req);

    controller_seq =
      i3c_sdr_write_parity_error_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_sdr_private_write_len4_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_sdr_private_write_len4_vseq)

  function new(string name = "i3c_sdr_private_write_len4_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn               cfg_req;
    i3c_sdr_private_write_len4_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.i2c_write_ack_count = 4;
    cfg_req.i3c_write_tbit_mode = 1'b1;
    configure_target(cfg_req);

    controller_seq =
      i3c_sdr_private_write_len4_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_command_error_recovery_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_command_error_recovery_vseq)

  function new(string name = "i3c_command_error_recovery_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn                  cfg_req;
    i3c_back_to_back_write_seq      queued_write_seq;
    i3c_queued_nack_recovery_seq    nack_recovery_seq;
    i3c_queued_parity_recovery_seq  parity_recovery_seq;

    // Two queued successful commands exercise command/TX/response ordering.
    cfg_req = i3c_target_txn::type_id::create("queued_write_cfg");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.i2c_write_ack_count = 1;
    cfg_req.i3c_write_tbit_mode = 1'b1;
    configure_target(cfg_req);
    queued_write_seq =
      i3c_back_to_back_write_seq::type_id::create("queued_write_seq");
    queued_write_seq.start(p_sequencer.apb_sqr);

    // Queue a wrong-address command followed by a valid command. The target
    // uses the same policy for both; only the observed address changes ACK.
    cfg_req = i3c_target_txn::type_id::create("nack_recovery_cfg");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    configure_target(cfg_req);
    nack_recovery_seq =
      i3c_queued_nack_recovery_seq::type_id::create(
        "nack_recovery_seq"
      );
    nack_recovery_seq.start(p_sequencer.apb_sqr);

    // Queue a parity-fault write followed by a normal read. A single target
    // policy supports both directions, so no reconfiguration or reset occurs
    // between the two controller commands.
    cfg_req = i3c_target_txn::type_id::create("parity_recovery_cfg");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.read_enable = 1'b1;
    cfg_req.i2c_write_ack_count = 1;
    cfg_req.i3c_write_tbit_mode = 1'b1;
    cfg_req.write_parity_error_index = 0;
    cfg_req.read_data = new[2];
    cfg_req.read_data[0] = 8'hde;
    cfg_req.read_data[1] = 8'had;
    configure_target(cfg_req);
    parity_recovery_seq =
      i3c_queued_parity_recovery_seq::type_id::create(
        "parity_recovery_seq"
      );
    parity_recovery_seq.start(p_sequencer.apb_sqr);

    idle_target();
  endtask
endclass

class i3c_target_agent_private_nack_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_target_agent_private_nack_vseq)

  function new(string name = "i3c_target_agent_private_nack_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn                  cfg_req;
    i3c_private_nack_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b0;
    configure_target(cfg_req);

    controller_seq =
      i3c_private_nack_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_target_agent_short_read_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_target_agent_short_read_vseq)

  function new(string name = "i3c_target_agent_short_read_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn                  cfg_req;
    i3c_sdr_private_read_short_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.read_enable = 1'b1;
    cfg_req.read_data = new[1];
    cfg_req.read_data[0] = 8'he1;
    configure_target(cfg_req);

    controller_seq =
      i3c_sdr_private_read_short_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_target_agent_early_end_read_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_target_agent_early_end_read_vseq)

  function new(string name = "i3c_target_agent_early_end_read_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn                       cfg_req;
    i3c_sdr_private_read_seq controller_seq;

    // Target offers three bytes while the controller descriptor accepts two.
    // The controller must terminate on the second read T-bit.
    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.read_enable = 1'b1;
    cfg_req.read_data = new[3];
    cfg_req.read_data[0] = 8'h3c;
    cfg_req.read_data[1] = 8'ha7;
    cfg_req.read_data[2] = 8'hd2;
    configure_target(cfg_req);

    controller_seq =
      i3c_sdr_private_read_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_target_agent_cmd_before_tx_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_target_agent_cmd_before_tx_vseq)

  function new(string name = "i3c_target_agent_cmd_before_tx_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn                    cfg_req;
    i3c_cmd_before_tx_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.i2c_write_ack_count = 2;
    cfg_req.i3c_write_tbit_mode = 1'b1;
    configure_target(cfg_req);

    controller_seq =
      i3c_cmd_before_tx_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_target_agent_i2c_write_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_target_agent_i2c_write_vseq)

  function new(string name = "i3c_target_agent_i2c_write_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn                cfg_req;
    i3c_i2c_private_write_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.i2c_write_ack_count = 2;
    configure_target(cfg_req);

    controller_seq =
      i3c_i2c_private_write_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_target_agent_i2c_data_nack_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_target_agent_i2c_data_nack_vseq)

  function new(string name = "i3c_target_agent_i2c_data_nack_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn                    cfg_req;
    i3c_i2c_private_write_data_nack_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    // ACK byte[0], then stop driving ACK so byte[1] is NACKed.
    cfg_req.i2c_write_ack_count = 1;
    configure_target(cfg_req);

    controller_seq =
      i3c_i2c_private_write_data_nack_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_target_agent_i2c_read_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_target_agent_i2c_read_vseq)

  function new(string name = "i3c_target_agent_i2c_read_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn               cfg_req;
    i3c_i2c_private_read_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.read_enable = 1'b1;
    cfg_req.i2c_read_mode = 1'b1;
    cfg_req.read_data = new[2];
    cfg_req.read_data[0] = 8'h11;
    cfg_req.read_data[1] = 8'h22;
    configure_target(cfg_req);

    controller_seq =
      i3c_i2c_private_read_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_broadcast_ccc_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_broadcast_ccc_vseq)

  function new(string name = "i3c_broadcast_ccc_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn       cfg_req;
    i3c_broadcast_ccc_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ccc_ack_enable = 1'b1;
    configure_target(cfg_req);

    controller_seq =
      i3c_broadcast_ccc_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_broadcast_ccc_nack_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_broadcast_ccc_nack_vseq)

  function new(string name = "i3c_broadcast_ccc_nack_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn              cfg_req;
    i3c_broadcast_ccc_nack_seq  controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ccc_ack_enable = 1'b0;
    configure_target(cfg_req);

    controller_seq =
      i3c_broadcast_ccc_nack_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_broadcast_ccc_payload_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_broadcast_ccc_payload_vseq)

  function new(string name = "i3c_broadcast_ccc_payload_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn                 cfg_req;
    i3c_broadcast_ccc_payload_seq  controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ccc_ack_enable = 1'b1;
    configure_target(cfg_req);

    controller_seq =
      i3c_broadcast_ccc_payload_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_direct_ccc_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_direct_ccc_vseq)

  function new(string name = "i3c_direct_ccc_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn    cfg_req;
    i3c_direct_ccc_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.read_enable = 1'b1;
    cfg_req.ccc_ack_enable = 1'b1;
    cfg_req.ccc_direct_enable = 1'b1;
    cfg_req.read_data = new[1];
    cfg_req.read_data[0] = 8'h55;
    configure_target(cfg_req);

    controller_seq =
      i3c_direct_ccc_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_direct_ccc_read_len2_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_direct_ccc_read_len2_vseq)

  function new(string name = "i3c_direct_ccc_read_len2_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn                  cfg_req;
    i3c_direct_ccc_read_len2_seq    controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.read_enable = 1'b1;
    cfg_req.ccc_ack_enable = 1'b1;
    cfg_req.ccc_direct_enable = 1'b1;
    // Target offers three bytes; the controller must terminate after two.
    cfg_req.read_data = new[3];
    cfg_req.read_data[0] = 8'h31;
    cfg_req.read_data[1] = 8'hc3;
    cfg_req.read_data[2] = 8'h7e;
    configure_target(cfg_req);

    controller_seq =
      i3c_direct_ccc_read_len2_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_direct_ccc_read_short_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_direct_ccc_read_short_vseq)

  function new(string name = "i3c_direct_ccc_read_short_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn                  cfg_req;
    i3c_direct_ccc_read_short_seq   controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.read_enable = 1'b1;
    cfg_req.ccc_ack_enable = 1'b1;
    cfg_req.ccc_direct_enable = 1'b1;
    // Controller requests two bytes; target ends after its first byte.
    cfg_req.read_data = new[1];
    cfg_req.read_data[0] = 8'he1;
    configure_target(cfg_req);

    controller_seq =
      i3c_direct_ccc_read_short_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_direct_ccc_nack_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_direct_ccc_nack_vseq)

  function new(string name = "i3c_direct_ccc_nack_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn           cfg_req;
    i3c_direct_ccc_nack_seq  controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b0;
    cfg_req.ccc_ack_enable = 1'b1;
    cfg_req.ccc_direct_enable = 1'b1;
    configure_target(cfg_req);

    controller_seq =
      i3c_direct_ccc_nack_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_direct_ccc_write_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_direct_ccc_write_vseq)

  function new(string name = "i3c_direct_ccc_write_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn                         cfg_req;
    i3c_direct_ccc_write_seq               setdasa_seq;
    i3c_setdasa_private_write_seq          write_seq;
    i3c_setdasa_private_read_seq           read_seq;
    i3c_setdasa_old_static_nack_seq        old_addr_seq;
    i3c_setdasa_sw_reset_preserve_seq      reset_seq;

    // Phase 1: address the target by its static address and assign DA 0x22.
    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.i2c_write_ack_count = 1;
    cfg_req.i3c_write_tbit_mode = 1'b1;
    cfg_req.ccc_ack_enable = 1'b1;
    cfg_req.ccc_direct_enable = 1'b1;
    configure_target(cfg_req);

    setdasa_seq =
      i3c_direct_ccc_write_seq::type_id::create("controller_seq");
    setdasa_seq.start(p_sequencer.apb_sqr);

    // Phase 2: the new dynamic address accepts private write traffic.
    cfg_req = i3c_target_txn::type_id::create("dynamic_write_cfg");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.i2c_write_ack_count = 2;
    cfg_req.i3c_write_tbit_mode = 1'b1;
    configure_target(cfg_req);

    write_seq =
      i3c_setdasa_private_write_seq::type_id::create("write_seq");
    write_seq.start(p_sequencer.apb_sqr);

    // Phase 3: the same address accepts private read traffic.
    cfg_req = i3c_target_txn::type_id::create("dynamic_read_cfg");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.read_enable = 1'b1;
    cfg_req.read_data = new[2];
    cfg_req.read_data[0] = 8'h7c;
    cfg_req.read_data[1] = 8'hc7;
    configure_target(cfg_req);

    read_seq =
      i3c_setdasa_private_read_seq::type_id::create("read_seq");
    read_seq.start(p_sequencer.apb_sqr);

    // Phase 4: once DA is valid, the old static address no longer matches.
    cfg_req = i3c_target_txn::type_id::create("old_static_cfg");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    configure_target(cfg_req);

    old_addr_seq =
      i3c_setdasa_old_static_nack_seq::type_id::create("old_addr_seq");
    old_addr_seq.start(p_sequencer.apb_sqr);

    // Phase 5: controller software reset must not reset an external target's
    // assigned dynamic address. Reconfigure only the target BFM response policy.
    reset_seq =
      i3c_setdasa_sw_reset_preserve_seq::type_id::create("reset_seq");
    fork
      reset_seq.start(p_sequencer.apb_sqr);
      begin
        i3c_target_txn post_reset_cfg;
        reset_seq.post_reset_target_ready.wait_on();
        post_reset_cfg =
          i3c_target_txn::type_id::create("post_reset_cfg");
        post_reset_cfg.op = I3C_TARGET_CONFIG;
        post_reset_cfg.ack_addr = 1'b1;
        post_reset_cfg.i2c_write_ack_count = 1;
        post_reset_cfg.i3c_write_tbit_mode = 1'b1;
        configure_target(post_reset_cfg);
        reset_seq.post_reset_target_configured.trigger();
      end
    join

    idle_target();
  endtask
endclass

class i3c_entdaa_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_entdaa_vseq)

  function new(string name = "i3c_entdaa_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn cfg_req;
    i3c_entdaa_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ccc_ack_enable = 1'b1;
    cfg_req.entdaa_participate = 1'b1;
    configure_target(cfg_req);

    controller_seq = i3c_entdaa_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_entdaa_da_nack_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_entdaa_da_nack_vseq)

  function new(string name = "i3c_entdaa_da_nack_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn          cfg_req;
    i3c_entdaa_da_nack_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ccc_ack_enable = 1'b1;
    cfg_req.entdaa_participate = 1'b1;
    cfg_req.entdaa_expect_da_ack = 1'b0;
    configure_target(cfg_req);

    controller_seq =
      i3c_entdaa_da_nack_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_entdaa_dynamic_addr_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_entdaa_dynamic_addr_vseq)

  function new(string name = "i3c_entdaa_dynamic_addr_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn                       cfg_req;
    i3c_entdaa_seq                       entdaa_seq;
    i3c_dynamic_addr_private_write_seq   write_seq;
    i3c_dynamic_addr_private_read_seq    read_seq;

    // Phase 1: discover the target and assign DA 0x01.
    cfg_req = i3c_target_txn::type_id::create("entdaa_cfg");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ccc_ack_enable = 1'b1;
    cfg_req.entdaa_participate = 1'b1;
    configure_target(cfg_req);

    entdaa_seq = i3c_entdaa_seq::type_id::create("entdaa_seq");
    entdaa_seq.start(p_sequencer.apb_sqr);

    // Phase 2: the target must now match DA 0x01, not only static address 0x12.
    cfg_req = i3c_target_txn::type_id::create("dynamic_write_cfg");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.i2c_write_ack_count = 2;
    cfg_req.i3c_write_tbit_mode = 1'b1;
    configure_target(cfg_req);

    write_seq =
      i3c_dynamic_addr_private_write_seq::type_id::create("write_seq");
    write_seq.start(p_sequencer.apb_sqr);

    // Phase 3: read through the same assigned DA and verify the RX FIFO path.
    cfg_req = i3c_target_txn::type_id::create("dynamic_read_cfg");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.read_enable = 1'b1;
    cfg_req.read_data = new[2];
    cfg_req.read_data[0] = 8'ha6;
    cfg_req.read_data[1] = 8'h39;
    configure_target(cfg_req);

    read_seq =
      i3c_dynamic_addr_private_read_seq::type_id::create("read_seq");
    read_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_ibi_no_payload_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_ibi_no_payload_vseq)

  function new(string name = "i3c_ibi_no_payload_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_ibi_no_payload_seq controller_seq;
    i3c_target_ibi_seq     target_seq;

    controller_seq =
      i3c_ibi_no_payload_seq::type_id::create("controller_seq");
    target_seq = i3c_target_ibi_seq::type_id::create("target_seq");
    target_seq.addr = 7'h12;
    target_seq.has_mdb = 1'b0;
    target_seq.expect_addr_ack = 1'b1;

    fork
      controller_seq.start(p_sequencer.apb_sqr);
      begin
        controller_seq.target_ready.wait_on();
        target_seq.start(p_sequencer.target_sqr);
      end
    join
  endtask
endclass

class i3c_ibi_payload_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_ibi_payload_vseq)

  function new(string name = "i3c_ibi_payload_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_ibi_payload_seq controller_seq;
    i3c_target_ibi_seq  target_seq;

    controller_seq =
      i3c_ibi_payload_seq::type_id::create("controller_seq");
    target_seq = i3c_target_ibi_seq::type_id::create("target_seq");
    target_seq.addr = 7'h12;
    target_seq.has_mdb = 1'b1;
    target_seq.mdb = 8'h5a;
    target_seq.expect_addr_ack = 1'b1;

    fork
      controller_seq.start(p_sequencer.apb_sqr);
      begin
        controller_seq.target_ready.wait_on();
        target_seq.start(p_sequencer.target_sqr);
      end
    join
  endtask
endclass

class i3c_bus_timing_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_bus_timing_vseq)

  function new(string name = "i3c_bus_timing_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn      cfg_req;
    i3c_bus_timing_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.i2c_write_ack_count = 1;
    cfg_req.i3c_write_tbit_mode = 1'b1;
    configure_target(cfg_req);

    controller_seq = i3c_bus_timing_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_bus_timing_sweep_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_bus_timing_sweep_vseq)

  function new(string name = "i3c_bus_timing_sweep_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn            cfg_req;
    i3c_bus_timing_sweep_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    configure_target(cfg_req);

    controller_seq =
      i3c_bus_timing_sweep_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_irq_access_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_irq_access_vseq)

  function new(string name = "i3c_irq_access_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn     cfg_req;
    i3c_irq_access_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    configure_target(cfg_req);

    controller_seq = i3c_irq_access_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_polling_access_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_polling_access_vseq)

  function new(string name = "i3c_polling_access_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn         cfg_req;
    i3c_polling_access_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    cfg_req.i2c_write_ack_count = 3;
    cfg_req.i3c_write_tbit_mode = 1'b1;
    configure_target(cfg_req);

    controller_seq =
      i3c_polling_access_seq::type_id::create("controller_seq");
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_sw_reset_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_sw_reset_vseq)

  function new(string name = "i3c_sw_reset_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn cfg_req;
    i3c_sw_reset_seq controller_seq;

    cfg_req = i3c_target_txn::type_id::create("cfg_req");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b1;
    configure_target(cfg_req);

    controller_seq = i3c_sw_reset_seq::type_id::create("controller_seq");
    fork
      controller_seq.start(p_sequencer.apb_sqr);
      begin
        i3c_target_txn post_reset_cfg;
        controller_seq.post_reset_target_ready.wait_on();
        post_reset_cfg =
          i3c_target_txn::type_id::create("post_reset_cfg");
        post_reset_cfg.op = I3C_TARGET_CONFIG;
        post_reset_cfg.ack_addr = 1'b1;
        configure_target(post_reset_cfg);
        controller_seq.post_reset_target_configured.trigger();
      end
    join
    idle_target();
  endtask
endclass

class i3c_constrained_random_private_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_constrained_random_private_vseq)

  int unsigned iterations = 30;

  function new(string name = "i3c_constrained_random_private_vseq");
    super.new(name);
  endfunction

  task body();
    for (int iter = 0; iter < iterations; iter++) begin
      i3c_random_private_cfg scenario;
      i3c_target_txn         cfg_req;
      i3c_random_private_seq controller_seq;

      scenario = i3c_random_private_cfg::type_id::create(
        $sformatf("scenario_%0d", iter)
      );
      if (!scenario.randomize())
        `uvm_fatal(
          "RAND_PRIVATE",
          $sformatf("scenario randomization failed at iteration %0d", iter)
        )

      `uvm_info(
        "RAND_PRIVATE",
        $sformatf(
          "iter=%0d mode=%s rw=%0b len=%0d target_len=%0d addr_ack=%0b i2c_ack_count=%0d parity_idx=%0d cmd_before_tx=%0b",
          iter,
          scenario.i3c_mode ? "I3C" : "I2C",
          scenario.rw,
          scenario.command_length,
          scenario.target_length,
          scenario.addr_ack,
          scenario.i2c_write_ack_count,
          scenario.parity_error_index,
          scenario.command_before_tx
        ),
        UVM_LOW
      )

      cfg_req = i3c_target_txn::type_id::create(
        $sformatf("target_cfg_%0d", iter)
      );
      cfg_req.op = I3C_TARGET_CONFIG;
      cfg_req.ack_addr = scenario.addr_ack;
      cfg_req.read_enable = scenario.rw;
      cfg_req.i2c_read_mode = scenario.rw && !scenario.i3c_mode;
      cfg_req.i3c_write_tbit_mode =
        !scenario.rw && scenario.i3c_mode;
      cfg_req.i2c_write_ack_count =
        scenario.i2c_write_ack_count;
      cfg_req.write_parity_error_index =
        scenario.parity_error_index;
      cfg_req.read_data = new[scenario.read_data.size()];
      foreach (scenario.read_data[i])
        cfg_req.read_data[i] = scenario.read_data[i];
      configure_target(cfg_req);

      controller_seq = i3c_random_private_seq::type_id::create(
        $sformatf("controller_seq_%0d", iter)
      );
      controller_seq.scenario = scenario;
      controller_seq.start(p_sequencer.apb_sqr);
    end
    idle_target();
  endtask
endclass

class i3c_constrained_random_ccc_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_constrained_random_ccc_vseq)

  int unsigned iterations = 20;

  function new(string name = "i3c_constrained_random_ccc_vseq");
    super.new(name);
  endfunction

  task body();
    for (int iter = 0; iter < iterations; iter++) begin
      i3c_random_ccc_cfg scenario;
      i3c_target_txn     cfg_req;
      i3c_random_ccc_seq controller_seq;

      scenario = i3c_random_ccc_cfg::type_id::create(
        $sformatf("scenario_%0d", iter)
      );
      if (!scenario.randomize())
        `uvm_fatal(
          "RAND_CCC",
          $sformatf("scenario randomization failed at iteration %0d", iter)
        )

      `uvm_info(
        "RAND_CCC",
        $sformatf(
          "iter=%0d kind=%s len=%0d target_len=%0d bcast_ack=%0b target_ack=%0b cmd_before_tx=%0b",
          iter,
          scenario.kind.name(),
          scenario.command_length,
          scenario.target_length,
          scenario.broadcast_ack,
          scenario.target_ack,
          scenario.command_before_tx
        ),
        UVM_LOW
      )

      cfg_req = i3c_target_txn::type_id::create(
        $sformatf("target_cfg_%0d", iter)
      );
      cfg_req.op = I3C_TARGET_CONFIG;
      cfg_req.ccc_ack_enable = scenario.broadcast_ack;
      cfg_req.ccc_direct_enable =
        (scenario.kind == I3C_RANDOM_DIRECT_CCC_READ);
      cfg_req.ack_addr = scenario.target_ack;
      cfg_req.read_enable =
        (scenario.kind == I3C_RANDOM_DIRECT_CCC_READ);
      cfg_req.read_data = new[scenario.read_data.size()];
      foreach (scenario.read_data[i])
        cfg_req.read_data[i] = scenario.read_data[i];
      configure_target(cfg_req);

      controller_seq = i3c_random_ccc_seq::type_id::create(
        $sformatf("controller_seq_%0d", iter)
      );
      controller_seq.scenario = scenario;
      controller_seq.start(p_sequencer.apb_sqr);
    end
    idle_target();
  endtask
endclass

class i3c_constrained_random_entdaa_vseq extends i3c_virtual_seq;
  `uvm_object_utils_begin(i3c_constrained_random_entdaa_vseq)
    `uvm_field_int(broadcast_ack, UVM_ALL_ON)
    `uvm_field_int(participate, UVM_ALL_ON)
    `uvm_field_int(expect_da_ack, UVM_ALL_ON)
  `uvm_object_utils_end

  rand logic broadcast_ack;
  rand logic participate;
  rand logic expect_da_ack;

  constraint c_entdaa_outcome {
    broadcast_ack dist {1'b1 := 9, 1'b0 := 1};
    if (!broadcast_ack) {
      participate == 1'b0;
      expect_da_ack == 1'b0;
    }
    else {
      participate dist {1'b1 := 4, 1'b0 := 1};
      if (participate)
        expect_da_ack dist {1'b1 := 3, 1'b0 := 1};
      else
        expect_da_ack == 1'b0;
    }
  }

  function new(string name = "i3c_constrained_random_entdaa_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn        cfg_req;
    i3c_random_entdaa_seq controller_seq;

    if (!randomize())
      `uvm_fatal("RAND_ENTDAA", "ENTDAA outcome randomization failed")

    `uvm_info(
      "RAND_ENTDAA",
      $sformatf(
        "broadcast_ack=%0b participate=%0b da_ack=%0b",
        broadcast_ack,
        participate,
        expect_da_ack
      ),
      UVM_LOW
    )

    cfg_req = i3c_target_txn::type_id::create("target_cfg");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ccc_ack_enable = broadcast_ack;
    cfg_req.entdaa_participate = participate;
    cfg_req.entdaa_expect_da_ack = expect_da_ack;
    configure_target(cfg_req);

    controller_seq =
      i3c_random_entdaa_seq::type_id::create("controller_seq");
    controller_seq.broadcast_ack = broadcast_ack;
    controller_seq.participate = participate;
    controller_seq.expect_da_ack = expect_da_ack;
    controller_seq.start(p_sequencer.apb_sqr);
    idle_target();
  endtask
endclass

class i3c_constrained_random_ibi_vseq extends i3c_virtual_seq;
  `uvm_object_utils_begin(i3c_constrained_random_ibi_vseq)
    `uvm_field_int(has_mdb, UVM_ALL_ON)
    `uvm_field_int(mdb, UVM_ALL_ON)
  `uvm_object_utils_end

  rand logic       has_mdb;
  rand logic [7:0] mdb;

  constraint c_ibi_shape {
    has_mdb dist {1'b1 := 2, 1'b0 := 1};
  }

  function new(string name = "i3c_constrained_random_ibi_vseq");
    super.new(name);
  endfunction

  task body();
    i3c_random_ibi_seq controller_seq;
    i3c_target_ibi_seq target_seq;

    if (!randomize())
      `uvm_fatal("RAND_IBI", "IBI randomization failed")

    `uvm_info(
      "RAND_IBI",
      $sformatf("has_mdb=%0b mdb=0x%02h", has_mdb, mdb),
      UVM_LOW
    )

    controller_seq =
      i3c_random_ibi_seq::type_id::create("controller_seq");
    controller_seq.has_mdb = has_mdb;
    controller_seq.mdb = mdb;

    target_seq = i3c_target_ibi_seq::type_id::create("target_seq");
    target_seq.addr = 7'h12;
    target_seq.has_mdb = has_mdb;
    target_seq.mdb = mdb;
    target_seq.expect_addr_ack = 1'b1;

    fork
      controller_seq.start(p_sequencer.apb_sqr);
      begin
        controller_seq.target_ready.wait_on();
        target_seq.start(p_sequencer.target_sqr);
      end
    join
  endtask
endclass

class i3c_ral_access_vseq extends i3c_virtual_seq;
  `uvm_object_utils(i3c_ral_access_vseq)

  i3c_reg_block ral;

  function new(string name = "i3c_ral_access_vseq");
    super.new(name);
  endfunction

  task ral_read_check(
    string         check_name,
    uvm_reg        rg,
    uvm_reg_data_t expected,
    uvm_reg_data_t mask = '1
  );
    uvm_status_e   status;
    uvm_reg_data_t value;

    rg.read(
      status,
      value,
      UVM_FRONTDOOR,
      ral.default_map,
      this
    );
    if (status != UVM_IS_OK)
      `uvm_error(
        "RAL",
        $sformatf("%s frontdoor read returned %s",
                  check_name, status.name())
      )
    else if ((value & mask) !== (expected & mask))
      `uvm_error(
        "RAL",
        $sformatf(
          "%s mismatch: got=0x%08h expected=0x%08h mask=0x%08h",
          check_name,
          value,
          expected,
          mask
        )
      )
    else
      `uvm_info(
        "RAL",
        $sformatf("%s PASS: 0x%08h", check_name, value & mask),
        UVM_LOW
      )

    if ((rg.get_mirrored_value() & mask) !== (value & mask))
      `uvm_error(
        "RAL",
        $sformatf(
          "%s mirror mismatch: mirror=0x%08h frontdoor=0x%08h",
          check_name,
          rg.get_mirrored_value(),
          value
        )
      )
  endtask

  task ral_write(
    string         operation_name,
    uvm_reg        rg,
    uvm_reg_data_t value
  );
    uvm_status_e status;

    rg.write(
      status,
      value,
      UVM_FRONTDOOR,
      ral.default_map,
      this
    );
    if (status != UVM_IS_OK)
      `uvm_error(
        "RAL",
        $sformatf("%s frontdoor write returned %s",
                  operation_name, status.name())
      )
  endtask

  task body();
    i3c_target_txn           cfg_req;
    i3c_ral_nack_trigger_seq nack_seq;

    if (ral == null)
      `uvm_fatal("RAL", "register model handle is null")

    // Hard-reset values and volatile status fields.
    ral_read_check(
      "BUS_TIMING_0 reset",
      ral.bus_timing_0,
      32'h0006_0006
    );
    ral_read_check(
      "BUS_TIMING_1 reset",
      ral.bus_timing_1,
      32'h0000_0002,
      32'h0000_ffff
    );
    ral_read_check("CTRL reset", ral.ctrl, 32'h0000_0001, 32'h1f);
    ral_read_check("STATUS idle", ral.status, 32'h0, 32'h3);
    ral_read_check("IBI_STATUS reset", ral.ibi_status, 32'h0, 32'h1ffff);
    ral_read_check("ERR_STATUS reset", ral.err_status, 32'h0, 32'h3);
    ral_read_check(
      "ENTDAA_STATUS reset",
      ral.entdaa_status,
      32'h0,
      32'h1ff
    );
    ral_read_check("ENTDAA_PID_LO reset", ral.entdaa_pid_lo, 32'h0);
    ral_read_check("ENTDAA_PID_HI reset", ral.entdaa_pid_hi, 32'h0);

    // Normal RW frontdoor accesses.
    ral_write(
      "BUS_TIMING_0 write",
      ral.bus_timing_0,
      32'h0007_0005
    );
    ral_read_check(
      "BUS_TIMING_0 readback",
      ral.bus_timing_0,
      32'h0007_0005
    );
    ral_write(
      "BUS_TIMING_1 write",
      ral.bus_timing_1,
      32'h0000_0003
    );
    ral_read_check(
      "BUS_TIMING_1 readback",
      ral.bus_timing_1,
      32'h0000_0003,
      32'h0000_ffff
    );
    ral_write("CTRL enable write", ral.ctrl, 32'h0000_0003);
    ral_read_check("CTRL enable readback", ral.ctrl, 32'h3, 32'h1f);

    // Produce a hardware-set volatile error, then clear it through W1C RAL.
    cfg_req = i3c_target_txn::type_id::create("nack_target_cfg");
    cfg_req.op = I3C_TARGET_CONFIG;
    cfg_req.ack_addr = 1'b0;
    configure_target(cfg_req);
    nack_seq =
      i3c_ral_nack_trigger_seq::type_id::create("nack_seq");
    nack_seq.start(p_sequencer.apb_sqr);

    ral_read_check("ERR_STATUS hardware NACK", ral.err_status, 32'h2, 32'h3);
    ral_write("ERR_STATUS W1C", ral.err_status, 32'h2);
    ral_read_check("ERR_STATUS cleared", ral.err_status, 32'h0, 32'h3);

    // sw_rst reads back as zero while the other CTRL configuration survives.
    ral_write("CTRL software reset", ral.ctrl, 32'h0000_0007);
    repeat (4) @(posedge vif.clk);
    ral_read_check(
      "CTRL software reset self clear",
      ral.ctrl,
      32'h0000_0003,
      32'h0000_001f
    );

    idle_target();
  endtask
endclass
