# I3C RTL 与 UVM 验证秋招模拟卷：参考答案与评分细则

> 对应试卷总分：120 分  
> 建议先完成纯试卷，再查看本文件。  
> 简答与开放题允许不同表述；只要技术含义正确、因果完整，可按得分点给分。

---

# 第一部分：设计与 RTL（20 分）

## 一、单项选择题（8 分）

### 1. B（2 分）

```text
len  = 8'h02 << 24 = 32'h0200_0000
addr = 7'h12 << 17 = 32'h0024_0000
rw/is_ccc/is_direct = 0
结果 = 32'h0224_0000
```

### 2. C（2 分）

地址 NACK 后进入 `S_STOP`。STOP 完成时，先前锁存的 `nack_r` 使 `xfer_nack` 产生一个 pulse。

### 3. B（2 分）

`8'hA5` 有 4 个 1，`^A5=0`。为了形成 odd parity，第九位应为 `!^A5=1`，并由 controller 在 I3C write PP 阶段驱动。

### 4. C（2 分）

`sw_rst` 在 CSR 内自清零，只作为单周期 pulse；`int_rst_n = PRESETn & ~sw_rst` 复位传输路径和 FIFO 等非 CSR 逻辑，配置 CSR 由 `PRESETn` 控制而保留。

## 二、填空与计算题（6 分）

### 5. `00B2_00D4`（2 分）

`PSTRB[0]` 更新低 byte 为 `D4`，`PSTRB[2]` 更新 `[23:16]` 为 `B2`，其余 byte 保留复位值。

### 6. 不同；相等（2 分）

每空 1 分。更准确地说，低地址位相同、回绕位不同表示 full；完整指针相等表示 empty。

### 7. Repeated START / Sr（2 分）

写作 `Sr`、Repeated START 或重复起始条件均可。

## 三、标准简答题（6 分）

### 8. CMD-before-TX

1. 地址 ACK 后进入 `S_DATA_WR`；因为 TX FIFO 为空，`tx_valid=0`，scheduler 不发下一条 serializer byte command。Dispatch 仍处于 `DS_RUN`，因此 `hw_busy=1`。（2 分）
2. 软件写 `TX_PORT` 后 TX FIFO 非空，`tx_valid=1`；scheduler 发数据 byte，serializer/line controller 完成 8+1 位，`tx_ready` 消耗 TX 数据，继续下一 byte 或 STOP。（2 分）
3. target 通常要到后续安全的 SCL low/下降沿才释放 ACK 驱动；RTL 又在没有 TX 数据时不产生下一数据 bit 的 SCL 周期。test 等 ACK phase 清零才写 TX，RTL 等 TX 才产生让 ACK phase 清零的 SCL，形成互等。（2 分）

---

# 第二部分：验证与 UVM（80 分）

## 四、选择题（16 分）

### 9. B（2 分）

component 有父子层次并参与 UVM phase；transaction、sequence、配置对象等属于 object 体系。

### 10. C（2 分）

analysis port 支持零到多个订阅者广播，没有 ready/valid 回执语义。

### 11. B（2 分）

如果没有其他 objection，run phase 可能很快结束，sequence、monitor 或 scoreboard 常驻线程来不及完成。

### 12. C（2 分）

expected read payload 应来自 target 在驱动总线前发布的 plan，并结合 APB command 预测；actual 来自 SCL/SDA monitor。

### 13. B（2 分）

第九位的语义依赖地址/数据、读写方向、I3C/I2C 模式及传输类型，monitor 应先记录事实，由 scoreboard 解释。

### 14. A（2 分）

analysis FIFO 提供 `analysis_export` 接收广播，并缓存 transaction 供消费者稍后取得；它不会自动配对或比较。

### 15. A、B、D（2 分）

全部选对得 2 分，否则 0 分。epoch 是 TB 的跨线程同步机制，不能代替 DUT 复位。

### 16. B、C（2 分）

全部选对得 2 分，否则 0 分。异常 decoder coverage 可以单独统计，但不应伪装成合法功能 closure 的 required bin。

