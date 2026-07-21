# I3C UVM 学习路线与验收标准

> 目标：以当前 I3C controller 项目为载体，形成能够用于 IC 验证求职展示的、可复现的 UVM 验证闭环。
>
> 当前基线日期：2026-07-21。当前 Git HEAD 为 `ba8d3fd`，但工作区包含未提交修改，因此后续每次验收都必须同时记录 commit、`git status --short` 和源码 diff hash。

## 1. “完成”和“掌握”的证据等级

以后不再用“代码写了”代替“验证通过”，统一采用以下等级：

| 等级 | 必须具备的证据 | 允许使用的结论 |
|---|---|---|
| L0 未开始 | 没有对应代码或练习 | 未开始 |
| L1 已接触 | 有源码、笔记或定向测试入口 | 已接触/已编写 |
| L2 已实现 | 当前源码能够干净编译，结构和连接完整 | 已实现 |
| L3 已验证 | 与当前 commit/dirty diff 绑定的仿真日志中 `UVM_ERROR=0`、`UVM_FATAL=0`，checker 无残留 | 已验证通过 |
| L4 已掌握 | 满足 L3；能独立解释数据流；能完成一次修改和故障注入，并用回归证明 checker 会抓错 | 已掌握 |
| L5 可签核 | 多 seed 回归稳定；required coverage 闭合；所有未命中项有测试或 waiver；结果可复现 | 可作为项目阶段签核 |

个人主观感受、测试类数量、日志文件“存在”都不能单独作为 L3/L4 证据。日志必须与当前源码版本、工具版本、test、seed 对应。

## 2. 项目完成定义（Definition of Done）

一次功能或知识点只有同时满足以下条件才算完成：

1. 有明确 requirement ID、协议预期和 checker 位置。
2. 当前源码完整编译，编译日志为 0 error。
3. 至少一个正向测试通过，日志中 `UVM_ERROR=0`、`UVM_FATAL=0`。
4. 至少一个反向实验能触发预期 checker，证明不是“没有检查所以通过”。
5. scoreboard 的 `check_phase` 没有 expected、actual、APB、IBI 或 RX 数据残留。
6. 对应 functional coverage required bin 被命中，或给出合理 waiver。
7. 记录工具版本、commit、test、seed、命令、日志和覆盖率报告路径。
8. `progress-log.md` 更新学习过程，`weekly-report.md` 更新阶段结论。

## 3. “完整 I3C 验证”的范围

“完整”必须相对于 DUT specification，而不是笼统宣称覆盖全部 MIPI I3C 标准。当前第一阶段项目范围按现有 RTL 定义为：

- APB CSR、FIFO、byte strobe、状态和中断。
- I3C SDR private read/write、地址 ACK/NACK、读写 T-bit。
- legacy I2C private read/write、数据 ACK/NACK。
- Broadcast CCC、Direct CCC、Repeated START。
- 单 target ENTDAA。
- IBI 无 MDB 和单 MDB。
- 硬复位、软件复位、命令/TX 到达顺序和 FIFO 边界。
- 总线 timing 配置及实际 SCL/SDA 时序检查。

当前 RTL 未实现的协议能力，必须列为 out-of-scope 或先扩展设计，不能只靠增加 test 宣称已验证。

## 4. 分阶段学习路线

### 阶段 0：建立可信、可复现的基线

学习目标：掌握 filelist、编译/运行分离、工具链、日志 gate 和证据管理。

任务：

- 修复当前 UVM 编译阻断，例如 `tb/env/i3c_scoreboard.sv` 中被拆开的 `apply_target_intent` 函数名。
- 配置可用的 VeriSim/VeriCov 或 VCS/URG；当前 Makefile 指向的 `../../../uvm-1.2` 不存在，需要把 `UVM_HOME` 指向可用的 UVM 1.2。
- 固定工具版本、源码 commit、默认 seed 和输出目录。
- 回归脚本不能只看 simulator 退出码，还要解析每个日志的 UVM report summary。
- 保存 compile log、每个 test log、机器可读 summary 和 coverage 报告。

验收：

- `make compile` 返回 0，模拟器 summary 为 0 error；同时定义并执行项目的 warning gate，不能只靠大小写敏感的文本搜索。
- 当前 23 项 `REGRESSION_TESTS` 全部有新日志，且 `UVM_ERROR=0`、`UVM_FATAL=0`。
- `i3c_full_feature_test` 单独通过，但不把它当成 23 项回归的替代品。
- 任何失败都能通过 `TEST + SEED + commit + tool version` 重现。

### 阶段 1：UVM 基础骨架与 APB UVC

学习目标：transaction、factory、sequence、sequencer、driver、monitor、agent、phase、objection、config DB、virtual interface。

当前源码入口：

- `tb/env/i3c_agent/i3c_txn.sv`
- `tb/env/i3c_agent/i3c_seq.sv`
- `tb/env/i3c_agent/i3c_driver.sv`
- `tb/env/i3c_agent/i3c_monitor.sv`
- `tb/env/i3c_agent/i3c_agent.sv`
- `tb/test/i3c_base_test.sv`

验收：

- 能独立画出 `sequence -> sequencer -> driver -> interface -> monitor` 数据流。
- 能解释 `start_item/finish_item` 与 `get_next_item/item_done` 的对应关系。
- 能新增一条 APB corner test，不复制现有 sequence，并通过回归。
- 能故意制造 APB 数据或 strobe 错误，让 scoreboard 准确报错。
- driver/monitor 对 APB handshake 和 `PSLVERR` 有明确检查策略。

### 阶段 2：TLM、predictor 与 scoreboard

