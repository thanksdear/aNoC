// =============================================================================
// 本文件阅读指南
// =============================================================================
// 这个文件不只有一个 scoreboard，而是依次放了四类内容：
//
//   1. i3c_sb
//      简单的 APB 寄存器镜像 scoreboard，只检查 BUS_TIMING/CTRL 等 CSR。
//
//   2. i3c_expected_entdaa_round / i3c_expected_op
//      “预期结果”的数据结构。它们描述命令执行后，总线上应该出现什么。
//
//   3. i3c_cmd_predictor
//      预测器。它把 APB monitor 观察到的软件命令，以及 target model 发布的
//      响应计划（是否 ACK、读回哪些数据等）组合成 i3c_expected_op。
//
//   4. i3c_bus_scoreboard
//      I3C 协议 scoreboard。它把 predictor 给出的 expected 与 SCL/SDA bus
//      monitor 给出的 actual 逐项比较，同时检查 RX_PORT 的 APB 读回值。
//
// 最重要的数据流如下：
//
//   APB monitor --i3c_txn--+--> i3c_cmd_predictor
//                           |           +
//   target model --intent--+           +--i3c_expected_op--> expected_fifo --+
//                                                                          |
//   SCL/SDA bus monitor --------i3c_bus_txn-----------> bus_fifo -----------+--> 比较
//
// 连接语句不在本文件，而在 i3c_env::connect_phase() 中：
//
//   agt.mon.ap       -> predictor.apb_fifo       // APB 实际访问
//   tgt.intent_ap    -> predictor.target_fifo    // target 的独立响应计划
//   predictor.expected_ap -> bus_sb.expected_fifo// 预测出的总线行为
//   bus_agt.mon.ap   -> bus_sb.bus_fifo          // SCL/SDA 上的实际总线行为
//   agt.mon.ap       -> bus_sb.apb_fifo          // CTRL/RX_PORT 的实际访问
//   tgt.ibi_intent_ap-> bus_sb.ibi_intent_fifo   // target 主动发起的 IBI 计划
//
// 学习普通 private write 时，建议只按下面顺序阅读：
//   process_apb() -> decode_command() -> process_command()
//   -> expected_ap.write() -> process_bus() -> compare_private()
// CCC、ENTDAA、IBI 分支可以等 private read/write 看懂后再读。
// =============================================================================

