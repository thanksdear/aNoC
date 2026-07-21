// ---------------------------------------------------------------------------
// 总线 monitor 输出的数据分为三层：
//
// i3c_bus_txn
//   一笔完整的 START -> STOP transaction。
//
// i3c_bus_segment
//   transaction 内由 START/Repeated START 开始、到 Repeated START/STOP
//   结束的一个地址段。Direct CCC 会包含至少两个 segment。
//
// i3c_entdaa_round
//   ENTDAA 专用的一轮 7E/R 仲裁。它不是普通 8+1 byte 流，所以不能放进
//   segment.data[]，必须单独描述。
//
// 这些对象只保存 monitor 从总线观察到的事实，不保存 sequence 的期望。
// scoreboard 再把实际 transaction 与 predictor 生成的 expected operation
// 比较，避免“用实际值生成期望值，再拿实际值检查自己”。
// ---------------------------------------------------------------------------

// 当前 segment 的 RnW 方向，来自 8-bit header 的 bit[0]。
// UNKNOWN 用于 header 尚未完整或采样到 X/Z 的情况，避免强行判成读或写。
typedef enum logic [1:0] {
  I3C_WRITE             = 2'd0,
  I3C_READ              = 2'd1,
  I3C_DIRECTION_UNKNOWN = 2'd2
} i3c_direction_e;

// START 的发起方。普通 private/CCC 由 controller 发起；IBI 由 target
// 主动拉低 SDA 发起。UNKNOWN 表示两侧驱动状态不足以可靠判断。
typedef enum logic [1:0] {
  I3C_ORIGIN_UNKNOWN    = 2'd0,
  I3C_ORIGIN_CONTROLLER = 2'd1,
  I3C_ORIGIN_TARGET     = 2'd2
} i3c_bus_origin_e;

// monitor 根据总线上实际出现的 header、CCC code、segment 数量和发起方
// 得到的 transaction 类型。它不是 test 提前告诉 monitor 的期望类型。
typedef enum logic [2:0] {
  I3C_KIND_UNKNOWN       = 3'd0,
  I3C_KIND_PRIVATE       = 3'd1,
  I3C_KIND_BROADCAST_CCC = 3'd2,
  I3C_KIND_DIRECT_CCC    = 3'd3,
  I3C_KIND_ENTDAA        = 3'd4,
  I3C_KIND_IBI           = 3'd5
} i3c_bus_kind_e;

// segment/ENTDAA round 的起止边界。
// RESET 表示传输被硬复位或软件复位打断；这种残缺 transaction 不应送入
// scoreboard，只用于 monitor 内部明确说明为什么停止收集。
typedef enum logic [2:0] {
  I3C_BOUNDARY_NONE    = 3'd0,
  I3C_BOUNDARY_START   = 3'd1,
  I3C_BOUNDARY_RESTART = 3'd2,
  I3C_BOUNDARY_STOP    = 3'd3,
  I3C_BOUNDARY_RESET   = 3'd4
} i3c_bus_boundary_e;