学习目标：analysis broadcast、`uvm_tlm_analysis_fifo`、`uvm_tlm_fifo`、生产者/消费者、actual/expected 独立性、reset-safe 配对。

当前源码入口：

- `tb/env/i3c_env.sv`
- `tb/env/i3c_scoreboard.sv`
- `tb/env/i3c_target_model.sv`
- `tb/env/i3c_bus_agent/i3c_bus_monitor.sv`

验收：

- 能说明 `command_fifo.put/get` 与 `expected_ap.write -> analysis_fifo` 的差异。
- 能从 APB CMD/TX 和 target intent 追踪出一条 `i3c_expected_op`。
- 能从 SCL/SDA 追踪出一条 `i3c_bus_txn`，并说明二者为什么必须独立。
- 修复 `expected_fifo.try_get()` 的潜在到达竞态，采用 reset-aware、带 timeout 的配对策略。
- 对 payload、地址 ACK、T-bit 各做一次故障注入，checker 都能抓到且无级联错配。
- 将 1900 行 scoreboard 按 expected object、predictor、CSR scoreboard、bus scoreboard 拆分，功能回归保持不变。

### 阶段 3：I3C/I2C 协议场景闭环

学习目标：把协议 requirement 转换成 stimulus、monitor decode、reference model、checker 和 coverage。

建议顺序：

1. Private write/read、地址 NACK、controller/target 提前结束。
2. legacy I2C 数据 ACK/NACK 与 I3C T-bit 的区别。
3. Broadcast CCC。
4. Direct CCC 与 Repeated START。
5. ENTDAA。
6. IBI。
7. reset、IRQ、FIFO 边界、错误注入和 timing。

验收：

- 每项 requirement 都能在“test/sequence、monitor、scoreboard、coverpoint”四处找到对应证据。
- timing test 实际测量 SCL high/low 和 SDA hold，而不是只读写 timing CSR。
- polling test 真正采用 polling 流程，而不是直接继承 private-write body。
- 覆盖 Direct CCC length 2、ENTDAA/IBI 失败路径、busy bus、NACK、错误 parity/T-bit。
- 所有无限 `wait` 都有 timeout 或 reset 退出路径。

### 阶段 4：约束随机、回归与覆盖率闭合

学习目标：constraint、randomize、seed、可复现失败、coverage-driven verification。

当前缺口：`i3c_txn` 虽有 `rand/constraint`，工程内没有实际 `randomize()` 调用，当前测试仍是定向测试。

验收：

- 新增约束随机 multi-command/FIFO-boundary/reset-stress sequence。
- 固定 seed 能重现失败；随机回归至少 100 seeds 无非预期错误。
- 建立 requirement -> test -> coverpoint -> result 矩阵。
- coverage 只把合法功能点计入 closure；unknown、X/Z、malformed、missing/extra 等改为 illegal/ignore，或放进独立 fault-injection coverage。
- required functional bins 100% 命中；其余合法 bin 未命中必须有测试或 waiver。
- 保存 code coverage 和 functional coverage 报告，不只报告一个总百分比。

### 阶段 5：求职级验证平台能力

学习目标：可复用 UVC、RAL、virtual sequence、factory override、SVA、自动化回归和问题定位。

验收：

- 将 target BFM 拆成 target agent/config/driver，避免 APB sequence 直接 bit-bang IBI。
- bus monitor 的核心协议判断只依赖 SCL/SDA；TB 内部驱动归属信号作为可选 debug checker。
- 引入 virtual sequencer/virtual sequence 协调 APB 与 target 两侧激励。
- 使用 UVM RAL 验证 CSR reset/access/W1C，并保留少量独立 APB raw test。
- 加入 timing、START/STOP、总线稳定性和关键协议 SVA。
- 至少展示一个 factory override 实例和一个可复现 bug 的完整 debug 报告。
- README 能让新环境按步骤完成 compile、single test、regression、coverage。

## 5. 当前阶段评估（2026-07-21）

| 阶段 | 当前证据状态 | 结论 |
|---|---|---|
| 0 可复现基线 | 未找到可用的动态模拟/覆盖工具；Makefile 配置的 UVM 路径不存在；无日志/覆盖率；UVM 源码有语法阻断 | 阻塞 |
| 1 UVM/APB 骨架 | component、phase、config DB、seq/driver/monitor 和定向测试均有源码 | L1，待当前版本仿真验收 |
| 2 TLM/scoreboard | analysis/TLM FIFO、predictor、actual/expected、reset epoch 均已编码 | L1，存在编译错误和配对竞态 |
| 3 协议场景 | 22 个 feature sequence，覆盖 private/I2C/CCC/ENTDAA/IBI/reset/IRQ | L1，当前无通过日志 |
| 4 随机/coverage closure | 9 个 covergroup 已编写；无 randomize、无 coverage report | L1，未闭环 |
| 5 求职级架构 | 尚无 RAL、SVA、virtual sequence、target UVC、factory override 用例 | 未开始/早期 |

当前处于“广泛定向功能已编码，尚未建立可信回归闭环”的阶段。优先级必须从继续堆功能，切换到编译、回归、checker 灵敏度和 coverage 证据。

## 6. 每次学习和每周更新规则

每次学习结束更新 `progress-log.md`：

- 今天学习的概念。
- 实际修改的文件和行号。
- 执行的命令、test、seed。
- 日志中的通过/失败证据。
- 尚未理解的问题和下一步。

每周由 Codex 更新 `weekly-report.md`：

- 先检查当前代码、Git 状态、编译日志、全部 test 日志和 coverage 报告。
- 没有当前版本产物时必须写“未知/待复验”，不得沿用旧截图数字。
- 只把达到相应证据等级的项目升级状态。
- 保留失败记录，修复后链接新的复验结果，不删除问题历史。
