// ===== env:把 agent + scoreboard + cov 集成 =====
class i3c_env extends uvm_env;
  `uvm_component_utils(i3c_env)

  i3c_agent agt;
  i3c_target_model tgt;
  i3c_sb    sb;
  i3c_coverage cov;

  i3c_bus_agent      bus_agt;
  i3c_bus_scoreboard bus_sb;

  function new(string name, uvm_component parent); 
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agt = i3c_agent::type_id::create("agt", this);
    tgt = i3c_target_model::type_id::create("tgt", this);
    sb  = i3c_sb::type_id::create("sb", this);
    cov = i3c_coverage::type_id::create("cov",this);

    bus_agt = i3c_bus_agent::type_id::create("bus_agt", this);
    bus_sb = i3c_bus_scoreboard::type_id::create("bus_sb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agt.mon.ap.connect(sb.ain);    // monitor 广播 → scoreboard 接收(从 test 搬来)
    agt.mon.ap.connect(cov.analysis_export);
    
    agt.mon.ap.connect(bus_sb.apb_fifo.analysis_export);
    bus_agt.mon.ap.connect(bus_sb.bus_fifo.analysis_export);
  endfunction
  
  function void end_of_elaboration_phase(uvm_phase phase);
      // 2. 检查所有 analysis_port 和 imp 之间的连接（如果有端口没连上，会报 WARNING/ERROR）
    super.end_of_elaboration_phase(phase);
    agt.mon.ap.debug_connected_to();
    bus_agt.mon.ap.debug_connected_to();
  endfunction
endclass    