// 一个 segment 从 START/Repeated START 开始，到下一个 Repeated START 或
// STOP 结束。这样 Direct CCC 的 broadcast 地址段和 target 地址段不会混在
// 同一个 data[] 中。
//
// 所有第九位都保存原始值，不直接命名成 ACK。因为同一个物理位置可能是：
//   - 地址 ACK/NACK；
//   - I3C write 的 parity T-bit；
//   - I3C read 的 End-of-Data T-bit；
//   - legacy I2C write 的数据 ACK/NACK；
//   - legacy I2C read 的 controller ACK/NACK。
// 它的含义必须由 scoreboard 结合 kind、direction 和 I3C/I2C mode 判断。
class i3c_bus_segment extends uvm_sequence_item;
  // 本地址段由什么边界开始、由什么边界结束。
  i3c_bus_boundary_e start_boundary;
  i3c_bus_boundary_e end_boundary;

  // header = {7-bit address, RnW}。
  // header_complete 使用两态 bit：它表示 monitor 自己的收集状态；
  // header/addr_ninth 使用四态 logic：总线上的 X/Z 必须被保留下来。
  bit                header_complete;
  logic [7:0]        header;
  // 地址后的原始第九位：0 通常表示 ACK，1 通常表示 NACK。
  logic              addr_ninth;
  // 从 header[7:1] 拆出的地址，方便 scoreboard/coverage 使用。
  logic [6:0]        addr;
  // 从 header[0] 拆出的读写方向。
  i3c_direction_e    direction;

  // data[i] 与下面三个 ninth-bit 队列的索引必须一一对应：
  // data[i]                     第 i 个数据 byte；
  // data_ninth_bits[i]          总线上解析到的第九位；
  // controller_low[i]           第九位时 controller 是否主动拉低；
  // target_low[i]               第九位时 target 是否主动拉低。
  logic [7:0]        data[$];
  logic              data_ninth_bits[$];
  // 只保存 resolved SDA 不够：读到 0 无法判断是谁拉低。额外记录两侧
  // 开漏贡献后，scoreboard 才能区分 target 主动结束与 controller 提前
  // 结束，而不是仅用同一个 resolved 值证明自己。
  logic              data_ninth_controller_low[$];
  logic              data_ninth_target_low[$];

  // 这两个字段是 end_boundary 的便捷形式，主要供 coverage 和日志使用。
  bit                ended_by_restart;
  bit                ended_by_stop;

  // 注册所有字段，使 UVM 的 print/copy/compare/record 能看到完整 segment。
  // 队列字段必须使用 uvm_field_queue_*，否则打印 transaction 时会丢数据。
  `uvm_object_utils_begin(i3c_bus_segment)
    `uvm_field_enum(i3c_bus_boundary_e, start_boundary, UVM_ALL_ON)
    `uvm_field_enum(i3c_bus_boundary_e, end_boundary, UVM_ALL_ON)
    `uvm_field_int(header_complete, UVM_ALL_ON)
    `uvm_field_int(header, UVM_ALL_ON)
    `uvm_field_int(addr_ninth, UVM_ALL_ON)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_enum(i3c_direction_e, direction, UVM_ALL_ON)
    `uvm_field_queue_int(data, UVM_ALL_ON)
    `uvm_field_queue_int(data_ninth_bits, UVM_ALL_ON)
    `uvm_field_queue_int(data_ninth_controller_low, UVM_ALL_ON)
    `uvm_field_queue_int(data_ninth_target_low, UVM_ALL_ON)
    `uvm_field_int(ended_by_restart, UVM_ALL_ON)
    `uvm_field_int(ended_by_stop, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "i3c_bus_segment");
    super.new(name);
    // 边界默认 NONE；总线采样字段默认 X。这样 monitor 漏采时会在
    // scoreboard 中暴露为 X/未完成，而不会被默认 0 伪装成合法 ACK/地址。
    start_boundary = I3C_BOUNDARY_NONE;
    end_boundary   = I3C_BOUNDARY_NONE;
    header         = 'x;
    addr_ninth     = 1'bx;
    addr           = 'x;
    direction      = I3C_DIRECTION_UNKNOWN;
  endfunction
endclass

// 一轮 ENTDAA 仲裁的实际总线记录。
//
// 普通 payload 是 8-bit data + 第九位，但 ENTDAA 的 64-bit PID/BCR/DCR
// 是连续位流，每 8 位后没有第九位，因此不能放进 i3c_bus_segment::data[]。
//
// 一轮成功流程为：
//   Repeated START -> 7E/R -> header ACK -> 64-bit ID
//   -> 7-bit assigned DA + odd parity -> target DA ACK -> Repeated START
//
// 所有 target 都完成分配后，最后还有一轮：
//   Repeated START -> 7E/R -> header NACK -> STOP
// 这个 final header NACK 是正常结束，不应当作地址分配失败。
class i3c_entdaa_round extends uvm_sequence_item;
  // 每轮正常从 Repeated START 开始；成功轮通常由下一次 Repeated START
  // 结束，最后 NACK 轮或错误轮由 STOP 结束。
  i3c_bus_boundary_e start_boundary;
  i3c_bus_boundary_e end_boundary;

  // 7E/R header 的采样进度和结果。bit_count 允许在复位/STOP 异常中断时
  // 报告“实际采到了几位”，比只保存一个 complete 标志更容易定位错位。
  int unsigned       header_bit_count;
  logic [7:0]        header;
  bit                header_complete;
  // header 后的原始 ACK/NACK：0=有未分配 target 参加，1=无人参加。
  logic              header_ninth;

  // target 仲裁输出的连续 64-bit PID/BCR/DCR 及其采样进度。
  int unsigned       id_bit_count;
  logic [63:0]       id;
  bit                id_complete;

  // Controller 分配的 7-bit dynamic address、随后的奇校验位，以及
  // target 对该地址分配结果的 ACK/NACK。
  int unsigned       assigned_da_bit_count;
  logic [6:0]        assigned_da;
  logic              da_parity;
  bit                assigned_da_complete;
  bit                da_ack_complete;
  logic              da_ack;

  // end_boundary 的便捷字段，供 coverage/日志直接使用。
  bit                ended_by_restart;
  bit                ended_by_stop;

  // 注册完整 round，保证 UVM 打印和 scoreboard 队列操作不会丢字段。
  `uvm_object_utils_begin(i3c_entdaa_round)
    `uvm_field_enum(i3c_bus_boundary_e, start_boundary, UVM_ALL_ON)
    `uvm_field_enum(i3c_bus_boundary_e, end_boundary, UVM_ALL_ON)
    `uvm_field_int(header_bit_count, UVM_ALL_ON)
    `uvm_field_int(header, UVM_ALL_ON)
    `uvm_field_int(header_complete, UVM_ALL_ON)
    `uvm_field_int(header_ninth, UVM_ALL_ON)
    `uvm_field_int(id_bit_count, UVM_ALL_ON)
    `uvm_field_int(id, UVM_ALL_ON)
    `uvm_field_int(id_complete, UVM_ALL_ON)
    `uvm_field_int(assigned_da_bit_count, UVM_ALL_ON)
    `uvm_field_int(assigned_da, UVM_ALL_ON)
    `uvm_field_int(da_parity, UVM_ALL_ON)
    `uvm_field_int(assigned_da_complete, UVM_ALL_ON)
    `uvm_field_int(da_ack_complete, UVM_ALL_ON)
    `uvm_field_int(da_ack, UVM_ALL_ON)
    `uvm_field_int(ended_by_restart, UVM_ALL_ON)
    `uvm_field_int(ended_by_stop, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "i3c_entdaa_round");
    super.new(name);
    // 与普通 segment 一样，未采样的总线字段初始化为 X，避免残缺 round
    // 被默认 0 误认为 ACK、合法地址或合法 ID。
    start_boundary          = I3C_BOUNDARY_NONE;
    end_boundary            = I3C_BOUNDARY_NONE;
    header                  = 'x;
    header_ninth            = 1'bx;
    id                      = 'x;
    assigned_da             = 'x;
    da_parity               = 1'bx;
    da_ack                  = 1'bx;
  endfunction

  function bit is_successful();
    // 成功不能只看 DA ACK，还必须同时满足：边界正确、header=7E/R 且 ACK、
    // 64-bit ID 完整、DA+parity 完整且为奇校验、最后 target ACK DA。
    return (start_boundary == I3C_BOUNDARY_RESTART) &&
           (end_boundary == I3C_BOUNDARY_RESTART) &&
           header_complete && (header === 8'hfd) &&
           (header_ninth === 1'b0) && id_complete &&
           assigned_da_complete &&
           ((^{assigned_da, da_parity}) === 1'b1) &&
           da_ack_complete &&
           (da_ack === 1'b0);
  endfunction

  function bit is_final_header_nack();
    // 最终正常结束轮只有 NACKed 7E/R header，不应再出现 ID、assigned DA
    // 或 DA ACK。明确检查这些计数可防止把中途损坏的 round 当成正常结束。
    return (start_boundary == I3C_BOUNDARY_RESTART) &&
           (end_boundary == I3C_BOUNDARY_STOP) &&
           header_complete && (header === 8'hfd) &&
           (header_ninth === 1'b1) &&
           (id_bit_count == 0) &&
           (assigned_da_bit_count == 0) &&
           !da_ack_complete;
  endfunction
endclass

// 一笔完整 START->STOP 总线 transaction，是 monitor 最终送给 scoreboard
// 和 coverage 的顶层对象。
//
// 常见结构：
//   private transfer：通常只有 segments[0]；
//   broadcast CCC：只有广播 segments[0]；
//   direct CCC：segments[0] 是广播 CCC，segments[1] 是 Sr 后 target 段；
//   ENTDAA：segments[0] 保存 7E/W+0x07 前缀，后续仲裁放在
//           entdaa_rounds[]，不能塞进普通 data[]；
//   IBI：通常只有一个由 target 发起的 segment。
//
// monitor 只在观察到 STOP 后发布这个对象；复位中断的残缺 transaction
// 会被丢弃，避免与下一条 expected command 错误配对。
class i3c_bus_txn extends uvm_sequence_item;
  // 谁发起了 START，用于区分 controller transaction 和 target IBI。
  i3c_bus_origin_e  origin;
  // 根据实际总线前缀和 segment 结构识别出的协议类型。
  i3c_bus_kind_e    kind;
  // 普通 START/Sr 地址段队列，按总线上出现的先后顺序保存。
  i3c_bus_segment   segments[$];
  // ENTDAA 专用仲裁轮队列；非 ENTDAA transaction 应为空。
  i3c_entdaa_round  entdaa_rounds[$];

  // 注册对象及两个对象队列，支持 UVM print/copy/compare/record。
  `uvm_object_utils_begin(i3c_bus_txn)
    `uvm_field_enum(i3c_bus_origin_e, origin, UVM_ALL_ON)
    `uvm_field_enum(i3c_bus_kind_e, kind, UVM_ALL_ON)
    `uvm_field_queue_object(segments, UVM_ALL_ON)
    `uvm_field_queue_object(entdaa_rounds, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "i3c_bus_txn");
    super.new(name);
    // 在 monitor 完成电气来源判断和协议分类前保持 UNKNOWN，防止未完整
    // transaction 被默认标记成某种合法类型。
    origin = I3C_ORIGIN_UNKNOWN;
    kind   = I3C_KIND_UNKNOWN;
  endfunction
endclass