## 五、填空题（12 分）

### 17. `start_item()`；`finish_item()`；`item_done()`（2 分）

三空全对 2 分；对两空 1 分。

### 18. `build_phase`；`get`（2 分）

每空 1 分。

### 19. `i3c_expected_op` / `expected_ap → expected_fifo`（2 分）

写出 predictor 输出的 expected 对象及进入 `expected_fifo` 的含义即可。

### 20. `i3c_bus_monitor`（2 分）

写 `passive bus monitor` 也可。

### 21. 7E/W 广播；target DA（2 分）

每空 1 分。第二空应体现 `{target_addr, rw}`。

### 22. `RAND_ITERS`（2 分）

## 六、标准简答题（24 分）

### 23. Private read 验证闭环（6 分）

参考得分点：

1. APB/controller sequence 向 APB sequencer 发送配置、CMD 和后续 RX_PORT 读；target sequence 向 target sequencer 发送 ACK、方向和 read data plan。（1 分）
2. APB driver 把 `i3c_txn` 转成 APB setup/access；target driver 根据配置通过 OD 方式响应地址并发送读数据/T-bit。（1 分）
3. APB monitor 观察已完成的 APB 访问；target driver 在驱动前发布独立 `i3c_target_intent`。（1 分）
4. predictor 解码 CMD，将 command length/address/mode 与 target intent 组合成 `i3c_expected_op`；expected payload 来自 intent，不来自总线。（1 分）
5. passive bus monitor 只从 SCL/SDA 边界和采样位构造 `i3c_bus_txn` actual；bus scoreboard 比较 header、ACK、payload、T-bit、边界。（1 分）
6. scoreboard 将独立预测的 read data 放入 `expected_rx_q`，再与 APB monitor 观察到的 RX_PORT 数据比较；若用 actual.data 生成 expected，DUT 总线与 RX FIFO 同时出错时可能自证通过。（1 分）

### 24. Direct CCC 与 segment（6 分）

参考得分点：

1. Segment 0：`START → 7E/W → ACK → CCC code/T`，起点为 START，终点为 RESTART。（2 分）
2. Segment 1：`Sr → {target DA,RW} → ACK → payload`，起点为 RESTART，终点为 STOP。（2 分）
3. monitor 根据总线实际观察到的第一段 header 为 7E/W，且存在后续 segment/Repeated START，将其分类为 Direct CCC；不能读取 sequence 的预期类型强制分类。（2 分）

若只写“因为有两个地址”但没有边界和内容，最多 2 分。

### 25. 两类 scoreboard 输入方式（6 分）

参考得分点：

1. `analysis_imp` 的 `write()` 是发布方 `ap.write()` 时直接回调；一个 imp 对应一个实现对象。（1 分）
2. `write()` 是 function，不能包含阻塞等待或时序控制；适合即时、轻量、确定性的镜像更新和读比较。（1 分）
3. 当前 CSR scoreboard 在 callback 中按 PSTRB 更新镜像，并对稳定可读 CSR 做带 mask 比较。（1 分）
4. `uvm_tlm_analysis_fifo` 通过 `analysis_export` 接收广播并缓存 transaction。（1 分）
5. 消费线程可在 task 中 `get/try_get`，可以等待另一路数据、reset 或 timeout，适合跨来源配对。（1 分）
6. FIFO 不会自动保证 expected/actual 对齐，仍需 scoreboard 设计顺序、ID、epoch、timeout 和残留检查。（1 分）

### 26. I3C read 与 I2C read 第九位（6 分）

参考得分点：

1. I3C read 的 T-bit 为 OD/wired-AND 结果：target 有更多数据时释放/发送 1，结束时拉低；controller 未达到本地长度时释放，达到最后一个请求 byte 时可拉低结束。（2 分）
2. 任一方拉低，resolved T 为 0；只有双方都释放才为 1。（1 分）
3. legacy I2C read 的第九位由 controller 驱动：中间 byte ACK=0，最后 byte NACK=1；target 释放。（1 分）
4. resolved SDA 只有最终 0/1，无法区分是 controller、target 还是双方拉低，因此当前 TB 额外记录各方 low contribution；更可复用的黑盒 checker 则需要用协议上下文推断并把白盒归属检查分层。（2 分）

