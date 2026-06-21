// Code your testbench here
// or browse Examples
`include "uvm_macros.svh"
import uvm_pkg::*;

interface axi_lite_slave_if (input logic clk);
    logic rst_n;
    logic [7:0] awaddr;logic awvalid;logic awready;
    logic [31:0] wdata;logic [3:0] wstrb;logic wvalid;logic wready;
    logic [1:0] bresp;logic bvalid;logic bready;
    logic [7:0] araddr;logic arvalid;logic arready;
    logic [31:0] rdata;logic [1:0] rresp;logic rvalid;logic rready;
  // 驱动视角:我驱动的是 output, 我观察的是 input
  clocking drv_cb @(posedge clk);
    default input #1step output #0;
    output awaddr, awvalid, wdata, wstrb, wvalid, bready, araddr, arvalid, rready;
    input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid;
  endclocking

  // 监视视角:全是 input(只看不驱动)
  clocking mon_cb @(posedge clk);
    default input #1step;
    input awaddr, awvalid, awready, wdata, wstrb, wvalid, wready, bresp, bvalid, bready,
          araddr, arvalid, arready, rdata, rresp, rvalid, rready;
  endclocking

  modport DRV (clocking drv_cb, output rst_n);   // 给 driver 的方向打包
  modport MON (clocking mon_cb);                  // 给 monitor 的方向打包
endinterface

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
    
// ===== 2. sequence:造一串 transaction 的"剧本"(也是 object,跑在自己线程里)=====
class axi_lite_slave_seq extends uvm_sequence #(axi_lite_slave_txn);
  `uvm_object_utils(axi_lite_slave_seq)
  function new(string name = "axi_lite_slave_seq"); super.new(name); endfunction

  task body();
    repeat(16)begin
      axi_lite_slave_txn tr = axi_lite_slave_txn::type_id::create("tr");
      start_item(tr);               // 握手①:申请通道, 阻塞等 driver 来要
      assert(tr.randomize() with {op == WR;}); // 拿到通道后再随机填 data
      finish_item(tr);                  // 握手②:交付, 阻塞等 driver 说"处理完了"
      `uvm_info("SEQ", $sformatf("WRITE 0x%08h", tr.data), UVM_MEDIUM)
    end
    repeat (16) begin
      axi_lite_slave_txn tr = axi_lite_slave_txn::type_id::create("tr");
      start_item(tr);               // 握手①:申请通道, 阻塞等 driver 来要
      assert(tr.randomize() with {op == RD;}); // 拿到通道后再随机填 data
      finish_item(tr);                  // 握手②:交付, 阻塞等 driver 说"处理完了"
      `uvm_info("SEQ", "READ",UVM_MEDIUM)
    end
  endtask
endclass

// ===== 3. driver:拿 transaction, 翻译成线上电平(component 体系)=====
class axi_lite_slave_driver extends uvm_driver #(axi_lite_slave_txn);
  `uvm_component_utils(axi_lite_slave_driver)
  virtual axi_lite_slave_if vif;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_lite_slave_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "driver 拿不到 vif")
  endfunction

  task run_phase(uvm_phase phase);
    @(vif.drv_cb);                 // 等第一个时钟事件后, 才能通过 cb 驱动
    vif.drv_cb.awaddr   <= 0;
    vif.drv_cb.awvalid  <= 0;
    vif.drv_cb.wdata    <= 0;
    vif.drv_cb.wstrb    <= 0;
    vif.drv_cb.wvalid   <= 0;
    vif.drv_cb.bready   <= 0;
    vif.drv_cb.araddr   <= 0;
    vif.drv_cb.arvalid  <= 0;
    vif.drv_cb.rready   <= 0;
    forever begin
      axi_lite_slave_txn tr;
      seq_item_port.get_next_item(tr);  // 握手③:跟 sequencer 要一笔, 没有就阻塞
      drive(tr);
      seq_item_port.item_done();        // 握手④:回执"这笔搞定", 放 sequence 走
    end
  endtask

  task axi_write(axi_lite_slave_txn tr);
      vif.drv_cb.awaddr <= tr.addr; vif.drv_cb.awvalid <= 1;
      do@(vif.drv_cb);while(!vif.drv_cb.awready);   // 等 AW 握手完成
      vif.drv_cb.awvalid <= 0;
      repeat(tr.start_delay)@(vif.drv_cb);           // 延迟 5 拍再发 W
      vif.drv_cb.wdata <= tr.data; vif.drv_cb.wstrb <= tr.strb; vif.drv_cb.wvalid <= 1;
      vif.drv_cb.bready <= 1;
      do@(vif.drv_cb);while(!vif.drv_cb.wready);    // 等 W 握手完成
      vif.drv_cb.wvalid <= 0;
      do@(vif.drv_cb);while(!vif.drv_cb.bvalid);    // 等 B 响应
      vif.drv_cb.bready <= 0;
  endtask

  task axi_read(axi_lite_slave_txn tr);
      vif.drv_cb.araddr <= tr.addr;vif.drv_cb.arvalid <= 1;
      vif.drv_cb.rready <= 1;
      do@(vif.drv_cb);while (!vif.drv_cb.arready);
      vif.drv_cb.arvalid <= 0;
      do@(vif.drv_cb);while (!vif.drv_cb.rvalid);
      vif.drv_cb.rready <= 0;
  endtask

  task drive(axi_lite_slave_txn tr);
      @(vif.drv_cb);
      if(tr.op === WR)begin
        axi_write(tr);
      end else begin
        axi_read(tr);
      end
    endtask
endclass

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
    cp_delay:coverpoint tr.start_delay{
      bins b2b = {0};
      bins light = {[1:2]};
      bins heavy = {[3:$]};
    }
  x_op_data:cross cp_op,cp_data;
  x_op_delay:cross cp_op,cp_delay;
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
      if(written[idx])begin
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
    
class axi_lite_slave_agent extends uvm_agent;          // uvm_agent 自带 is_active, 默认 UVM_ACTIVE
  `uvm_component_utils(axi_lite_slave_agent)

  uvm_sequencer #(axi_lite_slave_txn) sqr;
  axi_lite_slave_driver               drv;
  axi_lite_slave_monitor              mon;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = axi_lite_slave_monitor::type_id::create("mon", this);    // monitor 永远建(主被动都要观察)
    if (is_active == UVM_ACTIVE) begin                   // 只有 active 才建驱动侧
      sqr = uvm_sequencer#(axi_lite_slave_txn)::type_id::create("sqr", this);
      drv = axi_lite_slave_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (is_active == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);    // 驱动侧握手接线(从 test 搬来)
  endfunction
endclass

// ===== env:把 agent + scoreboard 集成 =====
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

    
class axi_lite_slave_base_test extends uvm_test;
  `uvm_component_utils(axi_lite_slave_base_test)

  virtual axi_lite_slave_if vif;
  axi_lite_slave_env        env;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_lite_slave_if)::get(this, "", "vif", vif))
      `uvm_fatal("TEST", "test 拿不到 vif")
    env = axi_lite_slave_env::type_id::create("env", this);    // 现在只造一个 env
  endfunction

  // 看一眼新树形(可选, 很爽)
  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    print();                                         // 打印 test 往下的组件树
    uvm_top.print_topology();

  endfunction

  task run_phase(uvm_phase phase);
    axi_lite_slave_seq seq;
    phase.raise_objection(this);
    vif.rst_n = 0;
    repeat (2) @(posedge vif.clk);
    vif.rst_n = 1;
    @(posedge vif.clk);

    seq = axi_lite_slave_seq::type_id::create("seq");
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
//    $fsdbDumpfile("axi_lite_slave.fsdb");   // 起名: 文件
//    $fsdbDumpvars(0, top);        // ★ 录信号: 是 DumpVARS, 不是 DumpFILE ★
  end

  axi_lite_slave_if vif (clk);
  axi_lite_slave dut(
    .clk(clk),.rst_n(vif.rst_n),
    .awaddr(vif.awaddr),.awvalid(vif.awvalid),.awready(vif.awready),
    .wdata(vif.wdata), .wstrb(vif.wstrb),.wvalid(vif.wvalid),.wready(vif.wready),
    .bresp(vif.bresp),.bvalid(vif.bvalid),.bready(vif.bready),    
    .araddr(vif.araddr),.arvalid(vif.arvalid),.arready(vif.arready),
    .rdata(vif.rdata),.rresp(vif.rresp),.rvalid(vif.rvalid),.rready(vif.rready)
  );
  initial begin
    uvm_config_db#(virtual axi_lite_slave_if)::set(null, "*", "vif", vif);
    run_test("axi_lite_slave_base_test");
  end
endmodule