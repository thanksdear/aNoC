class i3c_bus_agent extends uvm_agent;          // uvm_agent 自带 is_active, 默认 UVM_ACTIVE
  `uvm_component_utils(i3c_bus_agent)

  i3c_bus_monitor              mon;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = i3c_bus_monitor::type_id::create("mon", this);    // monitor 永远建(主被动都要观察)
  endfunction
endclass