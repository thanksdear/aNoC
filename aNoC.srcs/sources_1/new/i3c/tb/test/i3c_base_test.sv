class i3c_base_test extends uvm_test;
  `uvm_component_utils(i3c_base_test)

  virtual i3c_if vif;
  i3c_env        env;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual i3c_if)::get(this, "", "vif", vif))
      `uvm_fatal("TEST", "test 拿不到 vif")
    env = i3c_env::type_id::create("env", this);    // 现在只造一个 env
  endfunction

  // 看一眼新树形
  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    print();                                         // 打印 test 往下的组件树

  endfunction

  task reset_dut();
    vif.rst_n = 0;
    repeat (5) @(posedge vif.clk);
    vif.rst_n = 1;
    repeat (2) @(posedge vif.clk);
  endtask

  virtual task run_i3c_seq(uvm_sequence #(i3c_txn) seq);
    seq.start(env.agt.sqr);
  endtask

  task run_phase(uvm_phase phase);
    i3c_seq seq;
    phase.raise_objection(this);
    reset_dut();
    seq = i3c_seq::type_id::create("seq");
    run_i3c_seq(seq);
    repeat (20) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass
