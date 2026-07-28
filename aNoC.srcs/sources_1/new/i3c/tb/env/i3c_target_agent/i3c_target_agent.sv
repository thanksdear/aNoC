class i3c_target_agent extends uvm_agent;
  `uvm_component_utils(i3c_target_agent)

  uvm_sequencer #(i3c_target_txn) sqr;
  i3c_target_driver               drv;
  i3c_target_cfg                  cfg;

  // Preserve the environment-facing intent API.  The driver owns the
  // electrical behavior; the agent forwards its independent response plans.
  uvm_analysis_port #(i3c_target_intent) intent_ap;
  uvm_analysis_port #(i3c_ibi_intent)    ibi_intent_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    intent_ap = new("intent_ap", this);
    ibi_intent_ap = new("ibi_intent_ap", this);
    //优先使用testbench中配置的cfg，如果没有配置，则使用默认的cfg
    if (!uvm_config_db#(i3c_target_cfg)::get(this, "", "cfg", cfg))
      cfg = i3c_target_cfg::type_id::create("cfg");
    is_active = cfg.is_active;

    if (is_active == UVM_ACTIVE) begin
      sqr = uvm_sequencer#(i3c_target_txn)::type_id::create("sqr", this);
      uvm_config_db#(i3c_target_cfg)::set(this, "drv", "cfg", cfg);
      drv = i3c_target_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (is_active == UVM_ACTIVE) begin
      drv.seq_item_port.connect(sqr.seq_item_export);
      drv.intent_ap.connect(intent_ap);
      drv.ibi_intent_ap.connect(ibi_intent_ap);
    end
  endfunction
endclass
