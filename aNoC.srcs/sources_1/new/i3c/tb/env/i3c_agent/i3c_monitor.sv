class i3c_monitor extends uvm_monitor;
  	`uvm_component_utils(i3c_monitor)
  
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
  
	task run_phase(uvm_phase phase);
	    forever begin
	      @(vif.mon_cb);
	      if (vif.mon_cb.psel && vif.mon_cb.penable && vif.mon_cb.pready) begin
	        i3c_txn tr = i3c_txn::type_id::create("apb_obs");
	        tr.addr = vif.mon_cb.paddr[7:0];
	        tr.strb = vif.mon_cb.pstrb;
	        if (vif.mon_cb.pwrite) begin
	          tr.op = WR;
	          tr.data = vif.mon_cb.pwdata;
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
endclass