## 七、项目代码推演题（16 分）

### 27. Expected/actual 到达竞态（8 分）

#### 1. expected 可能晚到的原因（2 分）

任写两项，每项 1 分：

- predictor 在等待对应 target intent；
- CMD-before-TX 时 predictor 的 `bind_write_data()` 等待 TX_PORT 数据；
- predictor 与 bus monitor/scoreboard 是并行线程，analysis FIFO 调度和 delta-cycle 顺序不构成严格先后保证；
- 软件复位/epoch 变化使旧预测被丢弃；
- intent 发布顺序错误或 predictor 被前一命令阻塞。

#### 2. 永久阻塞 `get()` 的风险（2 分）

- expected 永远缺失时 scoreboard 卡死，无法及时报告根因；（1 分）
- 若 test objection 不结束或 checker 线程等待无退出条件，会形成仿真 hang；复位时还可能误取下一 epoch 的 expected。（1 分）

#### 3. reset-aware 有限等待方案（4 分）

一种参考伪代码：

```systemverilog
epoch = vif.tb_reset_epoch;
got_expected = 0;

fork : WAIT_EXPECTED
  begin
    expected_fifo.get(expected);
    got_expected = 1;
  end
  begin
    repeat (MAX_WAIT_CYCLES) @(posedge vif.clk);
  end
  begin
    wait (vif.rst_n !== 1'b1 ||
          vif.tb_reset_epoch != epoch);
  end
join_any
disable WAIT_EXPECTED;

if (vif.tb_reset_epoch != epoch || vif.rst_n !== 1'b1)
  discard_actual_as_reset_aborted();
else if (!got_expected)
  report_missing_expected_with_actual_summary();
else if (expected.reset_epoch != epoch)
  report_or_discard_stale_expected();
else
  compare(actual, expected);
```

评分点：

- 同时等待 expected、timeout 和 reset/epoch 三类事件；（1 分）
- 明确 timeout 有限，超时报告 actual kind/header/队列状态；（1 分）
- reset 优先并检查 expected epoch；（1 分）
- 说明配对仍应结合 command ID/顺序，且在 `check_phase` 检查残留，避免静默丢包。（1 分）

使用 timestamp/event/关联数组实现同等语义也可满分。

### 28. 约束随机场景手算（8 分）

#### 场景 A（4 分）

- TX_PORT 写入 3 个 byte。（1 分）
- 总线尝试发送 3 个 data byte。（1 分）
- response `[1:0] = 2'b10`。（1 分）
- target 先 ACK 2 个 I2C write data byte，随后第 3 个 byte 的第九位 NACK；controller 因此提前 STOP，不应为未发送的第 4、5 byte 消耗 TX 数据。`command_before_tx=1` 只改变 CMD/TX 到达顺序，不改变最终发送数量。（1 分）

#### 场景 B（4 分）

- 最终接收 `min(command_length,target_length)=2` byte。（1 分）
- 第一个 resolved T 为 1：双方都愿意继续，均释放。（1 分）
- 第二个 resolved T 为 0。（1 分）
- 第二个 byte 处 target 因无更多数据拉低；controller 尚未达到自己的第 4 byte 上限，因此释放、不拉低。（1 分）

## 八、开放式故障定位题（12 分）

### 29. 回归定位

没有唯一答案，参考评分如下。

#### 1. 第一条因果链（3 分）

- 从第一条 `actual has no predicted command` 开始，不先追最后一条 payload mismatch。（1 分）
- 对齐 APB monitor 的 CMD_PORT 记录、descriptor、PSTRB、reset epoch、predictor command ID/queue、target intent kind/address/direction，以及 bus monitor actual origin/kind/header。（1 分）
- 使用同一 test、seed、commit、工具版本重现，必要时开启 transaction print/波形并标记各对象到达时间。（1 分）

