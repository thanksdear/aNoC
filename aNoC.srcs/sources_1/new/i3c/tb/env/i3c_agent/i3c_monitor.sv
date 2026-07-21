class i3c_monitor extends uvm_monitor;
  	`uvm_component_utils(i3c_monitor)

    localparam bit [7:0] REG_CTRL = 8'h08;
  
  	virtual i3c_if vif;
  	uvm_analysis_port#(i3c_txn) ap;
  
  	function new(string name,uvm_component parent);
    	super.new(name,parent);
    	ap = new("ap",this);
  	endfunction
  
  	function void build_phase(uvm_phase phase);
    	super.build_phase(phase);
    	if (!uvm_config_db#(virtual i3c_if)::get(this, "", "vif", vif))
      	`uvm_fatal("MON", "cannot get vif")
  	endfunction
  
	task observe_apb();
	    forever begin
	      @(vif.mon_cb);
	      if (vif.mon_cb.psel && vif.mon_cb.penable && vif.mon_cb.pready) begin
	        i3c_txn tr = i3c_txn::type_id::create("apb_obs");
	        tr.addr = vif.mon_cb.paddr[7:0];
	        tr.strb = vif.mon_cb.pstrb;
	        if (vif.mon_cb.pwrite) begin
	          tr.op = WR;
	          tr.data = vif.mon_cb.pwdata;
	          // Advance the shared epoch before analysis subscribers see the
	          // reset write.  This gives reset priority even when predictor and
	          // bus-scoreboard FIFO consumers run in different delta cycles.
	          if ((tr.addr == REG_CTRL) && tr.strb[0] && tr.data[2])
	            vif.tb_reset_epoch = vif.tb_reset_epoch + 1;
	          `uvm_info("MON", $sformatf("OBSERVE APB WRITE addr=0x%02h data=0x%08h",
	                                     tr.addr, tr.data), UVM_MEDIUM)
	        end else begin
	          tr.op = RD;
	          tr.data = vif.mon_cb.prdata;
	          `uvm_info("MON", $sformatf("OBSERVE APB READ addr=0x%02h data=0x%08h",
	                                     tr.addr, tr.data), UVM_MEDIUM)
	        end
	        ap.write(tr);
	      end
	    end
	endtask

    task watch_hard_reset_epoch();
      forever begin
        @(negedge vif.rst_n);
        vif.tb_reset_epoch = vif.tb_reset_epoch + 1;
      end
    endtask

    task run_phase(uvm_phase phase);
      fork
        observe_apb();
        watch_hard_reset_epoch();
      join
    endtask
endclass
