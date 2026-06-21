// ===== env:把 agent + scoreboard + cov 集成 =====
class axi_lite_slave_env extends uvm_env;
  `uvm_component_utils(axi_lite_slave_env)

  axi_lite_slave_agent agt;
  axi_lite_slave_sb    sb;
  axi_lite_slave_coverage cov;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agt = axi_lite_slave_agent::type_id::create("agt", this);
    sb  = axi_lite_slave_sb::type_id::create("sb", this);
    cov = axi_lite_slave_coverage::type_id::create("cov",this);
  endfunction

  function void connect_phase(uvm_phase phase);
    agt.mon.ap.connect(sb.ain);    // monitor 广播 → scoreboard 接收(从 test 搬来)
    agt.mon.ap.connect(cov.analysis_export);
  endfunction
  
  function void end_of_elaboration_phase(uvm_phase phase);
      // 2. 检查所有 analysis_port 和 imp 之间的连接（如果有端口没连上，会报 WARNING/ERROR）
    super.end_of_elaboration_phase(phase);
    agt.mon.ap.debug_connected_to();
  endfunction
endclass    