#### 2. 可能根因（3 分）

任写三类且合理，每类 1 分：

- CMD_PORT 写的 `PSTRB != 4'hf`，DUT/predictor接受条件不一致；
- predictor 等待 TX 或 target intent，expected 晚于 actual；
- target intent 类型、地址、方向或发布顺序错误；
- reset epoch 在事务中变化，旧 expected 被正确丢弃但 actual 被错误发布；
- bus monitor 错判 START/STOP、origin 或将一笔事务拆成错误数量的 segment；
- sequence 未正确协调两个 active agent，target 配置晚到；
- analysis 连接缺失、factory 创建错误或消费者线程未运行；
- 前一命令残留导致 FIFO 顺序整体错位。

#### 3. 判断级联（2 分）

- 修复或隔离第一处缺 expected 后，用相同 seed 重跑；若后续 mismatch 消失，则是级联。（1 分）
- 也可按 command ID/epoch/时间戳划分事务；第一处丢失后严格 FIFO 配对的后续错误应先降级为“unmatched/tainted”，不要把每个字段都当独立 DUT bug。（1 分）

#### 4. 平台改进（4 分）

合理措施每项 1 分，最多 4 分：

- expected/actual 使用 reset-aware timeout，并在错误中打印两侧 FIFO 深度、epoch、command ID、header；
- 引入事务 ID、epoch、kind/address 等 key 或至少“首错后停止字段级比较”的 taint 机制；
- `check_phase` 强制检查 expected、actual、intent、RX、response、TX 残留；
- 回归脚本不仅看进程退出码，还解析 `UVM_ERROR/UVM_FATAL`、checker summary 和 timeout；
- 保存 test、seed、commit/diff hash、工具版本和首错摘要；
- 做 predictor/monitor/checker 单元测试与故障注入，证明 checker 会抓错；
- 为裸 `wait` 设置 timeout/reset 退出路径。

仅回答“看波形”最多 1 分。

---

# 第三部分：拓展能力（20 分）

## 九、开放式架构设计题（20 分）

### 30. UVM RAL 接入（10 分）

参考得分点：

1. 建立 `uvm_reg_block`、各 `uvm_reg`/field、address map；将 APB sequencer 设为 map sequencer，并配置 `uvm_reg_adapter` 完成 `uvm_reg_bus_op ↔ i3c_txn` 转换。（2 分）
2. 显式预测可由 `uvm_reg_predictor#(i3c_txn)` 接 APB monitor，adapter 将 observed APB 转为 bus op；若使用 auto-predict，应说明不能再重复显式预测。（1 分）
3. RW/RO 正确设置 access 与 reset；RW1C 建模写 1 清零语义；`sw_rst` 建模为自清零/写后预测回 0；STATUS、IBI/ERR、ENTDAA 等硬件更新字段设 volatile，并制定 mirror/predict 策略。（2 分）
4. 对异步硬件置位的 RW1C 字段，不能只依赖 frontdoor 写预测；应由 monitor/专用 predictor 或协议事件更新 mirror，并在读后校验。（1 分）
5. FIFO port 具有 push/pop 副作用和队列语义，不适合当作普通可 mirror 的稳定寄存器；可用 frontdoor sequence、user-defined reg/field callback，或继续保留专用 FIFO model/checker。（1 分）
6. 保留 raw APB test，独立验证 setup/access、PREADY/PSLVERR、PSTRB、未对齐/非法地址和寄存器真实地址；RAL test 验证寄存器语义。（1 分）
7. 使用独立 spec/CSV 或手工审查地址表，避免 DUT 与 RAL 从同一份错误 RTL 定义“共同正确”；加入 address decode/bit-bash/reset test 与少量硬编码 golden address smoke test。（2 分）

只写“使用 RAL 自动验证寄存器”最多 2 分。

### 31. 多 target 扩展（10 分）

参考得分点：

