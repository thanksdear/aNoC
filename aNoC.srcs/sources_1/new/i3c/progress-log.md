# I3C UVM 学习进度日志

> 记录原则：学习内容可以记录主观理解，但“编译通过、测试通过、覆盖率达到多少”必须引用当前版本的实际命令输出、日志或报告。

## 2026-07-21：建立证据化学习基线

### 本次检查快照

- 执行目录：`/mnt/d/aNoC/aNoC/aNoC.srcs/sources_1/new`
- Git HEAD：`ba8d3fd`
- `i3c/rtl` 与 `i3c/tb` 有 19 个已跟踪文件发生修改。
- 上述两个源码目录的 `git diff` SHA-256：`e2636dd96bfc3f18e131b88a44cbb3ddea273e7558b29df86f12b22f214b66f5`。
- Slang：`slang version 11.0.0+7ddf4059f`。

该 hash 只绑定本次检查的 RTL/TB 脏源码；三个学习文档未计入，避免更新文档时改变源码证据标识。

### 本次学习内容

- 理解 `process_apb()` 和 `process_commands()` 是通过 `command_fifo` 解耦的生产者/消费者线程。
- 区分三类 FIFO/队列：SystemVerilog queue、`uvm_tlm_fifo`、`uvm_tlm_analysis_fifo`。
- 理解 `expected_ap.write()` 是发布接口，连接到 `bus_sb.expected_fifo.analysis_export` 后仍由 FIFO 缓存。
- 跟踪 Private transfer 的比较层次：`process_bus -> compare_expected_transfer -> compare_private -> compare_payload -> check_*_byte`。
- 识别 actual/expected 最终配对的同步假设：`bus_fifo.get(actual)` 会等待，而 `expected_fifo.try_get(expected)` 不会等待。

以上内容目前记为“已学习/能够跟踪代码”，尚未自动升级为 L4“已掌握”；仍需独立修改、故障注入和当前版本回归证明。

### 项目源码盘点结果

- 已有 24 个 test class：1 个 base、22 个 feature test、1 个 `full_feature_test`。
- Makefile 的 `REGRESSION_TESTS` 有 23 项，包含 base，不包含 `full_feature_test`。
- 已有 23 个 sequence class（包含基础 `i3c_seq`）。
- 已有 9 个 functional covergroup、48 个 coverpoint、13 个 cross。
- 已实现 APB active agent、被动 I3C bus monitor、target model、predictor、CSR scoreboard、bus scoreboard 和两类 coverage subscriber。
- 已编码 Private、legacy I2C、Broadcast/Direct CCC、ENTDAA、IBI、reset、IRQ 等定向场景。

这些数字只证明源码入口存在，不证明测试已经运行通过。

### 本次实际检查结果

以下命令均在上述执行目录运行。输出只记录在本日志和本次 Codex 会话中，尚未另存为独立 lint log。

1. RTL 顶层静态检查：

   ```bash
   slang --lint-only --top i3c_top i3c/rtl/*.sv
   ```

   ```text
   Build succeeded: 0 errors, 0 warnings
   ```

2. 非 UVM 单元顶层静态 elaboration：

   ```bash
   slang --lint-only --timescale 1ns/1ps --top tb_i3c_top \
     i3c/rtl/*.sv i3c/tb/unit/tb_i3c_top.sv
   ```

   ```text
   Build succeeded: 0 errors, 0 warnings
   ```

   ```bash
   slang --lint-only --timescale 1ns/1ps --top tb_sync_fifo \
     i3c/rtl/sync_fifo.sv i3c/tb/unit/tb_sync_fifo.sv
   ```

   ```text
   Build succeeded: 0 errors, 0 warnings
   ```

   这只能证明 RTL 和单元 TB 能通过静态 elaboration，不代表单元仿真实际运行到 `TEST PASSED`。

