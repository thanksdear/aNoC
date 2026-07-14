class axi_lite_slave_coverage	extends uvm_subscriber #(axi_lite_slave_txn);
  `uvm_component_utils(axi_lite_slave_coverage)
  axi_lite_slave_txn tr;
  covergroup cg with function sample();
  	cp_op:	coverpoint	tr.op;
    cp_addr:coverpoint	tr.addr[5:2]{
      bins idx[] = {[0:15]};
    }
    cp_data:coverpoint	(tr.addr > 8'h3f){
      bins in_range = {0};
      bins out_range = {1};
    }
    cp_strb:coverpoint	tr.strb{
      bins none = {4'b0000};
      bins byte0 = {4'b0001};
      bins byte1 = {4'b0010};
      bins byte2 = {4'b0100};
      bins byte3 = {4'b1000};
      bins full = {4'b1111};
      bins others = default;
    }
  x_op_data:cross cp_op,cp_data;
  endgroup
  
  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg = new();                             // covergroup 在构造里实例化
  endfunction
  
  function void write(axi_lite_slave_txn t);
    tr = t;
    cg.sample();                // 采样: 把这笔的 op/data 喂进各 coverpoint
  endfunction
  
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("COV", $sformatf("功能覆盖率: %0.1f%%", cg.get_coverage()), UVM_LOW)
  endfunction
endclass
