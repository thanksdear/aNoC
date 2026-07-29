class i3c_apb_reg_access_test extends i3c_base_test;
  `uvm_component_utils(i3c_apb_reg_access_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_apb_reg_access_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_apb_reg_access_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_bus_timing_test extends i3c_base_test;
  `uvm_component_utils(i3c_bus_timing_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_bus_timing_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_bus_timing_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_apb_strb_test extends i3c_base_test;
  `uvm_component_utils(i3c_apb_strb_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_apb_strb_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_apb_strb_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_sdr_private_write_test extends i3c_base_test;
  `uvm_component_utils(i3c_sdr_private_write_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_sdr_private_write_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_sdr_private_write_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_sdr_write_parity_error_test extends i3c_base_test;
  `uvm_component_utils(i3c_sdr_write_parity_error_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  task run_phase(uvm_phase phase);
    i3c_sdr_write_parity_error_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_sdr_write_parity_error_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_full_feature_test extends i3c_base_test;
  `uvm_component_utils(i3c_full_feature_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  task run_one(uvm_sequence #(i3c_txn) seq);
    reset_dut();
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
  endtask

  task run_one_virtual(uvm_sequence seq);
    reset_dut();
    run_virtual_seq(seq);
    repeat (20) @(posedge vif.clk);
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    run_one(i3c_apb_reg_access_seq::type_id::create("apb_reg_seq"));
    run_one(i3c_apb_strb_seq::type_id::create("apb_strb_seq"));
    run_one_virtual(
      i3c_bus_timing_vseq::type_id::create("bus_timing_vseq")
    );
    run_one_virtual(
      i3c_bus_timing_sweep_vseq::type_id::create("bus_timing_sweep_vseq")
    );
    run_one_virtual(
      i3c_sdr_private_write_vseq::type_id::create("sdr_write_vseq")
    );
    run_one_virtual(
      i3c_sdr_write_parity_error_vseq::type_id::create(
        "sdr_write_parity_error_vseq"
      )
    );
    run_one_virtual(
      i3c_sdr_private_write_len4_vseq::type_id::create(
        "sdr_write_len4_vseq"
      )
    );
    run_one_virtual(
      i3c_command_error_recovery_vseq::type_id::create(
        "command_error_recovery_vseq"
      )
    );
    run_one_virtual(
      i3c_target_agent_cmd_before_tx_vseq::type_id::create(
        "cmd_before_tx_vseq"
      )
    );
    run_one_virtual(
      i3c_target_agent_private_nack_vseq::type_id::create(
        "private_nack_vseq"
      )
    );
    run_one_virtual(
      i3c_target_agent_early_end_read_vseq::type_id::create(
        "sdr_read_vseq"
      )
    );
    run_one_virtual(
      i3c_target_agent_short_read_vseq::type_id::create(
        "sdr_short_read_vseq"
      )
    );
    run_one_virtual(
      i3c_target_agent_i2c_write_vseq::type_id::create("i2c_write_vseq")
    );
    run_one_virtual(
      i3c_target_agent_i2c_data_nack_vseq::type_id::create(
        "i2c_write_data_nack_vseq"
      )
    );
    run_one_virtual(
      i3c_target_agent_i2c_read_vseq::type_id::create("i2c_read_vseq")
    );
    run_one_virtual(
      i3c_broadcast_ccc_vseq::type_id::create("broadcast_ccc_vseq")
    );
    run_one_virtual(
      i3c_broadcast_ccc_nack_vseq::type_id::create(
        "broadcast_ccc_nack_vseq"
      )
    );
    run_one_virtual(
      i3c_broadcast_ccc_payload_vseq::type_id::create(
        "broadcast_ccc_payload_vseq"
      )
    );
    run_one_virtual(
      i3c_direct_ccc_vseq::type_id::create("direct_ccc_vseq")
    );
    run_one_virtual(
      i3c_direct_ccc_read_len2_vseq::type_id::create(
        "direct_ccc_read_len2_vseq"
      )
    );
    run_one_virtual(
      i3c_direct_ccc_read_short_vseq::type_id::create(
        "direct_ccc_read_short_vseq"
      )
    );
    run_one_virtual(
      i3c_direct_ccc_nack_vseq::type_id::create(
        "direct_ccc_nack_vseq"
      )
    );
    run_one_virtual(
      i3c_direct_ccc_write_vseq::type_id::create("direct_ccc_write_vseq")
    );
    run_one_virtual(i3c_entdaa_vseq::type_id::create("entdaa_vseq"));
    run_one_virtual(
      i3c_entdaa_dynamic_addr_vseq::type_id::create(
        "entdaa_dynamic_addr_vseq"
      )
    );
    run_one_virtual(i3c_sw_reset_vseq::type_id::create("sw_reset_vseq"));
    run_one_virtual(i3c_irq_access_vseq::type_id::create("irq_vseq"));
    run_one_virtual(
      i3c_polling_access_vseq::type_id::create("polling_access_vseq")
    );
    run_one_virtual(
      i3c_ibi_no_payload_vseq::type_id::create("ibi_no_payload_vseq")
    );
    run_one_virtual(
      i3c_ibi_payload_vseq::type_id::create("ibi_payload_vseq")
    );
    phase.drop_objection(this);
  endtask
endclass

class i3c_cmd_before_tx_test extends i3c_base_test;
  `uvm_component_utils(i3c_cmd_before_tx_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_target_agent_cmd_before_tx_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_target_agent_cmd_before_tx_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_bus_timing_sweep_test extends i3c_base_test;
  `uvm_component_utils(i3c_bus_timing_sweep_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_bus_timing_sweep_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_bus_timing_sweep_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_sdr_private_write_len4_test extends i3c_base_test;
  `uvm_component_utils(i3c_sdr_private_write_len4_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_sdr_private_write_len4_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_sdr_private_write_len4_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_command_error_recovery_test extends i3c_base_test;
  `uvm_component_utils(i3c_command_error_recovery_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    i3c_command_error_recovery_vseq vseq;

    phase.raise_objection(this);
    reset_dut();
    vseq =
      i3c_command_error_recovery_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_private_nack_test extends i3c_base_test;
  `uvm_component_utils(i3c_private_nack_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_target_agent_private_nack_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_target_agent_private_nack_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_sdr_private_read_test extends i3c_base_test;
  `uvm_component_utils(i3c_sdr_private_read_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_target_agent_early_end_read_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq =
      i3c_target_agent_early_end_read_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_sdr_private_read_short_test extends i3c_base_test;
  `uvm_component_utils(i3c_sdr_private_read_short_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_target_agent_short_read_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_target_agent_short_read_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_target_agent_smoke_test extends i3c_base_test;
  `uvm_component_utils(i3c_target_agent_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    i3c_target_agent_private_read_vseq vseq;

    phase.raise_objection(this);
    reset_dut();
    vseq =
      i3c_target_agent_private_read_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_i2c_private_write_test extends i3c_base_test;
  `uvm_component_utils(i3c_i2c_private_write_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_target_agent_i2c_write_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_target_agent_i2c_write_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_i2c_private_write_data_nack_test extends i3c_base_test;
  `uvm_component_utils(i3c_i2c_private_write_data_nack_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_target_agent_i2c_data_nack_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_target_agent_i2c_data_nack_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_i2c_private_read_test extends i3c_base_test;
  `uvm_component_utils(i3c_i2c_private_read_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_target_agent_i2c_read_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_target_agent_i2c_read_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_broadcast_ccc_test extends i3c_base_test;
  `uvm_component_utils(i3c_broadcast_ccc_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_broadcast_ccc_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_broadcast_ccc_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_broadcast_ccc_nack_test extends i3c_base_test;
  `uvm_component_utils(i3c_broadcast_ccc_nack_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    i3c_broadcast_ccc_nack_vseq vseq;

    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_broadcast_ccc_nack_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_broadcast_ccc_payload_test extends i3c_base_test;
  `uvm_component_utils(i3c_broadcast_ccc_payload_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    i3c_broadcast_ccc_payload_vseq vseq;

    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_broadcast_ccc_payload_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_direct_ccc_test extends i3c_base_test;
  `uvm_component_utils(i3c_direct_ccc_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_direct_ccc_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_direct_ccc_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_direct_ccc_read_len2_test extends i3c_base_test;
  `uvm_component_utils(i3c_direct_ccc_read_len2_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    i3c_direct_ccc_read_len2_vseq vseq;

    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_direct_ccc_read_len2_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_direct_ccc_read_short_test extends i3c_base_test;
  `uvm_component_utils(i3c_direct_ccc_read_short_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    i3c_direct_ccc_read_short_vseq vseq;

    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_direct_ccc_read_short_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_direct_ccc_nack_test extends i3c_base_test;
  `uvm_component_utils(i3c_direct_ccc_nack_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    i3c_direct_ccc_nack_vseq vseq;

    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_direct_ccc_nack_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_direct_ccc_write_test extends i3c_base_test;
  `uvm_component_utils(i3c_direct_ccc_write_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_direct_ccc_write_vseq vseq;
    i3c_irq_access_vseq       hard_reset_static_vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_direct_ccc_write_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);

    // SETDASA survives controller software reset, but a hard reset returns
    // this target model to its static address. A successful 0x12 access proves
    // the previous dynamic 0x22 assignment was cleared.
    reset_dut();
    hard_reset_static_vseq =
      i3c_irq_access_vseq::type_id::create("hard_reset_static_vseq");
    run_virtual_seq(hard_reset_static_vseq);

    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_entdaa_test extends i3c_base_test;
  `uvm_component_utils(i3c_entdaa_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_entdaa_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_entdaa_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_entdaa_dynamic_addr_test extends i3c_base_test;
  `uvm_component_utils(i3c_entdaa_dynamic_addr_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    i3c_entdaa_dynamic_addr_vseq vseq;

    phase.raise_objection(this);
    reset_dut();
    vseq =
      i3c_entdaa_dynamic_addr_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_ibi_no_payload_test extends i3c_base_test;
  `uvm_component_utils(i3c_ibi_no_payload_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_ibi_no_payload_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_ibi_no_payload_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_ibi_payload_test extends i3c_base_test;
  `uvm_component_utils(i3c_ibi_payload_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_ibi_payload_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_ibi_payload_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_irq_access_test extends i3c_base_test;
  `uvm_component_utils(i3c_irq_access_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_irq_access_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_irq_access_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_sw_reset_test extends i3c_base_test;
  `uvm_component_utils(i3c_sw_reset_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_sw_reset_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_sw_reset_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_polling_access_test extends i3c_base_test;
  `uvm_component_utils(i3c_polling_access_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_polling_access_vseq vseq;
    phase.raise_objection(this);
    reset_dut();
    vseq = i3c_polling_access_vseq::type_id::create("vseq");
    run_virtual_seq(vseq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass
