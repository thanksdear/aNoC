class i3c_agent extends uvm_agent;          // uvm_agent 自带 is_active, 默认 UVM_ACTIVE
  `uvm_component_utils(i3c_agent)

  uvm_sequencer #(i3c_txn) sqr;
  i3c_driver               drv;
  i3c_monitor              mon;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = i3c_monitor::type_id::create("mon", this);    // monitor 永远建(主被动都要观察)
    if (is_active == UVM_ACTIVE) begin                   // 只有 active 才建驱动侧
      sqr = uvm_sequencer#(i3c_txn)::type_id::create("sqr", this);
      drv = i3c_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (is_active == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);    // 驱动侧握手接线(从 test 搬来)
  endfunction
endclass