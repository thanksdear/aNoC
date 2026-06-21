class axi_lite_slave_base_test extends uvm_test;
  `uvm_component_utils(axi_lite_slave_base_test)

  virtual axi_lite_slave_if vif;
  axi_lite_slave_env        env;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_lite_slave_if)::get(this, "", "vif", vif))
      `uvm_fatal("TEST", "test 拿不到 vif")
    env = axi_lite_slave_env::type_id::create("env", this);    // 现在只造一个 env
  endfunction

  // 看一眼新树形(可选, 很爽)
  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    print();                                         // 打印 test 往下的组件树
    uvm_top.print_topology();

  endfunction

  task run_phase(uvm_phase phase);
    axi_lite_slave_seq seq;
    phase.raise_objection(this);
    vif.rst_n = 0;
    repeat (2) @(posedge vif.clk);
    vif.rst_n = 1;
    @(posedge vif.clk);

    seq = axi_lite_slave_seq::type_id::create("seq");
    seq.start(env.agt.sqr);          // ← 唯一变的路径:经 env.agt 找 sequencer
    repeat (3) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass