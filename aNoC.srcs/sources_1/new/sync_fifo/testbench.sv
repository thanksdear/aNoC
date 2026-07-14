// Code your testbench here
// or browse Examples
`include "uvm_macros.svh"
import uvm_pkg::*;

interface fifo_if (input logic clk);
  logic       rst_n;
  logic       wr_en;
  logic [7:0] wr_data;
  logic       rd_en;
  logic [7:0] rd_data;
  logic       full;
  logic       empty;

  // 驱动视角:我驱动的是 output, 我观察的是 input
  clocking drv_cb @(posedge clk);
    default input #1step output #0;
    output wr_en, wr_data, rd_en;
    input  full, empty, rd_data;
  endclocking

  // 监视视角:全是 input(只看不驱动)
  clocking mon_cb @(posedge clk);
    default input #1step;
    input wr_en, wr_data, rd_en, rd_data, full, empty;
  endclocking

  modport DRV (clocking drv_cb, output rst_n);   // 给 driver 的方向打包
  modport MON (clocking mon_cb);                  // 给 monitor 的方向打包
endinterface

typedef enum bit {WR, RD} op_e;
// ===== 1. transaction:一笔"要做的事"的数据包(object 体系)=====
class fifo_txn extends uvm_sequence_item;
  rand op_e      op;
  rand bit [7:0] data;                  // 要写的数据, rand = 可被随机
  bit       full;
  bit       empty;
  `uvm_object_utils_begin(fifo_txn)
  	`uvm_field_enum(op_e, op, UVM_ALL_ON)
    `uvm_field_int(data, UVM_ALL_ON)    // 注册字段 → 白送 print/copy/compare
    `uvm_field_int(full, UVM_ALL_ON)    // 注册字段 → 白送 print/copy/compare
    `uvm_field_int(empty, UVM_ALL_ON)    // 注册字段 → 白送 print/copy/compare
  `uvm_object_utils_end

  function new(string name = "fifo_txn");
    super.new(name);
  endfunction
endclass    
    
// ===== 2. sequence:造一串 transaction 的"剧本"(也是 object,跑在自己线程里)=====
class fifo_seq extends uvm_sequence #(fifo_txn);
  `uvm_object_utils(fifo_seq)
  function new(string name = "fifo_seq"); super.new(name); endfunction

  task body();
    bit [7:0] wr_vals[] = '{8'h00, 8'hFF, 8'h3A, 8'h7F, 8'h80};  // 含两个角点
    foreach (wr_vals[i]) begin
      fifo_txn tr = fifo_txn::type_id::create("tr");
      start_item(tr);
      tr.op   = WR;
      tr.data = wr_vals[i];        // 直接指定, 不随机
      finish_item(tr);
      `uvm_info("SEQ", $sformatf("WRITE 0x%02h", tr.data), UVM_MEDIUM)
    end
    repeat (5) begin
      fifo_txn tr = fifo_txn::type_id::create("tr");
      start_item(tr);               // 握手①:申请通道, 阻塞等 driver 来要
      assert(tr.randomize() with {op == RD;}); // 拿到通道后再随机填 data
      finish_item(tr);                  // 握手②:交付, 阻塞等 driver 说"处理完了"
      `uvm_info("SEQ", "READ",UVM_MEDIUM)
    end
  endtask
endclass

// ===== 3. driver:拿 transaction, 翻译成线上电平(component 体系)=====
class fifo_driver extends uvm_driver #(fifo_txn);
  `uvm_component_utils(fifo_driver)
  virtual fifo_if vif;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "driver 拿不到 vif")
  endfunction

  task run_phase(uvm_phase phase);
    @(vif.drv_cb);                 // 等第一个时钟事件后, 才能通过 cb 驱动
    vif.drv_cb.wr_en   <= 0;
    vif.drv_cb.rd_en   <= 0;
    vif.drv_cb.wr_data <= '0;
    forever begin
      fifo_txn tr;
      seq_item_port.get_next_item(tr);  // 握手③:跟 sequencer 要一笔, 没有就阻塞
      drive(tr);
      seq_item_port.item_done();        // 握手④:回执"这笔搞定", 放 sequence 走
    end
  endtask

  task drive(fifo_txn tr);
      @(vif.drv_cb);
      if (tr.op == WR) begin
        vif.drv_cb.wr_en   <= 1;
        vif.drv_cb.wr_data <= tr.data;
        @(vif.drv_cb);
        vif.drv_cb.wr_en   <= 0;
      end else begin
        vif.drv_cb.rd_en <= 1;
        @(vif.drv_cb);
        vif.drv_cb.rd_en <= 0;
      end
    endtask
endclass

class fifo_coverage	extends uvm_subscriber #(fifo_txn);
  `uvm_component_utils(fifo_coverage)
  
  covergroup cg with function sample(op_e op ,bit [7:0] data,bit full ,bit empty);
  	cp_op:	coverpoint	op;
    cp_data:coverpoint	data{
      bins zero = {8'h00};
      bins low = {[8'h01:8'h7F]};
      bins high = {[8'h80:8'hFE]};
      bins allone = {8'hff};
    }
	cp_full:coverpoint full;  
	cp_empty:coverpoint empty;
    x_op_data:cross cp_op,cp_data;
	
	x_overflow:cross cp_op ,cp_full{
		bins write_when_full = binsof(cp_op) intersect {WR} &&
							   binsof(cp_full) intersect {1};
	}
	
	x_underflow:cross cp_op ,cp_empty{
		bins read_when_empty = binsof(cp_op) intersect {RD} &&
							   binsof(cp_empty) intersect {1};
	}
  endgroup
  
  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg = new();                             // covergroup 在构造里实例化
  endfunction
  
  function void write(fifo_txn t);
    cg.sample(t.op, t.data,t.full,t.empty);                // 采样: 把这笔的 op/data 喂进各 coverpoint
  endfunction
  
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("COV", $sformatf("功能覆盖率: %0.1f%%", cg.get_coverage()), UVM_LOW)
  endfunction
endclass
    
class fifo_monitor extends uvm_monitor;
  `uvm_component_utils(fifo_monitor)
  
  virtual fifo_if vif;
  uvm_analysis_port#(fifo_txn) ap;
  
  function new(string name,uvm_component parent);
    super.new(name,parent);
    ap=new("ap",this);
  endfunction
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "monitor 拿不到 vif")
  endfunction
  
  task run_phase(uvm_phase phase);
  	fork
      watch_writes();
      watch_reads();
    join_none 
  endtask
    
task watch_writes();
    forever begin
      @(vif.mon_cb);
      if (vif.rst_n && vif.mon_cb.wr_en ) begin
        fifo_txn tr = fifo_txn::type_id::create("wr_obs");
        tr.data = vif.mon_cb.wr_data;
        tr.op   = WR;
        tr.full = vif.mon_cb.full;
        tr.empty = vif.mon_cb.empty;		
        `uvm_info("MON", $sformatf("OBSERVE Write data=0x%02h", tr.data), UVM_MEDIUM)
        ap.write(tr);
      end
    end
  endtask

  task watch_reads();
    forever begin
      @(vif.mon_cb);
      if (vif.rst_n && vif.mon_cb.rd_en ) begin
        fifo_txn tr = fifo_txn::type_id::create("rd_obs");
        tr.data = vif.mon_cb.rd_data;
        tr.op   = RD;
        tr.full = vif.mon_cb.full;
        tr.empty = vif.mon_cb.empty;
        `uvm_info("MON", $sformatf("OBSERVE Read data=0x%02h", tr.data), UVM_MEDIUM)
        ap.write(tr);
      end
    end
  endtask
endclass

class fifo_sb extends uvm_scoreboard;
  `uvm_component_utils(fifo_sb)
  
  uvm_analysis_imp #(fifo_txn,fifo_sb) ain;
  bit [7:0] ref_q[$];
  int n_pass ,n_fail;
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ain = new("ain", this);    // imp 在构造里建好, 绑到 this(我来实现 write)
  endfunction
  
  function void write(fifo_txn tr);
    if(tr.op == WR) begin	
      ref_q.push_back(tr.data); // 入队
      `uvm_info("SB",$sformatf("INQUENE 0x%02h (deep=%0d)",tr.data,ref_q.size()),UVM_MEDIUM)
    end
    else begin
      if(ref_q.size()==0)begin
        `uvm_error("SB",$sformatf("0x%02h,error",tr.data))
        n_fail++;
      end
      else begin
        bit [7:0] exp = ref_q.pop_front();
        if(tr.data===exp) begin
          `uvm_info("SB",$sformatf("0x%02h == 0x%02h match",tr.data,exp),UVM_MEDIUM)
          n_pass++;
        end
        else begin
          `uvm_error("SB",$sformatf("0x%02h != 0x%02h match",tr.data,exp))
          n_fail++;
        end
      end
    end
  endfunction
  
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SB",$sformatf("finish: pass %0d, fail %0d, remain %0d",n_pass, n_fail, ref_q.size()),UVM_MEDIUM)
  endfunction
endclass    
    
class fifo_agent extends uvm_agent;          // uvm_agent 自带 is_active, 默认 UVM_ACTIVE
  `uvm_component_utils(fifo_agent)

  uvm_sequencer #(fifo_txn) sqr;
  fifo_driver               drv;
  fifo_monitor              mon;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = fifo_monitor::type_id::create("mon", this);    // monitor 永远建(主被动都要观察)
    if (is_active == UVM_ACTIVE) begin                   // 只有 active 才建驱动侧
      sqr = uvm_sequencer#(fifo_txn)::type_id::create("sqr", this);
      drv = fifo_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (is_active == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);    // 驱动侧握手接线(从 test 搬来)
  endfunction
endclass

// ===== env:把 agent + scoreboard 集成 =====
class fifo_env extends uvm_env;
  `uvm_component_utils(fifo_env)

  fifo_agent agt;
  fifo_sb    sb;
  fifo_coverage cov;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agt = fifo_agent::type_id::create("agt", this);
    sb  = fifo_sb::type_id::create("sb", this);
    cov = fifo_coverage::type_id::create("cov",this);
  endfunction

  function void connect_phase(uvm_phase phase);
    agt.mon.ap.connect(sb.ain);    // monitor 广播 → scoreboard 接收(从 test 搬来)
    agt.mon.ap.connect(cov.analysis_export);
  endfunction
endclass    

    
class fifo_base_test extends uvm_test;
  `uvm_component_utils(fifo_base_test)

  virtual fifo_if vif;
  fifo_env        env;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
      `uvm_fatal("TEST", "test 拿不到 vif")
    env = fifo_env::type_id::create("env", this);    // 现在只造一个 env
  endfunction

  // 看一眼新树形(可选, 很爽)
  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    print();                                         // 打印 test 往下的组件树
  endfunction

  task run_phase(uvm_phase phase);
    fifo_seq seq;
    phase.raise_objection(this);
    vif.rst_n = 0;
    repeat (2) @(posedge vif.clk);
    vif.rst_n = 1;
    @(posedge vif.clk);

    seq = fifo_seq::type_id::create("seq");
    seq.start(env.agt.sqr);          // ← 唯一变的路径:经 env.agt 找 sequencer
    repeat (3) @(posedge vif.clk);
    phase.drop_objection(this);
  endtask
endclass

// ---------- top (不变) ----------
module top;
  logic clk = 0;
  always #5 clk = ~clk;
  initial begin
    $fsdbDumpfile("fifo.fsdb");   // 起名: 文件
    $fsdbDumpvars(0, top);        // ★ 录信号: 是 DumpVARS, 不是 DumpFILE ★
  end

  fifo_if vif (clk);
  sync_fifo #(.WIDTH(8), .DEPTH(8)) dut (
    .clk(clk), .rst_n(vif.rst_n),
    .wr_en(vif.wr_en), .wr_data(vif.wr_data),
    .rd_en(vif.rd_en), .rd_data(vif.rd_data),
    .full(vif.full),  .empty(vif.empty)
  );
  initial begin
    uvm_config_db#(virtual fifo_if)::set(null, "*", "vif", vif);
    run_test("fifo_base_test");
  end
endmodule