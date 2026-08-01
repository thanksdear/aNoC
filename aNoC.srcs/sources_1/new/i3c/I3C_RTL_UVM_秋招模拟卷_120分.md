# I3C RTL 与 UVM 验证秋招模拟卷

> 基于当前工程代码快照设计  
> 总分：120 分　考试时间：120 分钟  
> 分值比例：设计 20 分 + 验证 80 分 + 拓展 20 分  
> 难度：中等偏难　适用方向：数字 IC 验证秋招

## 考试说明

1. 建议闭卷完成，不运行仿真、不查看源码和参考答案。
2. 选择题除特别标注外均为单选；多选题必须全部选对才得分。
3. 简答题应写出因果关系。只罗列术语但没有说明数据流、时序或检查关系，不得满分。
4. 开放题没有唯一实现，但必须满足 expected/actual 独立、复位安全、可检查和可闭合等基本原则。
5. 建议时间：设计 20 分钟，验证 80 分钟，拓展 20 分钟。

---

# 第一部分：设计与 RTL（20 分）

## 一、单项选择题（共 4 题，每题 2 分，共 8 分）

### 1. Command descriptor 计算

软件希望发起一笔 I3C private write，目标地址为 `7'h12`，长度为 2 byte。根据本项目 command descriptor 定义，写入 `CMD_PORT` 的值应为：

A. `32'h0202_4000`  
B. `32'h0224_0000`  
C. `32'h0212_0000`  
D. `32'h0248_0000`

### 2. 地址 NACK 后的 RTL 行为

`frame_scheduler` 在地址阶段完成后检测到 `ser_ack_ok==0`，正确行为是：

A. 继续发送全部 payload，最后再置位错误  
B. 立即回到 `S_IDLE`，不产生 STOP  
C. 转入 `S_STOP`，STOP 完成后产生 `xfer_nack`  
D. 清空全部 FIFO，并产生硬复位

### 3. I3C SDR write 的第九位

本项目发送 I3C SDR write 数据 `8'hA5` 时，正确的 odd-parity T-bit 为：

A. `0`，由 target 驱动  
B. `1`，由 controller 驱动  
C. `0`，由 controller 驱动  
D. `1`，由 target 驱动

### 4. 软件复位语义

关于本项目 `CTRL.sw_rst`，下列说法正确的是：

A. 软件复位会清除包括 CTRL、BUS_TIMING 在内的所有 CSR  
B. `sw_rst` 是粘滞位，必须由软件再次写 0 清除  
C. `sw_rst` 形成单周期 pulse，复位非 CSR 传输逻辑，配置 CSR 保留  
D. `sw_rst` 只复位 APB driver，不影响 DUT

## 二、填空与计算题（共 3 题，每题 2 分，共 6 分）

### 5. APB byte strobe

`BUS_TIMING_0` 复位值为 `32'h0006_0006`。随后执行一次写：

```text
PWDATA = 32'hA1B2_C3D4
PSTRB  = 4'b0101
```

写入后的 `BUS_TIMING_0` 为 `32'h________`。

### 6. 同步 FIFO

本项目 `sync_fifo` 深度为 `DEPTH`，读写指针均比地址位多 1 位。当读写指针的低地址位相等且最高位________时，FIFO 为 full；当完整读写指针________时，FIFO 为 empty。

### 7. Direct CCC 帧结构

补全本项目 Direct CCC 的总线结构：

```text
START → 7E/W → ACK → CCC_CODE → T → ________
      → {Target_DA, R/W} → ACK → Payload → STOP
```

## 三、标准简答题（共 1 题，共 6 分）

### 8. CMD-before-TX 场景分析

软件先向 `CMD_PORT` 写入一条长度为 2 的 private write 命令，此时 TX FIFO 为空；若地址被 target ACK，回答：

1. `frame_scheduler` 会停在哪一类状态，`hw_busy` 为什么仍为 1？（2 分）
2. TX 数据到达后，传输如何继续？（2 分）
3. 如果 testbench 必须等 `target_dbg_ack_phase` 从 1 变回 0 后才写第一笔 TX，为什么可能形成环形等待？（2 分）

---

# 第二部分：验证与 UVM（80 分）

## 四、选择题（共 8 题，每题 2 分，共 16 分）

### 9. UVM object 与 component

下列说法正确的是：

A. `uvm_sequence_item` 有层次结构并自动执行 `run_phase`  
B. `uvm_component` 参与层次结构和 phase，`uvm_object` 通常不参与  
C. sequence 必须在 `build_phase` 中发送 transaction  
D. factory 只能创建 component，不能创建 object

### 10. Analysis port

关于 `uvm_analysis_port`，正确的是：

A. 只能连接一个 subscriber  
B. `write()` 自带 ready/valid 反压  
C. 适合一对多广播，但发布方不能依靠它获得消费完成回执  
D. 只能在 `run_phase` 中连接

### 11. Objection

若 test 在 `run_phase` 中启动 sequence，却没有 raise objection，最可能出现：

A. factory 注册失败  
B. run phase 可能过早结束，激励和 checker 尚未完成  
C. monitor 自动转为 active  
D. transaction 随机化失败

### 12. Expected/actual 独立性

本项目检查 private read 时，最合理的 expected 数据来源是：

A. 直接复制 bus monitor 解码出的 `actual.data`  
B. 从 DUT 的 RX FIFO 层次路径读取  
C. 由 APB command 与 target 事先发布的 read plan 独立预测  
D. 从波形中人工抄录

### 13. 第九位建模

为什么 `i3c_bus_monitor` 将第九位保存成原始 `data_ninth_bits[]`，而不是统一命名为 ACK？

A. UVM 不支持 ACK 类型  
B. 第九位可能是地址 ACK、I3C parity/T、I3C read T 或 I2C ACK/NACK  
C. monitor 无法采样 SDA  
D. 只有 ENTDAA 才存在第九位

### 14. Analysis FIFO

`uvm_tlm_analysis_fifo` 在本项目中的主要价值是：

A. 将 analysis 广播转换为有缓存的消费者接口，使 scoreboard 可稍后 `get/try_get`  
B. 自动比较 expected 和 actual  
C. 自动清除 reset 前的数据  
D. 自动保证两个独立 FIFO 中事务一一对应

### 15. 多项选择：reset epoch

本项目引入 `tb_reset_epoch` 的合理作用包括：

A. 软件复位未拉低 `rst_n` 时，也能中止 monitor/target/predictor 的旧事务  
B. 防止复位前 expected 与复位后 actual 错配  
C. 代替 DUT 的全部复位逻辑  
D. 规定复位与事务到达同一时隙时“复位优先”

### 16. 多项选择：覆盖率闭合

下列做法有利于可信的 coverage closure：

A. 将 X/Z、malformed 等 checker 错误全部作为必须命中的合法功能 bin  
B. 建立 requirement—test—checker—coverpoint 映射  
C. 对不可达或 out-of-scope 的组合使用有依据的 ignore/waiver  
D. 只运行一个 full-feature test，看到总覆盖率较高即可签核

## 五、填空题（共 6 题，每题 2 分，共 12 分）

### 17. Sequence-driver 握手

sequence 侧典型调用顺序为 `________`、`________`；driver 侧对应为 `get_next_item()`、`________`。

### 18. Config DB

顶层使用 `uvm_config_db#(virtual i3c_if)::set(...)` 放入接口；component 通常在 `________ phase` 中使用相同的类型和 field name 调用 `________()` 取得接口。

### 19. 当前工程的 expected 路径

补全数据流：

```text
APB monitor ─┐
             ├→ i3c_cmd_predictor → ________ → bus scoreboard
target intent┘
```

### 20. 当前工程的 actual 路径

补全数据流：

```text
SCL/SDA → ________ → i3c_bus_txn → bus_fifo → bus scoreboard
```

### 21. Direct CCC

Direct CCC 需要两个 target intent：第一条描述 `________` 地址阶段，第二条描述 Repeated START 后的 `________` 地址阶段。

### 22. 随机回归复现

本项目通过 `+ntb_random_seed=<seed>` 固定随机种子，通过 `+________=<n>` 控制随机迭代次数。

## 六、标准简答题（共 4 题，每题 6 分，共 24 分）

### 23. Private read 验证闭环

以一笔 I3C private read 为例，按时间和数据依赖说明以下闭环：

```text
sequence / target sequence
→ 两个 driver
→ APB monitor、target intent
→ predictor expected
→ SCL/SDA bus monitor actual
→ bus scoreboard
→ RX_PORT 检查
```

回答必须说明 expected payload 与 actual payload 分别从哪里来，以及为什么不能同源。

### 24. Direct CCC 与 segment

说明 Direct CCC 为什么在 `i3c_bus_txn` 中通常表现为两个 segment。写出两个 segment 的起止边界、header 和主要 data 内容，并说明 monitor 应根据什么事实将其分类为 Direct CCC。

### 25. 两类 scoreboard 输入方式

比较当前工程中的：

- CSR 镜像 scoreboard：`uvm_analysis_imp::write()`
- 协议 scoreboard：`uvm_tlm_analysis_fifo`

