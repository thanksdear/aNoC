class i3c_virtual_seq extends uvm_sequence;
  `uvm_object_utils(i3c_virtual_seq)
  `uvm_declare_p_sequencer(i3c_virtual_sequencer)

  function new(string name = "i3c_virtual_seq");
    super.new(name);
  endfunction

  task pre_body();
    super.pre_body();
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
    // The legacy electrical responder uses this count as the number of write
    // bytes to observe.  In I3C mode it releases, rather than ACKs, each T-bit.
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
