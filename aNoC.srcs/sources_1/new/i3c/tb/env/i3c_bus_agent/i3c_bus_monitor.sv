class i3c_bus_monitor extends uvm_monitor;
  `uvm_component_utils(i3c_bus_monitor)

  // -----------------------------------------------------------------------
  // 这个 monitor 为什么不能只写成“每 9 个 SCL 采一个 byte”：
  //
  // 1. Direct CCC 中间有 Repeated START，一笔传输会包含多个地址段；
  // 2. 第九位的含义不是固定 ACK，它也可能是 parity T-bit、读方向
  //    End-of-Data T-bit，或者 legacy I2C 的数据 ACK/NACK；
  // 3. ENTDAA 的 64-bit PID/BCR/DCR 是连续位流，中间没有每 8 位一个
  //    第九位，因此不能套普通“8+1”数据格式；
  // 4. IBI 的 START 由 target 发起，需要区分 controller/target 来源；
  // 5. 软件复位可能在半包中发生，半包不能送给 scoreboard。
  //
  // 因此这里先被动记录“总线上实际发生了什么”：边界、原始位值、
  // 驱动来源。ACK/T-bit 的协议含义留给 scoreboard 根据传输类型判断。
  // monitor 只等待和采样信号，不会主动拉高/拉低 SCL 或 SDA。
  // -----------------------------------------------------------------------

  // 下一件需要处理的总线事件。SAMPLE 是 SCL 上升沿采样；START/STOP
  // 是 SDA 在 SCL 高电平期间发生的边沿；RESET 用于丢弃复位中断的半包。
  typedef enum logic [2:0] {
    MON_EVENT_SAMPLE,
    MON_EVENT_START,
    MON_EVENT_STOP,
    MON_EVENT_RESET
  } monitor_event_e;

  // ENTDAA 专用解码状态。之所以单独定义，是因为 ENTDAA 身份字段是
  // 连续 64-bit 原始位流，不能复用普通 segment 的 8-bit+第九位解析器。
  typedef enum logic [2:0] {
    ENTDAA_DECODE_HEADER,
    ENTDAA_DECODE_PID_BCR_DCR,
    ENTDAA_DECODE_ASSIGNED_DA,
    ENTDAA_DECODE_ASSIGNED_DA_ACK,
    ENTDAA_DECODE_WAIT_BOUNDARY
  } entdaa_decode_e;

  virtual i3c_if vif;
  uvm_analysis_port #(i3c_bus_txn) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual i3c_if)::get(this, "", "vif", vif))
      `uvm_fatal("I3C_MON", "cannot get vif")
  endfunction

  // SCL 为高时 SDA 下降才是 START；SCL 为低时的 SDA 变化只是普通数据。
  // 同一任务也用于识别传输中途的 Repeated START。
  task automatic wait_start();
    forever begin
      @(negedge vif.sda_in);
      if (vif.scl_in === 1'b1)
        return;
    end
  endtask

  // SCL 为高时 SDA 上升才是 STOP，避免把数据位从 0 变 1 误判为 STOP。
  task automatic wait_stop();
    forever begin
      @(posedge vif.sda_in);
      if (vif.scl_in === 1'b1)
        return;
    end
  endtask

  // 同时等待四类事件，而不是只等待 @(posedge scl_in)。原因是 START、
  // STOP 与 SCL 采样边沿可能非常接近；若串行等待，Repeated START 前用于
  // 准备边界的 SCL 上升沿可能会被错误塞进 data[]。
  task automatic wait_next_event(
    input  longint unsigned transfer_epoch,
    output monitor_event_e  event_kind
  );
    fork : WAIT_NEXT_EVENT
      begin
        @(posedge vif.scl_in);
        event_kind = MON_EVENT_SAMPLE;
      end

      begin
        wait_start();
        event_kind = MON_EVENT_START;
      end

      begin
        wait_stop();
        event_kind = MON_EVENT_STOP;
      end

      begin
        wait ((vif.rst_n !== 1'b1) ||
              (vif.tb_reset_epoch != transfer_epoch));
        event_kind = MON_EVENT_RESET;
      end
    join_any
    disable WAIT_NEXT_EVENT;

    // 如果复位与某个电气边沿恰好发生在同一个仿真时刻，复位优先。
    // 否则 monitor 可能在软件复位时发布一个看似有 STOP 的残缺事务。
    if ((vif.rst_n !== 1'b1) ||
        (vif.tb_reset_epoch != transfer_epoch))
      event_kind = MON_EVENT_RESET;
  endtask

  task automatic wait_first_start(
    input  longint unsigned idle_epoch,
    output bit              reset_seen
  );
    // 空闲等待 START 时也监视 reset epoch。这样软件复位不会让下一笔
    // transaction 继承复位前保存的状态。
    reset_seen = 1'b0;
    fork : WAIT_FIRST_START
      begin
        wait_start();
      end

      begin
        wait ((vif.rst_n !== 1'b1) ||
              (vif.tb_reset_epoch != idle_epoch));
        reset_seen = 1'b1;
      end
    join_any
    disable WAIT_FIRST_START;
    if ((vif.rst_n !== 1'b1) ||
        (vif.tb_reset_epoch != idle_epoch))
      reset_seen = 1'b1;
  endtask

  function automatic i3c_bus_origin_e infer_origin();
    bit controller_drove_low;
    bit target_drove_low;

    // START 的总线电平相同，但驱动者不同：普通传输由 controller 发起，
    // IBI 由 target 发起。这里查看两侧“是否主动拉低”，而不是根据地址
    // 内容猜测来源。两侧同时拉低或信号不确定时返回 UNKNOWN，避免误判。
    controller_drove_low = (vif.sda_oe === 1'b1) &&
                           (vif.sda_out === 1'b0);
    target_drove_low     = (vif.slave_drive_low === 1'b1);

    if (controller_drove_low && !target_drove_low)
      return I3C_ORIGIN_CONTROLLER;
    if (target_drove_low && !controller_drove_low)
      return I3C_ORIGIN_TARGET;
    return I3C_ORIGIN_UNKNOWN;
  endfunction

  function automatic i3c_bus_segment create_segment(
    string              name,
    i3c_bus_boundary_e  start_boundary
  );
    // 一个 segment 表示 START/Sr 到下一次 Sr/STOP 的单个地址段。
    // Direct CCC 必须拆成 broadcast segment 和 target segment，不能把
    // 两个地址头及其数据混在同一个 data[] 中。
    i3c_bus_segment segment;

    segment = i3c_bus_segment::type_id::create(name);
    segment.start_boundary = start_boundary;
    return segment;
  endfunction

  function automatic void finish_segment(
    i3c_bus_segment    segment,
    i3c_bus_boundary_e boundary
  );
    // 同时保存枚举边界和便于 coverage 使用的布尔字段；两者都来自同一
    // 个实际边界事件，避免各处重复推断。
    segment.end_boundary      = boundary;
    segment.ended_by_restart  = (boundary == I3C_BOUNDARY_RESTART);
    segment.ended_by_stop     = (boundary == I3C_BOUNDARY_STOP);
  endfunction

  function automatic i3c_entdaa_round create_entdaa_round(
    string              name,
    i3c_bus_boundary_e  start_boundary
  );
    // ENTDAA 的每个 Sr->7E/R 尝试单独保存为 round。成功 round 后还会有
    // 下一轮 7E/R；最后的 header NACK 表示“已经没有未分配 target”。
    i3c_entdaa_round round;

    round = i3c_entdaa_round::type_id::create(name);
    round.start_boundary = start_boundary;
    return round;
  endfunction

  function automatic void finish_entdaa_round(
    i3c_entdaa_round   round,
    i3c_bus_boundary_e boundary
  );
    round.end_boundary      = boundary;
    round.ended_by_restart  = (boundary == I3C_BOUNDARY_RESTART);
    round.ended_by_stop     = (boundary == I3C_BOUNDARY_STOP);
  endfunction

  function automatic bit has_entdaa_prefix(
    i3c_bus_txn     tr,
    i3c_bus_segment segment
  );
    // 只有观察到 7E/W(0xFC) 后紧跟 CCC code 0x07，才切换到 ENTDAA
    // raw-bit 解码器。不能只凭地址 7E 判断，因为普通 broadcast CCC
    // 也使用相同广播地址。
    return (tr.segments.size() == 1) &&
           (tr.segments[0] == segment) &&
           segment.header_complete &&
           (segment.header === 8'hfc) &&
           (segment.data.size() > 0) &&
           (segment.data[0] === 8'h07);
  endfunction

  function automatic void classify_transfer(i3c_bus_txn tr);
    i3c_bus_segment first_segment;

    // monitor 只用“已经观察到的总线事实”分类，不读取 sequence 中的预期。
    // 否则实际发错一种 transaction 时，monitor 仍可能按预期类型标记，
    // scoreboard 就失去了发现协议错误的能力。
    tr.kind = I3C_KIND_UNKNOWN;

    // ENTDAA 的 7E/W + 0x07 前缀在总线上可直接识别。即使 START 时的
    // 电气驱动来源无法确定，也仍可根据这个唯一前缀判断为 ENTDAA。
    if ((tr.segments.size() > 0) &&
        (tr.segments[0] != null) &&
        tr.segments[0].header_complete &&
        (tr.segments[0].header === 8'hfc) &&
        (tr.segments[0].data.size() > 0) &&
        (tr.segments[0].data[0] === 8'h07)) begin
      tr.kind = I3C_KIND_ENTDAA;
      return;
    end

    if (tr.origin == I3C_ORIGIN_TARGET) begin
      // 当前环境中 target 主动产生 START 的协议只有 IBI。
      tr.kind = I3C_KIND_IBI;
      return;
    end

    if ((tr.origin != I3C_ORIGIN_CONTROLLER) ||
        (tr.segments.size() == 0))
      return;

    first_segment = tr.segments[0];
    if (!first_segment.header_complete)
      return;

    if ((first_segment.header[7:1] === 7'h7e) &&
        (first_segment.header[0] === 1'b0)) begin
      // 7E/W 是 broadcast CCC 前缀；出现后续 segment 说明中间发生了
      // Repeated START，因此是 direct CCC，否则是单段 broadcast CCC。
      if (tr.segments.size() > 1)
        tr.kind = I3C_KIND_DIRECT_CCC;
      else
        tr.kind = I3C_KIND_BROADCAST_CCC;
    end
    else begin
      // 非 7E/W 的 controller 发起传输按 private transfer 处理。
      tr.kind = I3C_KIND_PRIVATE;
    end
  endfunction

  function automatic void print_transfer(i3c_bus_txn tr);
    string description;

    // 这里只生成一条低 verbosity 摘要，方便从 sim.log 快速看到 monitor
    // 实际抓到了哪些段。它不参与协议判断，删除日志也不会改变功能。
    description = $sformatf(
      "captured origin=%s kind=%s segments=%0d entdaa_rounds=%0d",
      tr.origin.name(),
      tr.kind.name(),
      tr.segments.size(),
      tr.entdaa_rounds.size()
    );

    foreach (tr.segments[i]) begin
      description = {
        description,
        $sformatf(
          " | seg[%0d] start=%s header=0x%02h ninth=%b data=%p end=%s",
          i,
          tr.segments[i].start_boundary.name(),
          tr.segments[i].header,
          tr.segments[i].addr_ninth,
          tr.segments[i].data,
          tr.segments[i].end_boundary.name()
        )
      };
    end

    foreach (tr.entdaa_rounds[i]) begin
      description = {
        description,
        $sformatf(
          " | entdaa[%0d] start=%s header=0x%02h ninth=%b id_bits=%0d id=0x%016h da_bits=%0d da=0x%02h da_ack=%b end=%s",
          i,
          tr.entdaa_rounds[i].start_boundary.name(),
          tr.entdaa_rounds[i].header,
          tr.entdaa_rounds[i].header_ninth,
          tr.entdaa_rounds[i].id_bit_count,
          tr.entdaa_rounds[i].id,
          tr.entdaa_rounds[i].assigned_da_bit_count,
          {tr.entdaa_rounds[i].assigned_da,
           tr.entdaa_rounds[i].da_parity},
          tr.entdaa_rounds[i].da_ack,
          tr.entdaa_rounds[i].end_boundary.name()
        )
      };
    end

    `uvm_info("I3C_MON", description, UVM_LOW)
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      // tr 表示一笔完整 START->STOP transaction；segment 表示其中一个
      // START/Sr 地址段；entdaa_round 仅在 ENTDAA raw-bit 阶段使用。
      i3c_bus_txn       tr;
      i3c_bus_segment   segment;
      i3c_entdaa_round  entdaa_round;
      monitor_event_e   event_kind;
      entdaa_decode_e   entdaa_decode_state;
      i3c_bus_boundary_e segment_start;
      bit               reset_seen;
      bit               collecting_header;
      bit               entdaa_detected;
      longint unsigned  transfer_epoch;
      int unsigned      sampled_bit_count;
      logic [7:0]       sampled_byte;

      // 复位期间管脚变化不属于协议通信。记录开始时的 epoch，后续软件
      // 复位即使不拉低 rst_n，也能使当前 transaction 立即作废。
      wait (vif.rst_n === 1'b1);
      transfer_epoch = vif.tb_reset_epoch;
      wait_first_start(transfer_epoch, reset_seen);
      if (reset_seen)
        continue;

      tr = i3c_bus_txn::type_id::create("tr");
      // 必须在 START 刚发生时判断来源，此时能看到究竟是哪一侧拉低 SDA。
      tr.origin = infer_origin();

      // 普通 transaction 至少包含一个 START 开始的 segment。遇到 Sr 时
      // 会结束当前 segment 并新建下一个，直到 STOP 才发布整个 tr。
      segment_start = I3C_BOUNDARY_START;
      segment = create_segment("segment", segment_start);
      tr.segments.push_back(segment);

      collecting_header = 1'b1;
      entdaa_detected    = 1'b0;
      entdaa_round       = null;
      sampled_bit_count = 0;
      sampled_byte      = 'x;

      forever begin
        wait_next_event(transfer_epoch, event_kind);

        case (event_kind)
          MON_EVENT_SAMPLE: begin
            if (entdaa_round != null) begin
              // ENTDAA 仲裁字段是连续原始位流：只有 7E/R header 后有
              // ACK/NACK，assigned DA 后有 target ACK/NACK；64-bit
              // PID/BCR/DCR 内部没有“每 8 位一个第九位”。因此这里必须
              // 按 HEADER -> 64-bit ID -> DA+parity -> DA ACK 单独解码。
              unique case (entdaa_decode_state)
                ENTDAA_DECODE_HEADER: begin
                  // 先采 8-bit 7E/R header，再单独采地址 ACK/NACK。
                  if (entdaa_round.header_bit_count < 8) begin
                    entdaa_round.header[
                      7-entdaa_round.header_bit_count
                    ] = vif.sda_in;
                    entdaa_round.header_bit_count++;
                  end
                  else begin
                    entdaa_round.header_ninth  = vif.sda_in;
                    entdaa_round.header_complete = 1'b1;
                    // Header NACK 表示没有 target 参加本轮，后面不会再有
                    // ID/DA，直接等待 STOP；ACK 才继续接收 64-bit ID。
                    if (vif.sda_in === 1'b1)
                      entdaa_decode_state = ENTDAA_DECODE_WAIT_BOUNDARY;
                    else
                      entdaa_decode_state = ENTDAA_DECODE_PID_BCR_DCR;
                  end
                end

                ENTDAA_DECODE_PID_BCR_DCR: begin
                  // 64 位必须连续移入，不能每 8 位跳过一个所谓“第九位”。
                  if (entdaa_round.id_bit_count < 64) begin
                    entdaa_round.id[
                      63-entdaa_round.id_bit_count
                    ] = vif.sda_in;
                    entdaa_round.id_bit_count++;
                    if (entdaa_round.id_bit_count == 64) begin
                      entdaa_round.id_complete = 1'b1;
                      entdaa_decode_state = ENTDAA_DECODE_ASSIGNED_DA;
                    end
                  end
                end

                ENTDAA_DECODE_ASSIGNED_DA: begin
                  // Controller 发送 7-bit dynamic address 加 1-bit 奇校验。
                  if (entdaa_round.assigned_da_bit_count < 8) begin
                    if (entdaa_round.assigned_da_bit_count < 7)
                      entdaa_round.assigned_da[
                        6-entdaa_round.assigned_da_bit_count
                      ] = vif.sda_in;
                    else
                      entdaa_round.da_parity = vif.sda_in;
                    entdaa_round.assigned_da_bit_count++;
                    if (entdaa_round.assigned_da_bit_count == 8) begin
                      entdaa_round.assigned_da_complete = 1'b1;
                      entdaa_decode_state = ENTDAA_DECODE_ASSIGNED_DA_ACK;
                    end
                  end
                end

                ENTDAA_DECODE_ASSIGNED_DA_ACK: begin
                  // DA 后这一位才是 target 对地址分配结果的 ACK/NACK。
                  entdaa_round.da_ack = vif.sda_in;
                  entdaa_round.da_ack_complete = 1'b1;
                  entdaa_decode_state = ENTDAA_DECODE_WAIT_BOUNDARY;
                end

                ENTDAA_DECODE_WAIT_BOUNDARY: begin
                  // 产生 STOP/Sr 前，line controller 可能先抬高一次 SCL
                  // 再改变 SDA。这个 SCL 边沿只是边界准备，不是新的 ID 位。
                end

                default:
                  entdaa_decode_state = ENTDAA_DECODE_WAIT_BOUNDARY;
              endcase
            end
            else if (collecting_header) begin
              // 每个 segment 的前 8 位固定是 {7-bit address, RnW}，第九位
              // 是地址 ACK/NACK。这里只保存原始值，不在 monitor 中使用
              // slave_ack_addr 等激励变量生成“期望 ACK”。
              if (sampled_bit_count < 8) begin
                segment.header[7-sampled_bit_count] = vif.sda_in;
                sampled_bit_count++;
              end
              else begin
                segment.addr_ninth     = vif.sda_in;
                segment.addr           = segment.header[7:1];
                if (segment.header[0] === 1'b0)
                  segment.direction = I3C_WRITE;
                else if (segment.header[0] === 1'b1)
                  segment.direction = I3C_READ;
                else
                  segment.direction = I3C_DIRECTION_UNKNOWN;
                segment.header_complete = 1'b1;
                collecting_header       = 1'b0;
                sampled_bit_count       = 0;
                sampled_byte            = 'x;
              end
            end
            else begin
              // 普通 payload 按 8-bit data + 1 个原始第九位收集。第九位
              // 究竟是 parity T、End-of-Data T 还是 I2C ACK，由 scoreboard
              // 结合 kind、direction 和 mode 决定，monitor 不提前命名。
              if (sampled_bit_count < 8) begin
                sampled_byte[7-sampled_bit_count] = vif.sda_in;
                sampled_bit_count++;
              end
              else begin
                segment.data.push_back(sampled_byte);
                segment.data_ninth_bits.push_back(vif.sda_in);
                // resolved SDA=0 不能说明是谁拉低，所以同时保存 controller
                // 和 target 两侧的驱动状态，供 scoreboard 检查 T-bit/ACK
                // 的电气所有权，而不是只检查最终总线电平。
                segment.data_ninth_controller_low.push_back(
                  (vif.sda_oe === 1'b1) && (vif.sda_out === 1'b0)
                );
                segment.data_ninth_target_low.push_back(
                  vif.slave_drive_low === 1'b1
                );
                if (has_entdaa_prefix(tr, segment)) begin
                  // CCC code 0x07 本身仍是普通 I3C write byte，它的第九位
                  // 是 controller 发送的 parity T-bit。必须等随后的 Sr 才
                  // 切换到 ENTDAA raw-bit 解码，不能提前吞掉这个 T-bit。
                  entdaa_detected = 1'b1;
                  tr.kind         = I3C_KIND_ENTDAA;
                end
                sampled_bit_count = 0;
                sampled_byte      = 'x;
              end
            end
          end

          MON_EVENT_START: begin
            // 在 Sr 前用于准备边界的 SCL 上升沿可能已经让 bit counter
            // 暂存了一个位，但该位并不属于 payload，因此边界出现时丢弃
            // 尚未组成完整 8+1 的临时数据，避免下一段发生一位错位。
            if (entdaa_detected) begin
              // ENTDAA 中第一个 Sr 结束 CCC prefix，后续 Sr 则结束上一轮
              // 成功分配并创建下一轮 7E/R 尝试。
              if (entdaa_round == null)
                finish_segment(segment, I3C_BOUNDARY_RESTART);
              else
                finish_entdaa_round(
                  entdaa_round,
                  I3C_BOUNDARY_RESTART
                );

              entdaa_round = create_entdaa_round(
                "entdaa_round",
                I3C_BOUNDARY_RESTART
              );
              tr.entdaa_rounds.push_back(entdaa_round);
              entdaa_decode_state = ENTDAA_DECODE_HEADER;
              collecting_header   = 1'b0;
            end
            else begin
              // 普通 Direct CCC：结束前一 segment，新建以 Sr 开始的 target
              // segment，下一批 8 位重新按地址 header 解析。
              finish_segment(segment, I3C_BOUNDARY_RESTART);
              segment = create_segment("segment", I3C_BOUNDARY_RESTART);
              tr.segments.push_back(segment);
              collecting_header = 1'b1;
            end
            sampled_bit_count = 0;
            sampled_byte      = 'x;
          end

          MON_EVENT_STOP: begin
            // 与 Sr 相同，STOP 准备阶段的 SCL 边沿不提交为 payload 位。
            // 只有观察到完整 STOP 后才分类并发布，scoreboard 因而不会收到
            // 正在进行中的 transaction。
            if (entdaa_round == null)
              finish_segment(segment, I3C_BOUNDARY_STOP);
            else
              finish_entdaa_round(entdaa_round, I3C_BOUNDARY_STOP);
            classify_transfer(tr);
            print_transfer(tr);
            ap.write(tr);
            break;
          end

          MON_EVENT_RESET: begin
            // 硬/软件复位中断的 transaction 只标记 RESET 边界并丢弃，
            // 绝不能 ap.write(tr)，否则 scoreboard 会把半包配给下一条命令。
            if (entdaa_round == null)
              finish_segment(segment, I3C_BOUNDARY_RESET);
            else
              finish_entdaa_round(entdaa_round, I3C_BOUNDARY_RESET);
            `uvm_info(
              "I3C_MON_RESET",
              "reset aborted the active bus transfer; transaction discarded",
              UVM_MEDIUM
            )
            break;
          end

          default: begin
            `uvm_error("I3C_MON", "unknown internal monitor event")
          end
        endcase
      end
    end
  endtask
endclass