1. 每个 target 使用独立 agent/config，包含 static address、PID/BCR/DCR、动态地址状态、IBI 能力；virtual sequencer 持有 target sequencer 数组，virtual sequence 协调 controller 与多个 target。（2 分）
2. 电气层将多个 target 的 OD low contribution做 wired-AND/OR-of-low 解析，并增加 contention/ownership checker；不要让多个 agent直接覆盖同一变量。（1 分）
3. intent 不再只靠单一 FIFO 顺序盲配；至少携带 target ID、command ID/epoch、阶段和地址，使用关联表/队列按 transaction key 配对，同时处理多个 target 对 broadcast 的共同响应。（2 分）
4. ENTDAA reference model 按参与 target 的 PID/BCR/DCR 仲裁优先级计算每轮获胜者，维护 DAT 分配、已分配集合和 final 7E/R NACK；比较每轮 ID、DA/parity、ACK、动态地址生效时刻。（2 分）
5. IBI 覆盖单请求、近同时请求、仲裁获胜/失败、busy bus 后延迟、重复请求、MDB 能力与 NACK/retry；检查未获胜 target 释放/重试行为。（1 分）
6. coverage 至少包括 target 数量、仲裁顺序、动态地址范围/冲突、成功/DA NACK/DAT exhausted、IBI 请求组合与获胜者、private/CCC 使用 static/dynamic address 的交叉。（1 分）
7. 负向测试包括重复 PID/地址、非法/保留 DA、错误 parity、错误 target ACK、多个 target 非法同时 PP 驱动、reset 中断仲裁、intent 缺失/重复；每类必须有 checker 和预期错误策略。（1 分）

只回答“复制 4 个 target agent”最多 2 分。

---

# 成绩解释

| 得分 | 参考判断 |
|---:|---|
| 105–120 | 秋招项目表达和验证闭环较扎实，重点训练限时表达与真实 debug 案例 |
| 90–104 | 基础较完整，仍有少数架构、协议细节或工程闭环缺口 |
| 72–89 | 能读懂平台，但 expected/actual、reset、coverage 或协议语义尚未完全串联 |
| 60–71 | 基础概念有印象，项目数据流与 checker 设计需要系统复盘 |
| 0–59 | 建议从 APB UVC、private transfer 闭环和 scoreboard 独立性重新搭主线 |

总分包含 20 分拓展题。若只评价当前项目内能力，也可以单独查看前 100 分得分。

# 查漏补缺诊断矩阵

| 能力项 | 对应题号 | 满分 |
|---|---|---:|
| RTL/CSR/FIFO/状态机 | 1、2、4、5、6、8 | 14 |
| I3C/I2C/CCC 协议细节 | 3、7、13、21、24、26、28B | 18 |
| UVM 基础机制 | 9、10、11、14、17、18、25 | 16 |
| Predictor/scoreboard/独立性 | 12、19、20、23、27、29 | 36 |
| 约束随机与可复现回归 | 22、28A、29 | 10 |
| reset、timeout 与鲁棒性 | 8、15、27、29 | 16 |
| Coverage 与验证闭环 | 16、29、31 | 8 |
| RAL 与平台扩展 | 30、31 | 20 |

矩阵中的题目可能同时考察多个能力项，因此各行分数不能直接相加为 120。建议按题目实得分比例判断：

- 低于 60%：优先补课并手写最小例子；
- 60%–80%：结合当前项目重新走读并做一次故障注入；
- 高于 80%：准备面试中的追问、取舍与替代方案。

# 推荐复盘方式

1. 第一次严格计时，只写自己真正理解的内容。
2. 对照评分点用另一种颜色自评，不因“意思差不多”自动给满分。
3. 将每道失分题归因于：概念不清、项目代码不熟、协议不熟、表达不完整或时间不足。
4. 对项目题回到代码中找到 stimulus、monitor、predictor、checker、coverage 五个入口。
5. 对最早的三个知识缺口，各做一次“解释 + 小修改 + 故障注入 + 回归复验”。