3. 本次会话曾使用临时 UVM macro stub 辅助 Slang `--parse-only`，发现源码阻断：

   ```systemverilog
   // tb/env/i3c_scoreboard.sv:505
   function void apply_target _intent(
   ```

   调用处使用的是 `apply_target_intent(...)`。临时 stub 已删除、没有作为项目证据保存；
   该检查不可替代真实 UVM 编译。不过，上述带空格的函数声明可直接从当前源码复核，
   本身就是确定的 SystemVerilog 语法错误，因此当前源码不能认定 UVM 编译通过。

4. 当前环境和证据产物：

   - 检查 `verisim/vericov/vcs/urg/iverilog/verilator/xrun/vsim/xsim` 后均未找到；可用的是 Slang 静态编译器，另有 `svls` 语言服务器，但它们都不是动态模拟器。
   - Makefile 默认的 `../../../uvm-1.2` 在当前工作区不存在；本次未证明整台机器任意位置都不存在 UVM 1.2。
   - `i3c/tb/sim` 下没有 `log/`、simulation image、`verisim.zdb`、`cov.txt` 或 LCOV 报告。
   - 当前没有任何 test 能依据现存日志标为“当前版本通过”，覆盖率数值为未知。

### 已确认的问题和薄弱环节

- `apply_target _intent` 是当前 UVM 编译的确定阻断。
- `expected_fifo.try_get()` 假设 expected 一定早于 actual；缺少 reset-aware timeout 配对，存在到达竞态风险。
- `polling_access_seq` 没有自己的 body，只是复用 private write，尚未真正验证 polling。
- timing/timing-sweep sequence 主要写读 CSR，没有测量实际 SCL high/low 和 SDA hold。
- `i3c_txn` 有 `rand/constraint`，但全工程没有 `randomize()`，尚未形成约束随机回归。
- coverage 中把 unknown、X/Z、null、incomplete、malformed、bad parity 和部分不可达状态作为普通 bins，当前不能用 100% 作为合理 closure 目标。
- target model 和 bus monitor 使用较多 TB 内部 sideband，当前更接近 white-box 学习平台，复用性不足。
- APB driver/monitor 没有采集或检查 `PSLVERR`，错误响应路径尚未闭环。
- 当前 target model 固定单 target，read plan 只支持 1～4 byte，IBI 只覆盖无 MDB/单 MDB；这是当前学习平台的子集范围，不是完整 MIPI I3C 能力。
- Makefile 回归只依据 simulator 退出码，没有强制解析 `UVM_ERROR/UVM_FATAL`；存在假通过风险。

### 历史失败线索（不作为当前版本证据）

- 旧截图中的 `i3c_full_feature_test` 曾显示 `UVM_ERROR : 28`，包含 APB STRB、payload、地址 NACK、无对应 APB command 和 RX_PORT 等错误。
- 旧 URG 截图出现过 `Design not yet loaded`。
- 这些原始日志和 VDB 已不存在，而且当前 Makefile 已切换到 VeriSim/VeriCov、源码也已修改，因此只能作为待复验线索。

### 本次完成结果

- 建立了严格的证据等级和阶段验收标准。
- 确认当前 RTL 静态检查通过；这不是动态功能验证，也不把任何协议功能升级为 L2/L3。
- 确认当前 UVM 源码仍有编译阻断，未错误标记为“已通过”。
- 明确下一步必须先建立 compile/regression/coverage 基线，而不是继续增加更多未验收功能。

### 下一次学习入口

1. 修复函数名并完成真实 UVM compile。
2. 运行最小 `i3c_base_test` 和 `i3c_sdr_private_write_test`，学习如何从 UVM report 判断结果。
3. 为回归增加日志 gate，保存第一份当前版本的可追溯基线。

---

## 后续日志模板

### YYYY-MM-DD：主题

#### 学习目标

- 

#### 实际代码与证据

- 修改文件/行号：
- 编译命令与结果：
- test、seed、日志路径：
- `UVM_ERROR/UVM_FATAL`：
- coverage 变化：

#### 遇到的问题与原因

- 

#### 本次验收结论

- 证据等级：L0/L1/L2/L3/L4/L5
- 已完成：
- 待完成：

#### 下一步

1. 
2. 
3. 
