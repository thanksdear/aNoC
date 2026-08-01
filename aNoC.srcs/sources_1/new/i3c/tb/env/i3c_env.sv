// ===== env:把 agent + scoreboard + cov 集成 =====
class i3c_env extends uvm_env;
  `uvm_component_utils(i3c_env)

  i3c_agent agt;
  i3c_target_agent tgt;
  i3c_coverage cov;
  virtual i3c_if vif;

  i3c_reg_block     ral;
  i3c_reg_adapter   ral_adapter;
  i3c_reg_apb_filter ral_filter;
  uvm_reg_predictor #(i3c_txn) ral_predictor;

  i3c_bus_agent      bus_agt;
  i3c_virtual_sequencer vseqr;
  i3c_cmd_predictor  predictor;
  i3c_bus_scoreboard bus_sb;
  i3c_bus_coverage   bus_cov;

  function new(string name, uvm_component parent); 
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual i3c_if)::get(this, "", "vif", vif))
      `uvm_fatal("ENV", "cannot get vif")

    ral = i3c_reg_block::type_id::create("ral");
    ral.build();
    ral.lock_model();
    ral.reset("HARD");
    ral_adapter =
      i3c_reg_adapter::type_id::create("ral_adapter");
    ral_filter =
      i3c_reg_apb_filter::type_id::create("ral_filter", this);
    ral_predictor =
      new("ral_predictor", this);

    agt = i3c_agent::type_id::create("agt", this);
    tgt = i3c_target_agent::type_id::create("tgt", this);
    cov = i3c_coverage::type_id::create("cov",this);

    bus_agt = i3c_bus_agent::type_id::create("bus_agt", this);
    vseqr = i3c_virtual_sequencer::type_id::create("vseqr", this);
    predictor = i3c_cmd_predictor::type_id::create("predictor", this);
    bus_sb = i3c_bus_scoreboard::type_id::create("bus_sb", this);
    bus_cov = i3c_bus_coverage::type_id::create("bus_cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agt.mon.ap.connect(cov.analysis_export);

    // RAL frontdoor traffic uses the active APB agent.  The APB monitor, not
    // the initiating sequence, updates the mirror so direct APB accesses and
    // RAL accesses share one prediction path.
    ral.default_map.set_sequencer(agt.sqr, ral_adapter);
    ral.default_map.set_auto_predict(0);
    ral_predictor.map = ral.default_map;
    ral_predictor.adapter = ral_adapter;
    agt.mon.ap.connect(ral_filter.bus_in);
    ral_filter.csr_ap.connect(ral_predictor.bus_in);
    
    // APB programming and the independent target response plan are combined
    // by the predictor before the passive bus result is compared.
    agt.mon.ap.connect(predictor.apb_fifo.analysis_export);
    tgt.intent_ap.connect(predictor.target_fifo.analysis_export);
    predictor.expected_ap.connect(bus_sb.expected_fifo.analysis_export);

    // IBI is target-initiated, so its independent plan bypasses the APB
    // command predictor and enters a dedicated scoreboard FIFO.
    tgt.ibi_intent_ap.connect(bus_sb.ibi_intent_fifo.analysis_export);

    // The protocol scoreboard also observes APB RX/CTRL accesses.
    agt.mon.ap.connect(bus_sb.apb_fifo.analysis_export);
    bus_agt.mon.ap.connect(bus_sb.bus_fifo.analysis_export);
    bus_agt.mon.ap.connect(bus_cov.analysis_export);

    // Virtual sequences coordinate the two active agents through typed
    // sequencer handles; no sequence needs to configure its peer through vif.
    vseqr.apb_sqr = agt.sqr;
    vseqr.target_sqr = tgt.sqr;
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(negedge vif.rst_n);
      ral.reset("HARD");
    end
  endtask
  
  function void end_of_elaboration_phase(uvm_phase phase);
      // 2. 检查所有 analysis_port 和 imp 之间的连接（如果有端口没连上，会报 WARNING/ERROR）
    super.end_of_elaboration_phase(phase);
    agt.mon.ap.debug_connected_to();
    bus_agt.mon.ap.debug_connected_to();
  endfunction
endclass    
