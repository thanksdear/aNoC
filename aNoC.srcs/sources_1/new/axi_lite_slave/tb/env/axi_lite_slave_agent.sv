class axi_lite_slave_agent extends uvm_agent;          // uvm_agent 自带 is_active, 默认 UVM_ACTIVE
  `uvm_component_utils(axi_lite_slave_agent)

  uvm_sequencer #(axi_lite_slave_txn) sqr;
  axi_lite_slave_driver               drv;
  axi_lite_slave_monitor              mon;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = axi_lite_slave_monitor::type_id::create("mon", this);    // monitor 永远建(主被动都要观察)
    if (is_active == UVM_ACTIVE) begin                   // 只有 active 才建驱动侧
      sqr = uvm_sequencer#(axi_lite_slave_txn)::type_id::create("sqr", this);
      drv = axi_lite_slave_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (is_active == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);    // 驱动侧握手接线(从 test 搬来)
  endfunction
endclass