说明二者在调用方式、是否可阻塞、是否缓存，以及适用检查任务上的差异。

### 26. I3C read 与 legacy I2C read 的第九位

分别说明：

1. I3C SDR read 中 controller 和 target 如何共同决定 resolved T-bit；
2. legacy I2C read 中最后一个 byte 的 ACK/NACK 由谁驱动；
3. 为什么只保存 resolved SDA 不足以判断驱动归属。

## 七、项目代码推演题（共 2 题，每题 8 分，共 16 分）

### 27. Expected/actual 到达竞态

当前协议 scoreboard 的核心逻辑可概括为：

```systemverilog
bus_fifo.get(actual);
if (!expected_fifo.try_get(expected))
  `uvm_error("I3C_SB", "actual has no predicted command")
else
  compare(actual, expected);
```

回答：

1. 即使 APB command 在总线传输前已经发出，为什么 expected 仍可能晚于 actual 发布？列举两个项目内原因。（2 分）
2. 直接把 `try_get()` 改成永久阻塞的 `get()` 有什么风险？（2 分）
3. 设计一种 reset-aware、带有限 timeout 的配对方案，写出关键伪代码或流程。（4 分）

### 28. 约束随机场景手算

#### 场景 A（4 分）

随机 private 场景为：

```text
i3c_mode              = 0
rw                    = 0
addr_ack              = 1
command_length        = 5
i2c_write_ack_count   = 2
command_before_tx     = 1
inject_parity_error   = 0
```

回答：实际应写入多少个 TX byte、总线上会尝试发送多少个 data byte、预期 response `[1:0]` 是多少，并说明原因。

#### 场景 B（4 分）

I3C private read 的 command length 为 4，target plan 只提供 2 byte 且地址 ACK。回答：最终接收多少 byte；两个数据 byte 的 resolved T-bit 依次为何值；controller/target 在第二个 T-bit 上分别是否拉低。

## 八、开放式故障定位题（共 1 题，共 12 分）

### 29. 回归中出现“假通过/级联错配”风险

某个随机 seed 的日志首先出现：

```text
I3C_SB: observed controller transfer kind=I3C_KIND_PRIVATE
        with no predicted APB command
I3C_PRED: 1 unmatched target intent(s) remain
```

后续又出现多条 payload、header 和 RX_PORT mismatch。请给出一套工程化定位方案，至少包括：

1. 你会优先检查的第一条因果链和关键日志/对象字段；（3 分）
2. 至少三类可能根因；（3 分）
3. 如何判断后续 mismatch 是独立 bug 还是第一处错配引发的级联；（2 分）
4. 你会如何改进 checker、timeout 或回归 gate，避免“报了一堆错但定位困难”以及 simulator 退出码为 0 的假通过。（4 分）

---

# 第三部分：拓展能力（20 分）

## 九、开放式架构设计题（共 2 题，每题 10 分，共 20 分）

### 30. 将当前 CSR 验证升级为 UVM RAL

当前工程使用手写 CSR 镜像 scoreboard，并通过 APB sequence 直接读写地址。请设计一个 RAL 接入方案，至少覆盖：

1. reg model、APB adapter、predictor 和 sequencer/map 的连接关系；
2. RW、RO、RW1C、自清零、volatile 状态寄存器分别如何建模和预测；
3. `CMD_PORT/TX_PORT/RESP_PORT/RX_PORT` 是否适合当作普通寄存器，为什么；
4. 如何保留独立 APB raw test，防止 RAL 与 DUT 共享同一种错误映射而“共同出错仍通过”。

### 31. 从单 target 扩展到多 target

当前 target agent 和 ENTDAA 模型主要面向单 target。若扩展到 4 个 target，并支持 ENTDAA 仲裁、动态地址分配和近同时 IBI，请给出验证平台改造方案，至少覆盖：

1. agent/config/virtual sequence 的组织；
2. target intent 与 APB command/总线 actual 的稳健匹配方式；
3. ENTDAA reference model 与仲裁结果检查；
4. IBI 仲裁和冲突场景；
5. 需要新增的 functional coverage 与负向测试。

---

# 答题后自检

- 我是否把“激励计划”与“总线实测”分开了？
- 我是否说明了第九位的协议语义和驱动归属？
- 我是否把 reset、timeout、队列残留和回归 gate 纳入验证闭环？
- 我是否只追求覆盖率数字，而没有说明合法 bin、checker 和 waiver？
- 开放题中，我是否给出了可实施的数据结构、连接或算法，而不只是口号？
