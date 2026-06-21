class axi_lite_slave_sb extends uvm_scoreboard;
  `uvm_component_utils(axi_lite_slave_sb)
  
  uvm_analysis_imp #(axi_lite_slave_txn,axi_lite_slave_sb) ain;
  bit [31:0] ref_q[16];
  bit        written[16];
  int n_pass ,n_fail;
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ain = new("ain", this);    // imp 在构造里建好, 绑到 this(我来实现 write)
  endfunction
  
  function void write(axi_lite_slave_txn tr);
    int idx = tr.addr[5:2];
    if(tr.op == WR) begin
      for(int i=0;i<4;i++)begin
        if(tr.strb[i]) begin
          ref_q[idx][i*8 +: 8] = tr.data[i*8 +: 8];
          `uvm_info("SB",$sformatf("WRITE 0x%08h to addr 0x%08h",tr.data[(i+1)*8-1 -: 8],tr.addr+i),UVM_MEDIUM)
        end
      end
      written[idx] = 1;	
    end
    else begin
      if(!written[idx]) return;
      begin
        bit [31:0] exp = ref_q[idx];
        if(tr.data===exp) begin
          `uvm_info("SB",$sformatf("0x%08h == 0x%08h match",tr.data,exp),UVM_MEDIUM)
          n_pass++;
        end
        else begin
          `uvm_error("SB",$sformatf("0x%08h != 0x%08h match",tr.data,exp))
          n_fail++;
        end
      end
    end
  endfunction
  
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SB",$sformatf("finish: pass %0d, fail %0d",n_pass, n_fail),UVM_MEDIUM)
  endfunction
endclass    