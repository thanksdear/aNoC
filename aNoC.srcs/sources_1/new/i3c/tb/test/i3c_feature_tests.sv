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
    i3c_bus_timing_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_bus_timing_seq::type_id::create("seq");
    run_i3c_seq(seq);
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
    i3c_sdr_private_write_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_sdr_private_write_seq::type_id::create("seq");
    run_i3c_seq(seq);
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

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    run_one(i3c_apb_reg_access_seq::type_id::create("apb_reg_seq"));
    run_one(i3c_apb_strb_seq::type_id::create("apb_strb_seq"));
    run_one(i3c_bus_timing_seq::type_id::create("bus_timing_seq"));
    run_one(i3c_bus_timing_sweep_seq::type_id::create("bus_timing_sweep_seq"));
    run_one(i3c_sdr_private_write_seq::type_id::create("sdr_write_seq"));
    run_one(i3c_sdr_private_write_len4_seq::type_id::create("sdr_write_len4_seq"));
    run_one(i3c_private_nack_seq::type_id::create("private_nack_seq"));
    run_one(i3c_sdr_private_read_seq::type_id::create("sdr_read_seq"));
    run_one(i3c_i2c_private_write_seq::type_id::create("i2c_write_seq"));
    run_one(i3c_i2c_private_read_seq::type_id::create("i2c_read_seq"));
    run_one(i3c_broadcast_ccc_seq::type_id::create("broadcast_ccc_seq"));
    run_one(i3c_direct_ccc_seq::type_id::create("direct_ccc_seq"));
    run_one(i3c_direct_ccc_write_seq::type_id::create("direct_ccc_write_seq"));
    run_one(i3c_entdaa_seq::type_id::create("entdaa_seq"));
    run_one(i3c_sw_reset_seq::type_id::create("sw_reset_seq"));
    run_one(i3c_irq_access_seq::type_id::create("irq_seq"));
    run_one(i3c_ibi_no_payload_seq::type_id::create("ibi_no_payload_seq"));
    run_one(i3c_ibi_payload_seq::type_id::create("ibi_payload_seq"));
    phase.drop_objection(this);
  endtask
endclass

class i3c_bus_timing_sweep_test extends i3c_base_test;
  `uvm_component_utils(i3c_bus_timing_sweep_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_bus_timing_sweep_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_bus_timing_sweep_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_sdr_private_write_len4_test extends i3c_base_test;
  `uvm_component_utils(i3c_sdr_private_write_len4_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_sdr_private_write_len4_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_sdr_private_write_len4_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_private_nack_test extends i3c_base_test;
  `uvm_component_utils(i3c_private_nack_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_private_nack_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_private_nack_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_sdr_private_read_test extends i3c_base_test;
  `uvm_component_utils(i3c_sdr_private_read_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_sdr_private_read_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_sdr_private_read_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_i2c_private_write_test extends i3c_base_test;
  `uvm_component_utils(i3c_i2c_private_write_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_i2c_private_write_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_i2c_private_write_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_i2c_private_read_test extends i3c_base_test;
  `uvm_component_utils(i3c_i2c_private_read_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_i2c_private_read_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_i2c_private_read_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_broadcast_ccc_test extends i3c_base_test;
  `uvm_component_utils(i3c_broadcast_ccc_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_broadcast_ccc_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_broadcast_ccc_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_direct_ccc_test extends i3c_base_test;
  `uvm_component_utils(i3c_direct_ccc_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_direct_ccc_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_direct_ccc_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_direct_ccc_write_test extends i3c_base_test;
  `uvm_component_utils(i3c_direct_ccc_write_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_direct_ccc_write_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_direct_ccc_write_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_entdaa_test extends i3c_base_test;
  `uvm_component_utils(i3c_entdaa_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_entdaa_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_entdaa_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_ibi_no_payload_test extends i3c_base_test;
  `uvm_component_utils(i3c_ibi_no_payload_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_ibi_no_payload_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_ibi_no_payload_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_ibi_payload_test extends i3c_base_test;
  `uvm_component_utils(i3c_ibi_payload_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_ibi_payload_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_ibi_payload_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_irq_access_test extends i3c_base_test;
  `uvm_component_utils(i3c_irq_access_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_irq_access_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_irq_access_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_sw_reset_test extends i3c_base_test;
  `uvm_component_utils(i3c_sw_reset_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_sw_reset_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_sw_reset_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

class i3c_polling_access_test extends i3c_base_test;
  `uvm_component_utils(i3c_polling_access_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    i3c_polling_access_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_polling_access_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass
