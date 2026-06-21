typedef enum bit {WR, RD} op_e;
// ===== 1. transaction:一笔"要做的事"的数据包(object 体系)=====
class axi_lite_slave_txn extends uvm_sequence_item;
  rand op_e       op;
  rand bit [7:0]  addr; 
  rand bit [31:0] data;                  // 要写的数据, rand = 可被随机
  rand bit [3:0]  strb;

  //—— 时序旋钮：握手的"随机"在这儿 ——
  rand int unsigned  start_delay;
  constraint c_addr { addr[1:0] == 2'b00;
                      addr inside {[0:8'h3f]}; }
  constraint c_delay{ start_delay inside{[0:4]};}

  `uvm_object_utils_begin(axi_lite_slave_txn)
  	`uvm_field_enum(op_e, op, UVM_ALL_ON)
    `uvm_field_int(addr, UVM_ALL_ON)    // 注册字段 → 白送 print/copy/compare
    `uvm_field_int(data, UVM_ALL_ON)    // 注册字段 → 白送 print/copy/compare
    `uvm_field_int(strb, UVM_ALL_ON)    // 注册字段 → 白送 print/copy/compare
    `uvm_field_int(start_delay, UVM_ALL_ON)    // 注册字段 → 白送 print/copy/compare
  `uvm_object_utils_end

  function new(string name = "axi_lite_slave_txn");
    super.new(name);
  endfunction
endclass    