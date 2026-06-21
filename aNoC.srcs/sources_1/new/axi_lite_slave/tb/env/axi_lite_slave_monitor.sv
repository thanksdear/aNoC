class axi_lite_slave_monitor extends uvm_monitor;
  `uvm_component_utils(axi_lite_slave_monitor)
  
  virtual axi_lite_slave_if vif;
  uvm_analysis_port#(axi_lite_slave_txn) ap;
  
  function new(string name,uvm_component parent);
    super.new(name,parent);
    ap = new("ap",this);
  endfunction
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_lite_slave_if)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "monitor 拿不到 vif")
  endfunction
  
  task run_phase(uvm_phase phase);
  	fork
      watch_writes();
      watch_reads();
    join_none 
  endtask
    
task watch_writes();
    axi_lite_slave_txn tr = axi_lite_slave_txn::type_id::create("wr_obs");
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.awvalid && vif.mon_cb.awready ) begin
        tr.op = WR;
        tr.addr = vif.mon_cb.awaddr;
        `uvm_info("MON", $sformatf("OBSERVE Write addr=0x%08h", tr.addr), UVM_MEDIUM)
      end
      if (vif.mon_cb.wvalid && vif.mon_cb.wready ) begin
        tr.data = vif.mon_cb.wdata;tr.strb = vif.mon_cb.wstrb;
        `uvm_info("MON", $sformatf("OBSERVE Write data=0x%08h", tr.data), UVM_MEDIUM)
      end
      if (vif.mon_cb.bvalid && vif.mon_cb.bready ) begin
        `uvm_info("MON", $sformatf("OBSERVE Write OVER"), UVM_MEDIUM)
        ap.write(tr);
        tr = axi_lite_slave_txn::type_id::create("wr_obs");
      end
    end
  endtask

  task watch_reads();
    axi_lite_slave_txn tr = axi_lite_slave_txn::type_id::create("rd_obs");
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.arready&&vif.mon_cb.arvalid) begin
        tr.op = RD;tr.addr = vif.mon_cb.araddr;
        `uvm_info("MON", $sformatf("OBSERVE Read addr=0x%08h", tr.addr), UVM_MEDIUM)
      end
      if (vif.mon_cb.rready && vif.mon_cb.rvalid )begin
        tr.data = vif.mon_cb.rdata;
        `uvm_info("MON", $sformatf("OBSERVE Read addr=0x%08h", tr.addr), UVM_MEDIUM)
        ap.write(tr);
        tr = axi_lite_slave_txn::type_id::create("rd_obs");
      end
    end
  endtask
endclass