// -----------------------------------------------------------------------------
// APB 寄存器 scoreboard
// -----------------------------------------------------------------------------
// 这个类只负责少量 CSR 的“写入后读回”检查，不检查 SCL/SDA 协议。
// 它的输入来自 APB monitor：agt.mon.ap -> sb.ain。
// 因为 ain 是 uvm_analysis_imp，monitor 每次 ap.write(tr) 时会直接回调本类的
// write(tr)，这里不需要再建立 FIFO 或在 run_phase 中 get()。
class i3c_sb extends uvm_scoreboard;
  `uvm_component_utils(i3c_sb)

  localparam bit [7:0] REG_BUS_TIMING_0 = 8'h00;
  localparam bit [7:0] REG_BUS_TIMING_1 = 8'h04;
  localparam bit [7:0] REG_CTRL         = 8'h08;

  virtual i3c_if vif;

  // APB monitor 的接收入口。收到的 i3c_txn 表示一次已经完成的 APB 读/写。
  uvm_analysis_imp #(i3c_txn, i3c_sb) ain;

  // CSR 参考模型。地址按 32-bit 字索引，所以使用 addr[5:2] 访问。
  bit [31:0] ref_q[16];
  // 标记某个槽位是否已有有效参考值，避免拿未建模寄存器进行比较。
  bit        written[16];
  // 这里只统计 APB 寄存器读回比较的结果，不是整个测试的 UVM 错误总数。
  int        n_pass;
  int        n_fail;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ain = new("ain", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual i3c_if)::get(this, "", "vif", vif))
      `uvm_fatal("SB", "cannot get vif")
    reset_model();
  endfunction

  // 将软件参考模型恢复到 DUT 的硬复位默认值。
  // 注意：这只是清空/重建 scoreboard 内部模型，不会驱动 DUT 复位。
  function void reset_model();
    for (int i = 0; i < 16; i++) begin
      ref_q[i]  = '0;
      written[i] = 1'b0;
    end

    // 必须与 RTL csr_regs 的硬复位默认值保持一致。
    ref_q[REG_BUS_TIMING_0[5:2]] = {16'd6, 16'd6};
    ref_q[REG_BUS_TIMING_1[5:2]] = 32'd2;
    ref_q[REG_CTRL[5:2]]         = 32'h0000_0001;
    written[REG_BUS_TIMING_0[5:2]] = 1'b1;
    written[REG_BUS_TIMING_1[5:2]] = 1'b1;
    written[REG_CTRL[5:2]]         = 1'b1;
  endfunction

  // 被动监听硬复位边沿。检测到 rst_n 下降后，重新初始化 CSR 参考模型。
  task run_phase(uvm_phase phase);
    forever begin
      @(negedge vif.rst_n);
      reset_model();
    end
  endtask

  // 当前只镜像三个可稳定读回的配置寄存器；FIFO/状态寄存器由其他逻辑检查。
  function bit is_mirror_reg(bit [7:0] addr);
    return (addr == REG_BUS_TIMING_0) ||
           (addr == REG_BUS_TIMING_1) ||
           (addr == REG_CTRL);
  endfunction

  // 某些 CSR 只有部分位可读或有意义，因此读比较前必须使用掩码。
  // 掩码为 0 的位既不判对，也不判错。
  function bit [31:0] read_mask(bit [7:0] addr);
    case (addr)
      REG_BUS_TIMING_0: return 32'hffff_ffff;
      REG_BUS_TIMING_1: return 32'h0000_ffff;
      REG_CTRL:         return 32'h0000_001f;
      default:          return 32'h0000_0000;
    endcase
  endfunction

  // uvm_analysis_imp 的回调函数：APB monitor 广播一笔事务时自动进入这里。
  // 写操作更新参考模型；读操作将 DUT 读回值与参考模型进行带掩码比较。
  function void write(i3c_txn tr);
    int        idx;
    bit [31:0] mask;
    bit [31:0] exp;

    if (!is_mirror_reg(tr.addr))
      return;

    // APB 地址按字节编址，而每个 CSR 占 4 byte，所以去掉低两位。
    idx = tr.addr[5:2];
    if (tr.op == WR) begin
      // pstrb 的每一位控制一个 byte，只更新本次真正写入的 byte lane。
      for (int i = 0; i < 4; i++) begin
        if (tr.strb[i]) begin
          ref_q[idx][i*8 +: 8] = tr.data[i*8 +: 8];
          `uvm_info(
            "SB",
            $sformatf(
              "WRITE 0x%02h to addr 0x%02h",
              tr.data[i*8 +: 8],
              tr.addr + i
            ),
            UVM_MEDIUM
          )
        end
      end

      // CTRL.sw_rst 是自清零脉冲。软件即使写入 1，之后读回也应为 0，
      // 所以参考模型不能长期保存写入的 1。
      if (tr.addr == REG_CTRL)
        ref_q[idx][2] = 1'b0;
      written[idx] = 1'b1;
    end
    else begin
      // 尚未建模的寄存器不在这个简单 scoreboard 中比较。
      if (!written[idx])
        return;

      exp  = ref_q[idx];
      mask = read_mask(tr.addr);
      if ((tr.data & mask) === (exp & mask)) begin
        `uvm_info(
          "SB",
          $sformatf(
            "addr 0x%02h: 0x%08h == 0x%08h mask 0x%08h match",
            tr.addr,
            tr.data,
            exp,
            mask
          ),
          UVM_MEDIUM
        )
        n_pass++;
      end
      else begin
        `uvm_error(
          "SB",
          $sformatf(
            "addr 0x%02h: 0x%08h != 0x%08h mask 0x%08h",
            tr.addr,
            tr.data,
            exp,
            mask
          )
        )
        n_fail++;
      end
    end
  endfunction

  // 仿真结束时汇总本类做过的 CSR 读回比较次数。
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(
      "SB",
      $sformatf("finish: pass %0d, fail %0d", n_pass, n_fail),
      UVM_MEDIUM
    )
  endfunction
endclass


// -----------------------------------------------------------------------------
// 一轮成功 ENTDAA 仲裁的“预期结果”
// -----------------------------------------------------------------------------
// ENTDAA 可能包含多轮 7E/R + 64-bit 身份信息 + 动态地址分配，因此每个成功
// target 使用一个 round 对象表示。最后用于确认“已经没有 target”的 7E/R NACK
// 不会分配地址，不属于成功 round，而由 i3c_expected_op 中的
// expect_entdaa_final_nack 单独表示。
class i3c_expected_entdaa_round extends uvm_object;
  // 该轮 7E/R 地址头是否应该得到 target ACK。
  logic        expect_header_ack;
  // target 在仲裁阶段发送的 64-bit PID/BCR/DCR 组合身份字段。
  logic [63:0] id;
  // controller 本轮准备分配给 target 的 7-bit 动态地址。
  logic [6:0]  assigned_da;
  // target 是否应该接受该动态地址。
  logic        expect_da_ack;

  `uvm_object_utils_begin(i3c_expected_entdaa_round)
    `uvm_field_int(expect_header_ack, UVM_ALL_ON)
    `uvm_field_int(id, UVM_ALL_ON)
    `uvm_field_int(assigned_da, UVM_ALL_ON)
    `uvm_field_int(expect_da_ack, UVM_ALL_ON)
  `uvm_object_utils_end

  // 成功 ENTDAA round 的常用默认值是“7E/R 被 ACK、分配的 DA 也被 ACK”；
  // id 和 assigned_da 随后由 bind_entdaa_intent() 按 target plan 填入。
  function new(string name = "i3c_expected_entdaa_round");
    super.new(name);
    expect_header_ack = 1'b1;
    expect_da_ack     = 1'b1;
  endfunction
endclass


// -----------------------------------------------------------------------------
// 一条 APB 命令对应的完整“预期总线操作”
// -----------------------------------------------------------------------------
// 这个对象不是 bus monitor 观察出来的 actual，而是 predictor 根据两类独立信息
// 生成的 expected：
//   1. APB monitor 看到的 CMD_PORT/TX_PORT/CTRL 写入；
//   2. target model 预先发布的 ACK、读数据、ENTDAA 等响应计划。
//
// 每条命令需要发送/接收的数据都绑定在自己的对象中，而不是比较时再去读取全局
// FIFO。这样复位、连续命令或 CCC 插入时，不会让前一条命令误拿后一条命令的数据。
class i3c_expected_op extends uvm_sequence_item;
  // 命令类型：private、broadcast CCC、direct CCC 或 ENTDAA。
  i3c_bus_kind_e kind;
  // predictor 分配的递增编号，仅用于日志定位同一条命令。
  int unsigned   command_id;
  // 命令创建时的复位代次，用来识别复位前遗留的过期 expected。
  int unsigned   reset_epoch;

  // 以下字段直接从 CTRL/CMD_PORT 的 APB 编程内容解码得到：
  //   i3c_mode <- predictor 对 CTRL[0] 的镜像
  //   addr      <- CMD_PORT data[23:17]
  //   rw        <- CMD_PORT data[16]
  //   length    <- CMD_PORT data[31:24]
  //   ccc_code  <- CMD_PORT data[15:8]
  logic          i3c_mode;
  logic [6:0]    addr;
  logic          rw;
  logic [7:0]    length;
  logic [7:0]    ccc_code;

  // 以下字段来自 target model 的响应计划，而不是来自被测总线。
  // broadcast ACK 是 7E/W 广播地址阶段的响应。
  logic          expect_bcast_ack;
  // target ACK 是 private 地址，或 direct CCC repeated START 后目标地址的响应。
  logic          expect_target_ack;
  // 保存 target plan 声明的地址和方向，便于 predictor 检查计划是否配错。
  logic [6:0]    target_model_addr;
  logic          target_model_direction;
  // legacy I2C 写方向下，target 计划连续 ACK 多少个数据 byte。
  int unsigned   target_write_ack_count;
  // I3C 读方向下，target 实际计划提供多少个数据 byte。
  int unsigned   target_read_length;

  // predictor 是否成功为本命令取齐全部 TX 数据；复位打断时会变为 0。
  bit            tx_model_complete;
  // legacy I2C 写是否预期在最后一个已发送 byte 后收到数据 NACK。
  logic          expect_i2c_data_nack;
  // 应在总线上出现的写/读 payload。名称中的 expected 由所属对象语义体现。
  logic [7:0]    write_data[$];
  logic [7:0]    read_data[$];

  // ENTDAA 成功轮次，以及所有 target 都完成后最后一次 7E/R NACK。
  i3c_expected_entdaa_round entdaa_rounds[$];
  logic                     expect_entdaa_final_nack;

  `uvm_object_utils_begin(i3c_expected_op)
    `uvm_field_enum(i3c_bus_kind_e, kind, UVM_ALL_ON)
    `uvm_field_int(command_id, UVM_ALL_ON)
    `uvm_field_int(reset_epoch, UVM_ALL_ON)
    `uvm_field_int(i3c_mode, UVM_ALL_ON)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_int(rw, UVM_ALL_ON)
    `uvm_field_int(length, UVM_ALL_ON)
    `uvm_field_int(ccc_code, UVM_ALL_ON)
    `uvm_field_int(expect_bcast_ack, UVM_ALL_ON)
    `uvm_field_int(expect_target_ack, UVM_ALL_ON)
    `uvm_field_int(target_model_addr, UVM_ALL_ON)
    `uvm_field_int(target_model_direction, UVM_ALL_ON)
    `uvm_field_int(target_write_ack_count, UVM_ALL_ON)
    `uvm_field_int(target_read_length, UVM_ALL_ON)
    `uvm_field_int(tx_model_complete, UVM_ALL_ON)
    `uvm_field_int(expect_i2c_data_nack, UVM_ALL_ON)
    `uvm_field_queue_int(write_data, UVM_ALL_ON)
    `uvm_field_queue_int(read_data, UVM_ALL_ON)
    `uvm_field_queue_object(entdaa_rounds, UVM_ALL_ON)
    `uvm_field_int(expect_entdaa_final_nack, UVM_ALL_ON)
  `uvm_object_utils_end

  // 构造时只给安全默认值；地址、长度、payload 和 ACK 由 decode/bind 流程补全。
  function new(string name = "i3c_expected_op");
    super.new(name);
    kind                   = I3C_KIND_UNKNOWN;
    i3c_mode               = 1'b1;
    expect_bcast_ack       = 1'b0;
    expect_target_ack      = 1'b0;
    target_model_addr      = 'x;
    target_model_direction = 1'bx;
    target_write_ack_count = 0;
    target_read_length     = 0;
    tx_model_complete      = 1'b1;
    expect_i2c_data_nack   = 1'b0;
    expect_entdaa_final_nack = 1'b0;
  endfunction
endclass


// -----------------------------------------------------------------------------
// 命令预测器：把“软件编程”转换成“预期总线行为”
// -----------------------------------------------------------------------------
// predictor 不采样 SCL/SDA，也不判断 DUT 对错。它只根据与 DUT 输出相互独立的
// 输入建立 expected：
//
//   apb_fifo    <- APB monitor：CTRL、TX_PORT、CMD_PORT 等实际 APB 访问
//   target_fifo <- target model：该 target 计划 ACK/NACK、发送哪些读数据
//   expected_ap -> bus scoreboard.expected_fifo：拼装完成的 expected
//
// command_fifo 是 predictor 内部的解耦队列：process_apb() 快速解析 CMD_PORT，
// process_commands() 再等待 target intent 和 TX 数据。这样 APB monitor 的输入消费
// 不会被一条尚未满足条件的 I3C 命令长期阻塞。
class i3c_cmd_predictor extends uvm_component;
  `uvm_component_utils(i3c_cmd_predictor)

  localparam bit [7:0] REG_CTRL  = 8'h08;
  localparam bit [7:0] CMD_PORT  = 8'h20;
  localparam bit [7:0] TX_PORT   = 8'h28;
  localparam bit [7:0] CCC_ENTDAA = 8'h07;

  virtual i3c_if vif;

  // 外部输入 1：APB monitor 广播的已完成 APB transaction。
  uvm_tlm_analysis_fifo #(i3c_txn)           apb_fifo;
  // 外部输入 2：target model 发布的独立响应计划。
  uvm_tlm_analysis_fifo #(i3c_target_intent) target_fifo;
  // 内部队列：已从 CMD_PORT 解码，但尚未绑定 target/TX 数据的命令。
  uvm_tlm_fifo          #(i3c_expected_op)    command_fifo;
  // 外部输出：完整 expected，由 env 连接到 bus_sb.expected_fifo。
  uvm_analysis_port      #(i3c_expected_op)   expected_ap;

  // APB 写 TX_PORT 时建立的软件侧 TX FIFO 镜像。
  logic [7:0]  tx_fifo_model[$];
  // CTRL.i3c_mode 的软件参考值，用于决定第九位应按 I3C 还是 I2C 解释。
  logic        i3c_mode_model;
  // 仅用于日志追踪的命令编号。
  int unsigned next_command_id;
  // 每次 TX 队列变化或事务状态清空时递增，用来唤醒等待 TX 数据的任务。
  int unsigned tx_change_seq;
  // 尚未完成的 process_command() 数量，check_phase 用它发现悬空预测任务。
  int           active_command_count;

  // 这里只创建 FIFO/port，本组件与 monitor/scoreboard 的实际接线在 env 的
  // connect_phase() 中完成。command_fifo 的 size=0 表示无界 FIFO，不是零容量。
  function new(string name, uvm_component parent);
    super.new(name, parent);
    apb_fifo    = new("apb_fifo", this);
    target_fifo = new("target_fifo", this);
    command_fifo = new("command_fifo", this, 0);
    expected_ap = new("expected_ap", this);
    next_command_id = 0;
    tx_change_seq = 0;
    active_command_count = 0;
  endfunction

  // predictor 从 vif 读取 reset、tb_reset_epoch 等同步信息，但不会用它采样
  // SCL/SDA 作为 expected。总线实际值只允许由 bus monitor 送往 scoreboard。
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual i3c_if)::get(this, "", "vif", vif))
      `uvm_fatal("I3C_PRED", "cannot get vif")
    hard_reset_model();
  endfunction

  // 清除“传输级”状态。
  // 软复位和硬复位都会调用；i3c_mode 是否恢复默认值由调用者决定。
  function void flush_transactions();
    tx_fifo_model.delete();
    target_fifo.flush();
    command_fifo.flush();
    tx_change_seq++;
  endfunction

  // 硬复位除了丢弃未完成事务，还要把 CTRL 模式模型恢复为 I3C 默认值。
  function void hard_reset_model();
    flush_transactions();
    i3c_mode_model = 1'b1;
  endfunction

  // 监听 DUT 硬复位。apb_fifo 也要清空，避免复位前已经广播、但尚未消费的
  // APB transaction 在复位后重新生成 expected。
  task watch_hard_reset();
    forever begin
      @(negedge vif.rst_n);
      hard_reset_model();
      apb_fifo.flush();
    end
  endtask

  // 将一次 CMD_PORT 写入解码为 expected 的“命令骨架”。
  // 此时只填 APB 命令本身能确定的字段；ACK 和 payload 稍后再绑定。
  function i3c_expected_op decode_command(i3c_txn apb_tr);
    i3c_expected_op expected;

    expected = i3c_expected_op::type_id::create(
      $sformatf("expected_op_%0d", next_command_id)
    );
    expected.command_id = next_command_id++;
    expected.reset_epoch = vif.tb_reset_epoch;
    expected.i3c_mode = i3c_mode_model;
    expected.addr     = apb_tr.data[23:17];
    expected.rw       = apb_tr.data[16];
    expected.length   = apb_tr.data[31:24];
    expected.ccc_code = apb_tr.data[15:8];

    // CMD_PORT 编码约定：bit[1] 区分 private/CCC；CCC 中 bit[0] 区分
    // broadcast/direct；ENTDAA 再由 CCC code 0x07 单独识别。
    if (!apb_tr.data[1])
      expected.kind = I3C_KIND_PRIVATE;
    else if (apb_tr.data[15:8] == CCC_ENTDAA)
      expected.kind = I3C_KIND_ENTDAA;
    else if (apb_tr.data[0])
      expected.kind = I3C_KIND_DIRECT_CCC;
    else
      expected.kind = I3C_KIND_BROADCAST_CCC;

    return expected;
  endfunction

  // 等待本命令对应的一条 target intent，但同时监听复位。
  // 如果直接使用 target_fifo.get()，测试在等待 target plan 时发生复位，旧命令
  // 可能永远阻塞，甚至在复位后误吃下一条命令的 intent，因此这里采用二选一等待。
  task get_target_intent_or_reset(
    input  longint unsigned command_epoch,
    output i3c_target_intent intent,
    output bit               got_intent,
    output bit               reset_seen
  );
    intent      = null;
    got_intent  = 1'b0;
    reset_seen  = 1'b0;

    if ((vif.rst_n !== 1'b1) ||
        (vif.tb_reset_epoch != command_epoch)) begin
      reset_seen = 1'b1;
      return;
    end

    fork : GET_INTENT_OR_RESET
      begin
        target_fifo.get(intent);
        got_intent = 1'b1;
      end
      begin
        wait ((vif.rst_n !== 1'b1) ||
              (vif.tb_reset_epoch != command_epoch));
        reset_seen = 1'b1;
      end
    join_any
    disable GET_INTENT_OR_RESET;

    // 若 intent 到达与复位发生在同一个仿真时隙，明确规定“复位优先”。
    // 这样复位前的命令绝不会继续产生可比较的 expected。
    if ((vif.rst_n !== 1'b1) ||
        (vif.tb_reset_epoch != command_epoch)) begin
      intent     = null;
      got_intent = 1'b0;
      reset_seen = 1'b1;
    end
  endtask

  // 把 target model 的响应计划写入 expected。
  // is_broadcast=1 表示当前 intent 对应 7E/W 广播阶段；否则对应真正目标地址。
  // i3c_expected_op 是 class handle，因此这里即使没有 output 形参，也是在原地
  // 修改调用者持有的同一个 expected 对象。
  function void apply_target_intent(
    i3c_expected_op  expected,
    i3c_target_intent intent,
    bit              is_broadcast
  );
    logic effective_ack;

    // 非广播访问时，只有 plan 地址与命令地址一致，计划的 ACK 才有效。
    // 地址对不上时强制按 NACK 预测，避免一个配错地址的 target plan 蒙混过关。
    effective_ack = intent.expect_ack;
    if (!is_broadcast && (expected.addr !== intent.expected_addr))
      effective_ack = 1'b0;

    if (is_broadcast) begin
      expected.expect_bcast_ack = effective_ack;
    end
    else begin
      expected.expect_target_ack      = effective_ack;
      expected.target_model_addr      = intent.expected_addr;
      expected.target_model_direction = intent.direction;
      expected.target_write_ack_count = intent.write_ack_count;
      if (effective_ack && (intent.direction !== expected.rw))
        `uvm_error(
          "I3C_PRED",
          $sformatf(
            "cmd[%0d] target direction plan=%0b differs from command rw=%0b",
            expected.command_id,
            intent.direction,
            expected.rw
          )
        )
    end
  endfunction

  // 为写命令绑定预期 payload。
  // 数据来源不是总线 monitor，而是此前 APB 写 TX_PORT 建立的 tx_fifo_model。
  // reaches_data=0（地址 NACK）、读命令或 ENTDAA 都不应消费 TX FIFO。
  task bind_write_data(
    i3c_expected_op expected,
    bit             reaches_data,
    output bit      reset_seen
  );
    int unsigned write_length;
    int unsigned wake_seq;

    reset_seen = 1'b0;

    if (!reaches_data || expected.rw || expected.kind == I3C_KIND_ENTDAA)
      return;

    write_length = expected.length;
    // legacy I2C 每个写数据 byte 后都由 target 给 ACK/NACK。
    // 如果 target 计划 ACK 的数量小于命令 length，controller 仍会发送下一个
    // byte，然后在它的第九位收到 NACK 并停止，因此预期发送数量是 ACK 数+1。
    if ((expected.kind == I3C_KIND_PRIVATE) && !expected.i3c_mode &&
        (expected.target_write_ack_count < expected.length)) begin
      write_length = expected.target_write_ack_count + 1;
      expected.expect_i2c_data_nack = 1'b1;
    end

    for (int i = 0; i < write_length; i++) begin
      // 允许测试先下 CMD、稍后再补 TX_PORT 数据，因此队列为空时等待。
      // 等待条件包含 reset 和 tx_change_seq，既不会忙等，也能在复位时退出。
      while (tx_fifo_model.size() == 0) begin
        if ((vif.rst_n !== 1'b1) ||
            (vif.tb_reset_epoch != expected.reset_epoch)) begin
          expected.tx_model_complete = 1'b0;
          reset_seen = 1'b1;
          return;
        end

        wake_seq = tx_change_seq;
        wait ((tx_change_seq != wake_seq) ||
              (vif.rst_n !== 1'b1) ||
              (vif.tb_reset_epoch != expected.reset_epoch));
      end

      // 被唤醒后、真正 pop 前再次检查 reset epoch，防止旧命令消费复位后新写入的
      // TX 数据。这是处理并发 delta-cycle/复位竞争的保护。
      if ((vif.rst_n !== 1'b1) ||
          (vif.tb_reset_epoch != expected.reset_epoch)) begin
        expected.tx_model_complete = 1'b0;
        reset_seen = 1'b1;
        return;
      end
      expected.write_data.push_back(tx_fifo_model.pop_front());
    end
  endtask

  // 为读命令绑定 target 计划发送的数据。
  // 读数据来自 target intent.read_data，而不是从 actual 总线上复制；否则 expected
  // 与 actual 同源，会造成“无论 DUT 发什么都比较通过”的自证问题。
  function void bind_read_data(
    i3c_expected_op   expected,
    i3c_target_intent intent,
    bit               reaches_data
  );
    int unsigned expected_read_length;

    if (!reaches_data || !expected.rw)
      return;

    expected.target_read_length = intent.read_length;
    if (intent.read_data.size() != intent.read_length)
      `uvm_error(
        "I3C_PRED",
        $sformatf(
          "cmd[%0d] target read plan length=%0d but carries %0d byte(s)",
          expected.command_id,
          intent.read_length,
          intent.read_data.size()
        )
      )

    // I3C SDR read 可由任意一方先结束：target 用 T-bit 表示没有更多数据，
    // controller 也可达到命令 length 后结束。因此取二者较短者。
    // legacy I2C 没有 target 驱动的 I3C T-bit，长度由 controller 命令控制。
    if (expected.i3c_mode && (intent.read_length < expected.length))
      expected_read_length = intent.read_length;
    else
      expected_read_length = expected.length;

    if (expected_read_length > intent.read_data.size()) begin
      `uvm_error(
        "I3C_PRED",
        $sformatf(
          "cmd[%0d] needs %0d predicted read byte(s), target supplied %0d",
          expected.command_id,
          expected_read_length,
          intent.read_data.size()
        )
      )
      expected_read_length = intent.read_data.size();
    end

    for (int i = 0; i < expected_read_length; i++)
      expected.read_data.push_back(intent.read_data[i]);
  endfunction

  // 将 ENTDAA target plan 转换为一轮预期仲裁记录。
  function void bind_entdaa_intent(
    i3c_expected_op   expected,
    i3c_target_intent intent
  );
    i3c_expected_entdaa_round round;

    // 7E/W + ENTDAA code 被 ACK 后，controller 会用 repeated START 发 7E/R。
    // 若 target 不参与，就没有成功仲裁轮，只出现最终用于结束搜索的 header NACK。
    expected.expect_entdaa_final_nack = 1'b1;
    if (!intent.entdaa_participate)
      return;

    round = i3c_expected_entdaa_round::type_id::create(
      $sformatf("expected_entdaa_round_%0d", expected.entdaa_rounds.size())
    );
    round.expect_header_ack = 1'b1;
    round.id                = intent.entdaa_id;
    round.assigned_da       = intent.entdaa_expected_da;
    round.expect_da_ack     = intent.entdaa_expect_da_ack;
    expected.entdaa_rounds.push_back(round);

    // 动态地址 DA 被 NACK 属于异常终止，此路径不会再继续发下一轮 7E/R 探测，
    // 因而也不应期待正常流程末尾的 final NACK。
    if (!round.expect_da_ack)
      expected.expect_entdaa_final_nack = 1'b0;
  endfunction

  // 补全并发布一条 expected。
  // 输入 expected 是 decode_command() 产生的命令骨架；本任务依命令类型取得一条
  // 或两条 target intent，绑定 ACK/TX/RX/ENTDAA 信息，最后 expected_ap.write()。
  // intent 也按 FIFO 顺序配对，并不会按地址回头搜索，所以测试发布计划的顺序必须
  // 与 controller 命令实际执行顺序一致。
  task process_command(i3c_expected_op expected);
    i3c_target_intent first_intent;
    i3c_target_intent second_intent;
    bit got_intent;
    bit reset_seen;
    bit reaches_data;

    active_command_count++;
    begin : PROCESS_BODY
      get_target_intent_or_reset(
        expected.reset_epoch, first_intent, got_intent, reset_seen
      );
      if (reset_seen || !got_intent)
        disable PROCESS_BODY;

      case (expected.kind)
        I3C_KIND_PRIVATE: begin
          // Private：只有一个目标地址阶段，所以消费一条 PRIVATE intent。
          if (first_intent.kind != TARGET_INTENT_PRIVATE)
            `uvm_error(
              "I3C_PRED",
              $sformatf(
                "cmd[%0d] expected private target intent, got %s",
                expected.command_id,
                first_intent.kind.name()
              )
            )
          apply_target_intent(expected, first_intent, 1'b0);
          reaches_data = expected.expect_target_ack;
          bind_write_data(expected, reaches_data, reset_seen);
          if (reset_seen)
            disable PROCESS_BODY;
          bind_read_data(expected, first_intent, reaches_data);
        end

        I3C_KIND_BROADCAST_CCC: begin
          // Broadcast CCC：7E/W 地址阶段消费一条 CCC_BCAST intent；ACK 后才会
          // 发送 CCC code 和可选 payload。
          if (first_intent.kind != TARGET_INTENT_CCC_BCAST)
            `uvm_error(
              "I3C_PRED",
              $sformatf(
                "cmd[%0d] expected CCC broadcast intent, got %s",
                expected.command_id,
                first_intent.kind.name()
              )
            )
          apply_target_intent(expected, first_intent, 1'b1);
          reaches_data = expected.expect_bcast_ack;
          bind_write_data(expected, reaches_data, reset_seen);
          if (reset_seen)
            disable PROCESS_BODY;
        end

        I3C_KIND_ENTDAA: begin
          // ENTDAA 先经过广播 7E/W 阶段。若广播被 ACK，再消费第二条 ENTDAA
          // intent 来预测 7E/R 仲裁、64-bit ID 和动态地址分配。
          if (first_intent.kind != TARGET_INTENT_CCC_BCAST)
            `uvm_error(
              "I3C_PRED",
              $sformatf(
                "cmd[%0d] expected ENTDAA broadcast intent, got %s",
                expected.command_id,
                first_intent.kind.name()
              )
            )
          apply_target_intent(expected, first_intent, 1'b1);

          if (expected.expect_bcast_ack) begin
            get_target_intent_or_reset(
              expected.reset_epoch, second_intent, got_intent, reset_seen
            );
            if (reset_seen || !got_intent)
              disable PROCESS_BODY;
            if (second_intent.kind != TARGET_INTENT_ENTDAA)
              `uvm_error(
                "I3C_PRED",
                $sformatf(
                  "cmd[%0d] expected ENTDAA target intent, got %s",
                  expected.command_id,
                  second_intent.kind.name()
                )
              )
            bind_entdaa_intent(expected, second_intent);
          end
        end

        I3C_KIND_DIRECT_CCC: begin
          // Direct CCC 有两个地址阶段：
          //   START + 7E/W + CCC code + repeated START + target address。
          // 因此先消费广播 intent；广播 ACK 后再消费 direct target intent。
          if (first_intent.kind != TARGET_INTENT_CCC_BCAST)
            `uvm_error(
              "I3C_PRED",
              $sformatf(
                "cmd[%0d] expected first direct-CCC intent to be broadcast, got %s",
                expected.command_id,
                first_intent.kind.name()
              )
            )
          apply_target_intent(expected, first_intent, 1'b1);

          if (expected.expect_bcast_ack) begin
            get_target_intent_or_reset(
              expected.reset_epoch, second_intent, got_intent, reset_seen
            );
            if (reset_seen || !got_intent)
              disable PROCESS_BODY;
            if (second_intent.kind != TARGET_INTENT_CCC_DIRECT)
              `uvm_error(
                "I3C_PRED",
                $sformatf(
                  "cmd[%0d] expected direct target intent, got %s",
                  expected.command_id,
                  second_intent.kind.name()
                )
              )
            apply_target_intent(expected, second_intent, 1'b0);
            reaches_data = expected.expect_target_ack;
            bind_write_data(expected, reaches_data, reset_seen);
            if (reset_seen)
              disable PROCESS_BODY;
            bind_read_data(expected, second_intent, reaches_data);
          end
        end

        default:
          `uvm_error(
            "I3C_PRED",
            $sformatf("cmd[%0d] has unsupported kind", expected.command_id)
          )
      endcase

      // 只有命令仍属于当前 reset epoch 时才发布。复位打断的半条 expected 会被
      // 直接丢弃，避免它与复位后的 actual 错位配对。
      if ((vif.rst_n === 1'b1) &&
          (expected.reset_epoch == vif.tb_reset_epoch))
        expected_ap.write(expected);
    end
    active_command_count--;
  endtask

  // 持续消费 APB monitor 的 transaction，并维护 predictor 的软件侧模型。
  // 这里只做快速分类/入队，不在这里等待 target 响应。
  task process_apb();
    i3c_txn         apb_tr;
    i3c_expected_op expected;

    forever begin
      apb_fifo.get(apb_tr);
      if (vif.rst_n !== 1'b1)
        continue;

      if ((apb_tr.op == WR) && (apb_tr.addr == REG_CTRL) && apb_tr.strb[0]) begin
        // CTRL 配置本身在软件复位语义下保留。先更新 mode，再清传输状态。
        // 这里不能 flush apb_fifo，因为 monitor 可能已经把复位写之后的合法 APB
        // 访问也放入 FIFO；一并清掉会漏预测新命令。
        i3c_mode_model = apb_tr.data[0];
        if (apb_tr.data[2])
          flush_transactions();
      end
      else if ((apb_tr.op == WR) && (apb_tr.addr == TX_PORT) && apb_tr.strb[0]) begin
        // TX_PORT 每次写入一个有效低字节，按软件写入顺序进入参考 TX FIFO。
        tx_fifo_model.push_back(apb_tr.data[7:0]);//这个是队列，用push_back放入，pop_front取出
        tx_change_seq++;
      end
      else if ((apb_tr.op == WR) && (apb_tr.addr == CMD_PORT) &&
               (apb_tr.strb == 4'hf)) begin
        // CMD_PORT 需要完整 4-byte strobe。解码后放入内部 command_fifo，
        // 由 process_commands() 异步等待相应 target intent 和 TX 数据。
        expected = decode_command(apb_tr);
        command_fifo.put(expected);//这个是TLMFIFO，使用PUT放入，GET取出，没有数据等待，flush清空
      end
    end
  endtask

  // 串行取出命令骨架并补全 expected。command_fifo 保证 APB 命令的先后顺序。
  task process_commands();
    i3c_expected_op expected;

    forever begin
      command_fifo.get(expected);
      process_command(expected);
    end
  endtask

  // 三条并行线程分别处理 APB、命令预测和硬复位；它们整个仿真期间持续运行。
  task run_phase(uvm_phase phase);
    fork
      process_apb();
      process_commands();
      watch_hard_reset();
    join
  endtask

  // 仿真收尾检查：任何非空队列都说明有输入没有被消费，通常意味着命令、
  // target plan 或 TX 数据数量/顺序不匹配，而不是可以忽略的普通 INFO。
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (active_command_count != 0)
      `uvm_error(
        "I3C_PRED",
        $sformatf("%0d command prediction task(s) still active", active_command_count)
      )
    if (target_fifo.used() != 0)
      `uvm_error(
        "I3C_PRED",
        $sformatf("%0d unmatched target intent(s) remain", target_fifo.used())
      )
    if (command_fifo.used() != 0)
      `uvm_error(
        "I3C_PRED",
        $sformatf("%0d APB command(s) remain unpredicted", command_fifo.used())
      )
    if (apb_fifo.used() != 0)
      `uvm_error(
        "I3C_PRED",
        $sformatf("%0d APB transaction(s) remain unprocessed", apb_fifo.used())
      )
    if (tx_fifo_model.size() != 0)
      `uvm_error(
        "I3C_PRED",
        $sformatf("%0d unconsumed TX byte(s) remain", tx_fifo_model.size())
      )
  endfunction
endclass


// -----------------------------------------------------------------------------
// I3C 总线协议 scoreboard
// -----------------------------------------------------------------------------
// 这是本文件中真正检查 SCL/SDA 协议的 scoreboard，与前面的 CSR 镜像 i3c_sb
// 是两个不同组件。核心工作是把下面两条独立路径按事务发生顺序一一配对：
//
//   expected_fifo：predictor 根据 APB 命令 + target plan 生成“应该发生什么”
//   bus_fifo     ：bus monitor 根据 SCL/SDA 解码得到“实际发生了什么”
//
// 当前匹配策略是严格 FIFO 顺序，不会按 command_id 在队列中搜索。如果命令、
// target intent 或 monitor transaction 多一条/少一条，后面的事务也可能跟着错位；
// 因此报错时应先处理日志中最早出现的 unmatched/mismatch。
//
// 另外两条旁路用于特殊检查：
//   apb_fifo       ：观察 CTRL 写入和 RX_PORT 读回；
//   ibi_intent_fifo：IBI 由 target 主动发起，没有 APB CMD，直接使用 target plan。
class i3c_bus_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(i3c_bus_scoreboard)

  localparam bit [7:0] REG_CTRL = 8'h08;
  localparam bit [7:0] RX_PORT  = 8'h2c;

  virtual i3c_if vif;

  // 来源：predictor.expected_ap -> expected_fifo.analysis_export
  // 内容：已绑定命令字段、ACK 计划和 payload 的完整预期总线操作。
  // 消费者：process_bus() 在收到 controller-origin actual 后 try_get()。
  uvm_tlm_analysis_fifo #(i3c_expected_op) expected_fifo;

  // 来源：bus_agt.mon.ap -> bus_fifo.analysis_export
  // 内容：SCL/SDA bus monitor 在 STOP/完整事务结束时发布的实际总线事务。
  // 消费者：process_bus() 首先阻塞 get(actual)，再选择对应 expected 路径。
  uvm_tlm_analysis_fifo #(i3c_bus_txn)     bus_fifo;

  // 来源：agt.mon.ap -> apb_fifo.analysis_export
  // 内容：APB monitor 的同一份 transaction 广播副本。
  // 消费者：process_apb()；这里只关心 CTRL 写和 RX_PORT 读，其余地址忽略。
  uvm_tlm_analysis_fifo #(i3c_txn)         apb_fifo;

  // 来源：tgt.ibi_intent_ap -> ibi_intent_fifo.analysis_export
  // 内容：target model 在发起 IBI 前发布的独立计划，并非 monitor 实测值。
  // 消费者：process_bus() 遇到 target-origin actual 时取出并 compare_ibi()。
  uvm_tlm_analysis_fifo #(i3c_ibi_intent)  ibi_intent_fifo;

  // 预期最终进入 DUT RX FIFO、随后应由软件从 RX_PORT 依序读出的 byte。
  // private/direct-CCC read 使用 predictor.read_data 入队；IBI 使用 plan.mdb 入队。
  // 绝不能把 bus monitor 的 actual.data 放进来，否则 RX_PORT 比较会与 actual 同源，
  // DUT 即使在总线和 RX FIFO 上同时犯同样的错也可能被错误判为通过。
  logic [7:0] expected_rx_q[$];

  // CTRL[3] ibi_en 和 CTRL[4] ibi_mdb_en 的轻量软件镜像。
  // 它们不替代 CSR scoreboard，只为解释一笔 IBI 在当前配置下是否合法。
  logic       ibi_en_model;
  logic       ibi_mdb_en_model;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    // analysis FIFO 自带 analysis_export：生产者调用 ap.write() 时，事务会被
    // 缓存在此；scoreboard 可以稍后在自己的 run_phase 线程中 get()/try_get()。
    expected_fifo = new("expected_fifo", this);
    bus_fifo      = new("bus_fifo", this);
    apb_fifo      = new("apb_fifo", this);
    ibi_intent_fifo = new("ibi_intent_fifo", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual i3c_if)::get(this, "", "vif", vif))
      `uvm_fatal("I3C_SB", "cannot get vif")
    hard_reset_model();
  endfunction

  // 清理“当前在途传输”的状态，供软件复位和硬复位共同使用。
  // 故意不在这里清 apb_fifo：软件复位写之后的合法 APB 访问可能已经排在其中，
  // 如果一并 flush，会让 scoreboard 漏掉复位后的新事务。
  function void flush_transactions();
    expected_fifo.flush();
    bus_fifo.flush();
    ibi_intent_fifo.flush();
    expected_rx_q.delete();
  endfunction

  // 硬复位比软件复位更彻底：除传输状态外，还清 APB backlog，并将 CTRL 的
  // IBI 配置镜像恢复为 RTL 硬复位默认值。
  function void hard_reset_model();
    flush_transactions();
    apb_fifo.flush();
    ibi_en_model     = 1'b0;
    ibi_mdb_en_model = 1'b0;
  endfunction

  // 与 process_bus/process_apb 并行运行，监听 rst_n 下降沿并立即复位参考模型。
  task watch_hard_reset();
    forever begin
      @(negedge vif.rst_n);
      hard_reset_model();
    end
  endtask

  // --------------------------- 基础比较工具层 -------------------------------
  // 后续所有协议比较函数最终都调用这些小函数，以统一 UVM_ERROR 格式。

  // 统一报告 actual/expected 字符串，field_name 应包含 segment/data 索引，
  // 便于从第一条错误直接定位到具体协议字段。
  function void report_mismatch(string field_name, string actual, string expected);
    `uvm_error(
      "I3C_SB",
      $sformatf("%s mismatch: actual=%s expected=%s", field_name, actual, expected)
    )
  endfunction

  // 四态逻辑使用 !==：actual 中出现 X/Z 也必须判错，不能被二态比较隐藏。
  function void check_logic(string field_name, logic actual, logic expected);
    if (actual !== expected)
      report_mismatch(
        field_name,
        $sformatf("%b", actual),
        $sformatf("%b", expected)
      );
  endfunction

  // 用于长度、队列大小、bit count 等整数属性。
  function void check_int(string field_name, int actual, int expected);
    if (actual != expected)
      report_mismatch(
        field_name,
        $sformatf("%0d", actual),
        $sformatf("%0d", expected)
      );
  endfunction

  // 用于地址头、CCC code 和 payload byte，同样使用四态 !==。
  function void check_byte(string field_name, logic [7:0] actual,
                           logic [7:0] expected);
    if (actual !== expected)
      report_mismatch(
        field_name,
        $sformatf("0x%02h", actual),
        $sformatf("0x%02h", expected)
      );
  endfunction

  // ENTDAA 的 PID/BCR/DCR 组合身份字段为连续 64 bit，单独提供比较函数。
  function void check_u64(string field_name, logic [63:0] actual,
                          logic [63:0] expected);
    if (actual !== expected)
      report_mismatch(
        field_name,
        $sformatf("0x%016h", actual),
        $sformatf("0x%016h", expected)
      );
  endfunction

  // --------------------------- segment 字段检查层 ----------------------------

  // 检查一个 segment 的 8-bit 地址头和紧随其后的第九位。
  // segment.header 保存原始 {7-bit address, R/W}；addr_ninth 保存总线实际电平。
  // ACK 在线上是低电平 0，所以 expected_ack=1 时，原始期望位必须写成
  // !expected_ack=0。这层只检查 header，不检查后面的 payload。
  function bit check_segment_header(
    i3c_bus_segment segment,
    int             segment_index,
    logic [6:0]     expected_addr,
    logic           expected_rw,
    logic           expected_ack
  );
    logic [7:0] expected_header;

    expected_header = {expected_addr, expected_rw};
    // 半个地址头不能继续按完整事务比较，否则后面的数组索引都没有协议意义。
    if (!segment.header_complete) begin
      `uvm_error(
        "I3C_SB",
        $sformatf("segment[%0d] ended before its address header completed", segment_index)
      )
      return 1'b0;
    end

    check_byte(
      $sformatf("segment[%0d].header", segment_index),
      segment.header,
      expected_header
    );
    check_logic(
      $sformatf("segment[%0d].addr_ninth", segment_index),
      segment.addr_ninth,
      !expected_ack
    );
    return 1'b1;
  endfunction

  // 检查 segment 两端的协议边界。
  // 一笔含 repeated START 的事务会被 monitor 分成多个 segment：第一段通常
  // START->RESTART，下一段 RESTART->STOP；普通 private 传输则 START->STOP。
  function void check_boundaries(
    i3c_bus_segment  segment,
    int              segment_index,
    i3c_bus_boundary_e expected_start,
    i3c_bus_boundary_e expected_end
  );
    if (segment.start_boundary != expected_start)
      report_mismatch(
        $sformatf("segment[%0d].start", segment_index),
        segment.start_boundary.name(),
        expected_start.name()
      );
    if (segment.end_boundary != expected_end)
      report_mismatch(
        $sformatf("segment[%0d].end", segment_index),
        segment.end_boundary.name(),
        expected_end.name()
      );
  endfunction

  // 检查一个“写方向”数据 byte 及其第九位。
  //
  // i3c_parity=1：按 I3C SDR 写处理，第九位由 controller 驱动 parity/T；
  // i3c_parity=0：按 legacy I2C 写处理，第九位由 target 驱动 ACK/NACK，
  //               legacy_expected_ninth 直接给出线上期望电平（ACK=0，NACK=1）。
  //
  // 除 resolved SDA 电平外，本环境还保存 controller_low/target_low 两组 TB 辅助
  // 采样，用于检查“谁在驱动第九位”。它们不是 IP 的物理引脚；若以后构建纯黑盒、
  // 可复用 monitor，应把驱动归属检查与只依赖 SCL/SDA 的协议检查分开。
  function void check_write_byte(
    i3c_bus_segment segment,
    int             segment_index,
    int             data_index,
    logic [7:0]     expected_data,
    bit             i3c_parity,
    logic           legacy_expected_ninth
  );
    logic expected_ninth;
    logic expected_controller_low;
    logic expected_target_low;

    if (data_index >= segment.data.size())
      return;

    check_byte(
      $sformatf("segment[%0d].data[%0d]", segment_index, data_index),
      segment.data[data_index],
      expected_data
    );

    if (data_index >= segment.data_ninth_bits.size()) begin
      `uvm_error(
        "I3C_SB",
        $sformatf("segment[%0d] has no ninth bit for data[%0d]",
                  segment_index, data_index)
      )
      return;
    end

    // I3C 模式用 monitor 采到的实际 byte 计算其应有 parity；数据内容本身已经在
    // 上面的 check_byte() 与 expected_data 独立比较。
    if (i3c_parity)
      expected_ninth = ~^segment.data[data_index];
    else
      expected_ninth = legacy_expected_ninth;
    check_logic(
      $sformatf("segment[%0d].ninth[%0d]", segment_index, data_index),
      segment.data_ninth_bits[data_index],
      expected_ninth
    );

    // 只看 resolved SDA 的 0/1 无法判断是谁拉低：I3C 可能是 controller 的
    // parity/T，legacy I2C 则可能是 target ACK，所以再检查 TB 记录的驱动归属。
    expected_controller_low = i3c_parity && !expected_ninth;
    expected_target_low     = !i3c_parity && !expected_ninth;

    if (data_index >= segment.data_ninth_controller_low.size())
      `uvm_error(
        "I3C_SB",
        $sformatf("segment[%0d] has no controller-drive sample for data[%0d]",
                  segment_index, data_index)
      )
    else
      check_logic(
        $sformatf("segment[%0d].ninth_controller_low[%0d]",
                  segment_index, data_index),
        segment.data_ninth_controller_low[data_index],
        expected_controller_low
      );

    if (data_index >= segment.data_ninth_target_low.size())
      `uvm_error(
        "I3C_SB",
        $sformatf("segment[%0d] has no target-drive sample for data[%0d]",
                  segment_index, data_index)
      )
    else
      check_logic(
        $sformatf("segment[%0d].ninth_target_low[%0d]",
                  segment_index, data_index),
        segment.data_ninth_target_low[data_index],
        expected_target_low
      );
  endfunction

  // 检查一个“读方向”数据 byte 及其第九位。
  // logical_index 是 payload 内索引；data_index 是 segment.data[] 中的实际索引，
  // 两者在前面有 CCC code 等前缀时可能不同。
  function void check_read_byte(
    i3c_bus_segment segment,
    int             segment_index,
    int             data_index,
    int             logical_index,
    int             requested_length,
    int             target_length,
    logic [7:0]     expected_data,
    bit             i3c_mode
  );
    logic expected_ninth;
    logic expected_controller_low;
    logic expected_target_low;

    if (data_index >= segment.data.size())
      return;

    check_byte(
      $sformatf("segment[%0d].data[%0d]", segment_index, data_index),
      segment.data[data_index],
      expected_data
    );

    if (data_index >= segment.data_ninth_bits.size()) begin
      `uvm_error(
        "I3C_SB",
        $sformatf("segment[%0d] has no ninth bit for data[%0d]",
                  segment_index, data_index)
      )
      return;
    end

    if (i3c_mode) begin
      // I3C read 的第九位是 wired-AND 后的 T-bit：controller 达到请求长度末尾
      // 或 target 达到自己计划的数据末尾时，都可以拉低。任意一方拉低，线上
      // resolved T 都为 0。
      expected_controller_low = (logical_index == (requested_length - 1));
      expected_target_low     = (logical_index == (target_length - 1));
      expected_ninth          = !(expected_controller_low || expected_target_low);
    end
    else begin
      // legacy I2C read：controller 对中间 byte 拉低 ACK，最后一个 byte 释放 SDA
      // 形成 NACK；读数据的发送方 target 不驱动这个第九位。
      expected_ninth          = (logical_index == (requested_length - 1));
      expected_controller_low = !expected_ninth;
      expected_target_low     = 1'b0;
    end

    check_logic(
      $sformatf("segment[%0d].ninth[%0d]", segment_index, data_index),
      segment.data_ninth_bits[data_index],
      expected_ninth
    );

    if (data_index >= segment.data_ninth_controller_low.size())
      `uvm_error(
        "I3C_SB",
        $sformatf("segment[%0d] has no controller-drive sample for data[%0d]",
                  segment_index, data_index)
      )
    else
      check_logic(
        $sformatf("segment[%0d].ninth_controller_low[%0d]",
                  segment_index, data_index),
        segment.data_ninth_controller_low[data_index],
        expected_controller_low
      );

    if (data_index >= segment.data_ninth_target_low.size())
      `uvm_error(
        "I3C_SB",
        $sformatf("segment[%0d] has no target-drive sample for data[%0d]",
                  segment_index, data_index)
      )
    else
      check_logic(
        $sformatf("segment[%0d].ninth_target_low[%0d]",
                  segment_index, data_index),
        segment.data_ninth_target_low[data_index],
        expected_target_low
      );
  endfunction

  // --------------------------- payload 通用比较层 ----------------------------

  // 比较一个 segment 中的全部 payload。
  // data_offset：payload 在 segment.data[] 中的起点；broadcast/direct CCC 的
  //               data[0] 是 CCC code，所以真正 payload 从 1 开始。
  // force_i3c_mode：CCC 固定使用 I3C 第九位规则，不受普通 private 模式镜像影响。
  // 函数先检查总 byte 数，再根据 expected.rw 分派给读/写 byte 检查器。
  function void compare_payload(
    i3c_bus_segment segment,
    int             segment_index,
    i3c_expected_op expected,
    int             data_offset,
    bit             force_i3c_mode
  );
    int expected_size;
    bit mode;

    expected_size = data_offset +
                    (expected.rw ? expected.read_data.size()
                                 : expected.write_data.size());
    check_int(
      $sformatf("segment[%0d].data.size", segment_index),
      segment.data.size(),
      expected_size
    );

    mode = force_i3c_mode ? 1'b1 : expected.i3c_mode;
    for (int i = 0;
         i < (expected.rw ? expected.read_data.size()
                          : expected.write_data.size());
         i++) begin
      if ((data_offset + i) >= segment.data.size())
        continue;

      if (expected.rw) begin
        if (i >= expected.read_data.size()) begin
          `uvm_error(
            "I3C_SB",
            $sformatf("cmd[%0d] has no predicted read byte %0d", expected.command_id, i)
          )
          continue;
        end
        check_read_byte(
          segment,
          segment_index,
          data_offset + i,
          i,
          expected.length,
          expected.target_read_length,
          expected.read_data[i],
          mode
        );
      end
      else begin
        if (i >= expected.write_data.size()) begin
          `uvm_error(
            "I3C_SB",
            $sformatf("cmd[%0d] has no predicted write byte %0d", expected.command_id, i)
          )
          continue;
        end
        check_write_byte(
          segment,
          segment_index,
          data_offset + i,
          expected.write_data[i],
          mode,
          // 仅 legacy I2C 写会使用此参数：最后一个实际发送 byte 预期 NACK。
          !mode && expected.expect_i2c_data_nack &&
            (i == (expected.write_data.size() - 1))
        );
      end
    end
  endfunction

  // 把“独立预测的读数据”登记为未来 RX_PORT 应读出的内容。
  // 只有读命令且目标地址 ACK 后数据才可能进入 DUT RX FIFO。这里使用 predictor
  // 的 expected.read_data，绝不使用 bus monitor 的 actual.data。
  function void enqueue_expected_rx(i3c_expected_op expected);
    if (!expected.rw || !expected.expect_target_ack)
      return;
    foreach (expected.read_data[i])
      expected_rx_q.push_back(expected.read_data[i]);
  endfunction

  // --------------------------- 事务级协议比较层 ------------------------------

  // Private transfer 的预期结构：
  //   START -> {target_addr, R/W} -> address ACK/NACK -> payload -> STOP
  // 因而正常只有一个 segment。地址 NACK 后不得再出现 payload；读命令比较完
  // 总线数据后，还要把独立预测的数据加入 expected_rx_q，供以后检查 RX_PORT。
  function void compare_private(i3c_bus_txn actual, i3c_expected_op expected);
    i3c_bus_segment segment;

    check_int("private segment count", actual.segments.size(), 1);
    if (actual.segments.size() == 0)
      return;

    segment = actual.segments[0];
    check_boundaries(segment, 0, I3C_BOUNDARY_START, I3C_BOUNDARY_STOP);
    check_segment_header(
      segment,
      0,
      expected.addr,
      expected.rw,
      expected.expect_target_ack
    );

    // 地址未被 target 接受时，controller 应立即结束本次传输。
    if (!expected.expect_target_ack) begin
      check_int("private NACK data size", segment.data.size(), 0);
      return;
    end

    compare_payload(segment, 0, expected, 0, 1'b0);
    enqueue_expected_rx(expected);
  endfunction

  // Broadcast CCC 的预期结构：
  //   START -> 7E/W -> broadcast ACK/NACK -> CCC code -> payload -> STOP
  // data[0] 固定是 CCC code，后面的 expected.length 个 byte 才是命令 payload；
  // CCC 始终使用 I3C 第九位规则。
  function void compare_broadcast_ccc(
    i3c_bus_txn actual,
    i3c_expected_op expected
  );
    i3c_bus_segment segment;
    int expected_size;

    check_int("broadcast CCC segment count", actual.segments.size(), 1);
    if (actual.segments.size() == 0)
      return;

    segment = actual.segments[0];
    check_boundaries(segment, 0, I3C_BOUNDARY_START, I3C_BOUNDARY_STOP);
    check_segment_header(segment, 0, 7'h7e, 1'b0, expected.expect_bcast_ack);

    // 广播地址 7E/W 被 NACK 后，CCC code 根本不会发送到总线。
    if (!expected.expect_bcast_ack) begin
      check_int("broadcast CCC NACK data size", segment.data.size(), 0);
      return;
    end

    expected_size = 1 + expected.length;
    check_int("broadcast CCC data size", segment.data.size(), expected_size);
    if (segment.data.size() > 0)
      check_write_byte(segment, 0, 0, expected.ccc_code, 1'b1, 1'b0);
    compare_payload(segment, 0, expected, 1, 1'b1);
  endfunction

  // Direct CCC 正常包含两个 segment：
  //   segment[0]：START   -> 7E/W -> ACK -> CCC code -> RESTART
  //   segment[1]：RESTART -> target address/RW -> ACK -> payload -> STOP
  // 第一个 ACK 是广播阶段 expect_bcast_ack；第二个 ACK 才是目标地址阶段
  // expect_target_ack。两者来自两条不同 target intent，不能混为同一个 ACK。
  function void compare_direct_ccc(i3c_bus_txn actual, i3c_expected_op expected);
    i3c_bus_segment broadcast_segment;
    i3c_bus_segment target_segment;

    // 7E/W 就被 NACK 时，不会发送 CCC code，也不会出现 repeated START 和
    // target segment；此时总线外形与“广播 CCC 在地址处中止”完全相同。
    if (!expected.expect_bcast_ack) begin
      check_int("direct CCC broadcast-NACK segment count", actual.segments.size(), 1);
      if (actual.segments.size() == 0)
        return;
      broadcast_segment = actual.segments[0];
      check_boundaries(
        broadcast_segment,
        0,
        I3C_BOUNDARY_START,
        I3C_BOUNDARY_STOP
      );
      check_segment_header(broadcast_segment, 0, 7'h7e, 1'b0, 1'b0);
      check_int("direct CCC broadcast-NACK data size", broadcast_segment.data.size(), 0);
      return;
    end

    check_int("direct CCC segment count", actual.segments.size(), 2);
    if (actual.segments.size() == 0)
      return;

    // 第一段只检查广播地址和一个 CCC code。
    broadcast_segment = actual.segments[0];
    check_boundaries(
      broadcast_segment,
      0,
      I3C_BOUNDARY_START,
      I3C_BOUNDARY_RESTART
    );
    check_segment_header(broadcast_segment, 0, 7'h7e, 1'b0, 1'b1);
    check_int("direct CCC code count", broadcast_segment.data.size(), 1);
    if (broadcast_segment.data.size() > 0)
      check_write_byte(
        broadcast_segment, 0, 0, expected.ccc_code, 1'b1, 1'b0
      );

    if (actual.segments.size() < 2)
      return;
    // 第二段从 repeated START 开始，方向和 payload 都属于真正 target。
    target_segment = actual.segments[1];
    check_boundaries(
      target_segment,
      1,
      I3C_BOUNDARY_RESTART,
      I3C_BOUNDARY_STOP
    );
    check_segment_header(
      target_segment,
      1,
      expected.addr,
      expected.rw,
      expected.expect_target_ack
    );

    // 广播阶段成功并不代表目标地址一定 ACK；目标 NACK 后同样不得有 payload。
    if (!expected.expect_target_ack) begin
      check_int("direct CCC target-NACK data size", target_segment.data.size(), 0);
      return;
    end

    compare_payload(target_segment, 1, expected, 0, 1'b1);
    enqueue_expected_rx(expected);
  endfunction

  // ENTDAA 的预期结构分为两种对象保存：
  //
  //   actual.segments[0]
  //     START -> 7E/W -> ACK -> ENTDAA code -> RESTART
  //
  //   actual.entdaa_rounds[i]
  //     7E/R -> ACK -> 64-bit PID/BCR/DCR -> assigned DA + parity
  //     -> target 对 DA 的 ACK -> RESTART/STOP
  //
  // 64-bit 身份仲裁是连续位流，不是普通的“8 data + 1 ninth”格式，所以 monitor
  // 必须单独解码成 entdaa_round，而不能塞进普通 segment.data[]。
  function void compare_entdaa(i3c_bus_txn actual, i3c_expected_op expected);
    i3c_bus_segment          prefix;
    i3c_entdaa_round         actual_round;
    i3c_expected_entdaa_round expected_round;
    int expected_round_count;

    if (actual.segments.size() == 0) begin
      `uvm_error("I3C_SB", "ENTDAA transfer has no segment")
      return;
    end

    // 普通 segment 队列只应包含最前面的广播 CCC 前缀；每轮 repeated START
    // 仲裁放入 entdaa_rounds，防止连续 64-bit ID 被误当成多个 9-bit 数据 byte。
    check_int("ENTDAA prefix segment count", actual.segments.size(), 1);
    prefix = actual.segments[0];
    check_boundaries(
      prefix,
      0,
      I3C_BOUNDARY_START,
      expected.expect_bcast_ack ? I3C_BOUNDARY_RESTART : I3C_BOUNDARY_STOP
    );
    check_segment_header(prefix, 0, 7'h7e, 1'b0, expected.expect_bcast_ack);

    if (!expected.expect_bcast_ack) begin
      check_int("ENTDAA broadcast-NACK prefix data size", prefix.data.size(), 0);
      check_int("ENTDAA broadcast-NACK round count",
                actual.entdaa_rounds.size(), 0);
      return;
    end

    check_int("ENTDAA prefix data size", prefix.data.size(), 1);
    if (prefix.data.size() > 0)
      check_write_byte(prefix, 0, 0, expected.ccc_code, 1'b1, 1'b0);

    // 正常完整流程的 actual round 数 = 成功分配轮数 + 最后一轮 7E/R NACK。
    // 若 DA ACK 失败，predictor 会关闭 final-NACK 预期，因为流程已经异常终止。
    expected_round_count = expected.entdaa_rounds.size() +
                           (expected.expect_entdaa_final_nack ? 1 : 0);
    check_int("ENTDAA round count",
              actual.entdaa_rounds.size(), expected_round_count);

    // 逐轮检查成功的 target：边界、7E/R、64-bit ID、动态地址、parity 和 ACK。
    foreach (expected.entdaa_rounds[i]) begin
      if (i >= actual.entdaa_rounds.size())
        continue;
      actual_round   = actual.entdaa_rounds[i];
      expected_round = expected.entdaa_rounds[i];
      if (actual_round == null || expected_round == null) begin
        `uvm_error(
          "I3C_SB",
          $sformatf("ENTDAA successful round[%0d] contains a null object", i)
        )
        continue;
      end

      if (actual_round.start_boundary != I3C_BOUNDARY_RESTART)
        report_mismatch(
          $sformatf("ENTDAA round[%0d].start", i),
          actual_round.start_boundary.name(),
          I3C_BOUNDARY_RESTART.name()
        );
      if (actual_round.end_boundary !=
          (expected_round.expect_da_ack ? I3C_BOUNDARY_RESTART
                                        : I3C_BOUNDARY_STOP))
        report_mismatch(
          $sformatf("ENTDAA round[%0d].end", i),
          actual_round.end_boundary.name(),
          expected_round.expect_da_ack ? I3C_BOUNDARY_RESTART.name()
                                       : I3C_BOUNDARY_STOP.name()
        );

      check_int($sformatf("ENTDAA round[%0d].header_bit_count", i),
                actual_round.header_bit_count, 8);
      check_logic($sformatf("ENTDAA round[%0d].header_complete", i),
                  actual_round.header_complete, 1'b1);
      // 8'hfd = {7'h7e, 1'b1}，即广播地址 7E 的读方向 header。
      check_byte($sformatf("ENTDAA round[%0d].header", i),
                 actual_round.header, 8'hfd);
      // header_ninth/da_ack 都保存原始 SDA 电平，所以期望 ACK 时取反为 0。
      check_logic($sformatf("ENTDAA round[%0d].header_ninth", i),
                  actual_round.header_ninth,
                  !expected_round.expect_header_ack);

      check_int($sformatf("ENTDAA round[%0d].id_bit_count", i),
                actual_round.id_bit_count, 64);
      check_logic($sformatf("ENTDAA round[%0d].id_complete", i),
                  actual_round.id_complete, 1'b1);
      check_u64($sformatf("ENTDAA round[%0d].id", i),
                actual_round.id, expected_round.id);

      check_int($sformatf("ENTDAA round[%0d].assigned_da_bit_count", i),
                actual_round.assigned_da_bit_count, 8);
      check_logic($sformatf("ENTDAA round[%0d].assigned_da_complete", i),
                  actual_round.assigned_da_complete, 1'b1);
      if (actual_round.assigned_da !== expected_round.assigned_da)
        report_mismatch(
          $sformatf("ENTDAA round[%0d].assigned_da", i),
          $sformatf("0x%02h", actual_round.assigned_da),
          $sformatf("0x%02h", expected_round.assigned_da)
        );
      check_logic($sformatf("ENTDAA round[%0d].da_parity", i),
                  actual_round.da_parity, ~^expected_round.assigned_da);
      check_logic($sformatf("ENTDAA round[%0d].da_ack_complete", i),
                  actual_round.da_ack_complete, 1'b1);
      check_logic($sformatf("ENTDAA round[%0d].da_ack", i),
                  actual_round.da_ack, !expected_round.expect_da_ack);

      if (expected_round.expect_da_ack && !actual_round.is_successful())
        `uvm_error(
          "I3C_SB",
          $sformatf("ENTDAA round[%0d] is not a complete successful round", i)
        )
    end

    // 所有 target 分配完成后，controller 再发一次 7E/R 探测。没人 ACK 表示
    // ENTDAA 正常结束；这一轮只能包含 header，不能再含 ID 或动态地址字段。
    if (expected.expect_entdaa_final_nack &&
        (actual.entdaa_rounds.size() > expected.entdaa_rounds.size())) begin
      int final_index;

      final_index  = expected.entdaa_rounds.size();
      actual_round = actual.entdaa_rounds[final_index];
      if (actual_round == null) begin
        `uvm_error("I3C_SB", "ENTDAA final-NACK round is null")
        return;
      end

      if (actual_round.start_boundary != I3C_BOUNDARY_RESTART)
        report_mismatch(
          "ENTDAA final round start",
          actual_round.start_boundary.name(),
          I3C_BOUNDARY_RESTART.name()
        );
      if (actual_round.end_boundary != I3C_BOUNDARY_STOP)
        report_mismatch(
          "ENTDAA final round end",
          actual_round.end_boundary.name(),
          I3C_BOUNDARY_STOP.name()
        );
      check_int("ENTDAA final round header_bit_count",
                actual_round.header_bit_count, 8);
      check_logic("ENTDAA final round header_complete",
                  actual_round.header_complete, 1'b1);
      check_byte("ENTDAA final round header", actual_round.header, 8'hfd);
      check_logic("ENTDAA final round header_ninth",
                  actual_round.header_ninth, 1'b1);
      check_int("ENTDAA final round ID bit count",
                actual_round.id_bit_count, 0);
      check_logic("ENTDAA final round ID complete",
                  actual_round.id_complete, 1'b0);
      check_int("ENTDAA final round DA bit count",
                actual_round.assigned_da_bit_count, 0);
      check_logic("ENTDAA final round DA complete",
                  actual_round.assigned_da_complete, 1'b0);
      check_logic("ENTDAA final round DA ACK complete",
                  actual_round.da_ack_complete, 1'b0);
      if (!actual_round.is_final_header_nack())
        `uvm_error(
          "I3C_SB",
          "ENTDAA did not end with a dedicated 7E/R header-NACK round"
        )
    end
  endfunction

  // controller 发起事务的统一分发入口。
  // process_bus() 已经按 FIFO 取到一对 actual/expected；这里先检查来源和类型，
  // 再按照 expected.kind 进入具体协议比较函数。即使 kind 已报 mismatch，仍继续
  // 按 expected 类型深入比较，以便日志给出更具体的 header/payload 错误。
  function void compare_expected_transfer(
    i3c_bus_txn     actual,
    i3c_expected_op expected
  );
    bit kind_compatible;

    if (actual.origin != I3C_ORIGIN_CONTROLLER)
      report_mismatch(
        "transfer origin",
        actual.origin.name(),
        I3C_ORIGIN_CONTROLLER.name()
      );

    kind_compatible = (actual.kind == expected.kind);
    // 如果 7E/W 地址阶段就 NACK，CCC code 尚未出现在总线上。纯被动 monitor
    // 无法判断软件原本计划的是 Broadcast、Direct CCC 还是 ENTDAA，因此后两者
    // 在这个早退路径上被识别成 Broadcast CCC 也认为“类型外形兼容”。
    if (!expected.expect_bcast_ack &&
        ((expected.kind == I3C_KIND_DIRECT_CCC) ||
         (expected.kind == I3C_KIND_ENTDAA)) &&
        (actual.kind == I3C_KIND_BROADCAST_CCC))
      kind_compatible = 1'b1;
    if (!kind_compatible)
      report_mismatch("transfer kind", actual.kind.name(), expected.kind.name());

    case (expected.kind)
      I3C_KIND_PRIVATE:
        compare_private(actual, expected);
      I3C_KIND_BROADCAST_CCC:
        compare_broadcast_ccc(actual, expected);
      I3C_KIND_DIRECT_CCC:
        compare_direct_ccc(actual, expected);
      I3C_KIND_ENTDAA:
        compare_entdaa(actual, expected);
      default:
        `uvm_error(
          "I3C_SB",
          $sformatf("cmd[%0d] unsupported expected kind %s",
                    expected.command_id, expected.kind.name())
        )
    endcase
  endfunction

  // IBI 比较入口。
  // IBI 是 target 主动发起的事务，不对应 APB CMD_PORT，因此 expected 不来自
  // i3c_cmd_predictor，而来自 target model 预先发布到 ibi_intent_fifo 的计划。
  // 预期外形：target START -> {target_addr, R} -> controller ACK/NACK
  //          -> 可选 MDB -> T-bit -> STOP。
  function void compare_ibi(
    i3c_bus_txn actual,
    i3c_ibi_intent expected
  );
    i3c_bus_segment segment;
    int expected_data_count;
    logic expected_resolved_t;

    // 先检查当前 CTRL 软件模型是否允许 IBI，再检查 monitor 解码的来源和类型。
    if (!ibi_en_model)
      `uvm_error("I3C_SB", "IBI observed while CTRL.ibi_en model is disabled")
    if (actual.origin != I3C_ORIGIN_TARGET)
      report_mismatch(
        "IBI origin",
        actual.origin.name(),
        I3C_ORIGIN_TARGET.name()
      );
    if (actual.kind != I3C_KIND_IBI)
      report_mismatch("IBI kind", actual.kind.name(), I3C_KIND_IBI.name());
    check_int("IBI segment count", actual.segments.size(), 1);
    check_int("IBI ENTDAA-round count", actual.entdaa_rounds.size(), 0);
    if (actual.segments.size() == 0)
      return;

    segment = actual.segments[0];
    check_boundaries(segment, 0, I3C_BOUNDARY_START, I3C_BOUNDARY_STOP);
    check_logic("IBI segment ended_by_stop", segment.ended_by_stop, 1'b1);
    check_logic("IBI segment ended_by_restart", segment.ended_by_restart, 1'b0);
    check_segment_header(
      segment,
      0,
      expected.expected_addr,
      1'b1,
      expected.expect_addr_ack
    );

    // target 的 MDB 发送计划应与 controller 的 CTRL.ibi_mdb_en 配置一致。
    if (expected.has_mdb !== ibi_mdb_en_model)
      report_mismatch(
        "IBI target MDB plan vs CTRL.ibi_mdb_en",
        $sformatf("%0b", expected.has_mdb),
        $sformatf("%0b", ibi_mdb_en_model)
      );

    // 只有 controller 接受 IBI 地址且 target 计划携带 MDB，才应出现一个数据 byte。
    expected_data_count = (expected.expect_addr_ack && expected.has_mdb) ? 1 : 0;
    check_int("IBI MDB count", segment.data.size(), expected_data_count);
    check_int("IBI MDB ninth-bit count",
              segment.data_ninth_bits.size(), expected_data_count);
    check_int("IBI MDB controller-drive sample count",
              segment.data_ninth_controller_low.size(), expected_data_count);
    check_int("IBI MDB target-drive sample count",
              segment.data_ninth_target_low.size(), expected_data_count);

    if (expected_data_count != 0 && segment.data.size() > 0) begin
      check_byte("IBI MDB", segment.data[0], expected.mdb);
      // SCL/SDA 上只能看到 wired-AND 后的 T；任意一方拉低，resolved T 就为 0。
      expected_resolved_t = !(expected.expect_controller_t_low ||
                              expected.expect_target_t_low);

      if (segment.data_ninth_bits.size() > 0)
        check_logic("IBI final resolved T", segment.data_ninth_bits[0],
                    expected_resolved_t);
      if (segment.data_ninth_controller_low.size() > 0)
        check_logic("IBI final controller T-low drive",
                    segment.data_ninth_controller_low[0],
                    expected.expect_controller_t_low);
      if (segment.data_ninth_target_low.size() > 0)
        check_logic("IBI final target T-low drive",
                    segment.data_ninth_target_low[0],
                    expected.expect_target_t_low);

      // RX_PORT 的预期值必须来自事先发布的 target plan，绝不能从被动 monitor
      // 采到的 segment.data[0] 反推，否则 expected 与 actual 会变成同源数据。
      expected_rx_q.push_back(expected.mdb);
    end
  endfunction

  // --------------------------- 运行时取数与配对 ------------------------------

  // 总线事务主线程。
  // 先阻塞等待 bus monitor 发布一笔完整 actual，再根据发起方选择 expected 来源：
  //   target-origin     -> IBI plan FIFO；
  //   controller-origin -> predictor expected FIFO。
  // 这里的匹配依据是 FIFO 先后顺序，不是对象名字或 command_id。
  task process_bus();
    i3c_bus_txn     actual;
    i3c_expected_op expected;
    i3c_ibi_intent  ibi_expected;

    forever begin
      // bus monitor 通常在完整 STOP 后才 ap.write(tr)，所以 get() 返回时 actual
      // 已是一笔完整总线 transaction，而不是每个 bit/byte 都来一次。
      bus_fifo.get(actual);
      if (actual.origin == I3C_ORIGIN_TARGET) begin
        // target 主动发起目前只对应 IBI，因此直接与最早的 IBI plan 配对。
        if (!ibi_intent_fifo.try_get(ibi_expected))
          `uvm_error(
            "I3C_SB",
            "observed target-initiated IBI with no independent target plan"
          )
        else
          compare_ibi(actual, ibi_expected);
        continue;
      end

      // controller actual 到达时，APB 命令应早已被 predictor 转成 expected，
      // 所以这里使用非阻塞 try_get()。取不到不是“再等等”即可忽略，而表示缺少
      // APB 预测、顺序错位或 predictor 被某个 target/TX 条件卡住。
      if (!expected_fifo.try_get(expected)) begin
        `uvm_error(
          "I3C_SB",
          $sformatf(
            "observed controller transfer kind=%s with no predicted APB command",
            actual.kind.name()
          )
        )
        continue;
      end
      // reset_epoch 防止复位前残留 expected 与复位后的 actual 错配。
      if (expected.reset_epoch != vif.tb_reset_epoch) begin
        `uvm_info(
          "I3C_SB_RESET",
          $sformatf(
            "discarding stale cmd[%0d] expected epoch=%0d current=%0d",
            expected.command_id, expected.reset_epoch, vif.tb_reset_epoch
          ),
          UVM_MEDIUM
        )
        continue;
      end
      compare_expected_transfer(actual, expected);
    end
  endtask

  // APB 旁路处理线程。
  // 输入仍来自同一个 APB monitor，但本类只关心：
  //   1. CTRL 写：维护 IBI 配置镜像，处理软件复位；
  //   2. RX_PORT 读：检查 DUT RX FIFO 交给软件的 byte。
  // TX_PORT/CMD_PORT 已由 predictor 消费，这里无需重复处理。
  task process_apb();
    i3c_txn apb_tr;
    logic [7:0] expected_byte;

    forever begin
      apb_fifo.get(apb_tr);
      if (vif.rst_n !== 1'b1)
        continue;

      if ((apb_tr.op == WR) && (apb_tr.addr == REG_CTRL) && apb_tr.strb[0]) begin
        // 只有低 byte strobe 有效时 CTRL[4:0] 的写入才生效。
        ibi_en_model     = apb_tr.data[3];
        ibi_mdb_en_model = apb_tr.data[4];
        if (apb_tr.data[2])
          flush_transactions();
      end
      else if ((apb_tr.op == RD) && (apb_tr.addr == RX_PORT)) begin
        // APB 每读一次 RX_PORT，就应按顺序取出一个独立预测的 RX byte。
        if (expected_rx_q.size() == 0) begin
          `uvm_error(
            "I3C_SB",
            $sformatf(
              "RX_PORT returned 0x%02h with no independently predicted read byte",
              apb_tr.data[7:0]
            )
          )
        end
        else begin
          expected_byte = expected_rx_q.pop_front();
          check_byte("RX_PORT data", apb_tr.data[7:0], expected_byte);
        end
      end
    end
  endtask

  // 三个常驻线程必须并行：等待总线 STOP、等待 APB transaction、监听硬复位。
  // 任意一条若串行放在前面，都会 forever 阻塞后面的工作。
  task run_phase(uvm_phase phase);
    fork
      process_bus();
      process_apb();
      watch_hard_reset();
    join
  endtask

  // 测试结束时检查是否还有未完成的数据流。各类残留分别表示：
  //   expected_fifo 非空：软件下了命令，但总线上没有看到对应 controller 事务；
  //   bus_fifo 非空     ：monitor 发布了 actual，但比较线程没有消费完；
  //   apb_fifo 非空     ：APB 旁路线程未消费完 monitor 广播；
  //   ibi_intent_fifo非空：target 计划发 IBI，但总线上没有出现对应 IBI；
  //   expected_rx_q 非空：预测有数据进入 RX FIFO，但软件从未全部读走。
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (expected_fifo.used() != 0)
      `uvm_error(
        "I3C_SB",
        $sformatf("%0d expected transfer(s) were never observed", expected_fifo.used())
      )
    if (bus_fifo.used() != 0)
      `uvm_error(
        "I3C_SB",
        $sformatf("%0d observed transfer(s) were never compared", bus_fifo.used())
      )
    if (apb_fifo.used() != 0)
      `uvm_error(
        "I3C_SB",
        $sformatf("%0d APB transaction(s) remain unprocessed", apb_fifo.used())
      )
    if (ibi_intent_fifo.used() != 0)
      `uvm_error(
        "I3C_SB",
        $sformatf("%0d IBI target plan(s) were never observed",
                  ibi_intent_fifo.used())
      )
    if (expected_rx_q.size() != 0)
      `uvm_error(
        "I3C_SB",
        $sformatf("%0d predicted RX byte(s) were never read", expected_rx_q.size())
      )
  endfunction
endclass
