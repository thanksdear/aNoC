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

## 2026-07-21：CMD-before-TX 运行时环形等待

### 现象与实际证据

- 当前 Git HEAD：`4b00573`。
- 修改前的仿真停在时间 `20965000`，最后一条输出是 APB monitor 观察到：

  ```text
  OBSERVE APB WRITE addr=0x20 data=0x02240000
  ```

- `0x02240000` 按 `private_cmd()` 的定义解码为：private write、target
  地址 `7'h12`、`rw=0`、长度 2 byte。
- 结合该命令之前只有 `cfg_i3c_mode()`、没有 TX_PORT 写，可以定位到
  `tb/env/i3c_agent/i3c_seq.sv` 的 `i3c_cmd_before_tx_seq`。
- 仿真没有退出，是因为 sequence 卡在裸 `wait` 中，test objection 一直没有
  drop；不是 scoreboard 的打印把仿真卡住。
- 本次没有取得原始 sim log 路径、test seed 和 UVM report summary，因此该失败
  目前以屏幕输出作为定位证据，尚不满足可复现回归记录要求。

### 根因

原来的执行顺序形成了三方环形等待：

```text
sequence 等 slave_dbg_ack_phase 清零后才写 TX
target 必须等下一次 SCL 下降沿，才能在协议安全时刻释放地址 ACK
RTL 在 S_DATA_WR 中等待 TX FIFO 非空，收到 TX 前不会产生下一次 SCL 下降沿
```

因此三方分别等待对方先动作，仿真时间不再前进到 sequence 的下一条 APB 操作。
`i3c_cmd_predictor::bind_write_data()` 同时等待 TX 数据是该场景的正常行为，
bus monitor 等待完整 STOP 也是正常行为，它们不是死锁根因。

### 修改前后代码对照

#### `i3c_cmd_before_tx_seq`：修改前（有环形等待）

```systemverilog
send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b0, 8'd2));
wait (vif.slave_dbg_ack_phase === 1'b1);
wait (vif.slave_dbg_ack_phase === 1'b0);

repeat (4) @(posedge vif.clk);
apb_read(REG_STATUS, rdata);
expect_eq("CMD-before-TX waits after address", rdata,
          32'h0000_0001, 32'h0000_0001);

send_apb(WR, TX_PORT, 32'h0000_00d1);
wait (vif.slave_dbg_write_byte === 8'hd1);
```

问题在于第二个 `wait`：sequence 要等 ACK phase 清零才写 `d1`，但 target
只有在下一个 SCL 下降沿才能清零 ACK phase，而 RTL 又必须先收到 `d1` 才会
产生这个 SCL 下降沿。

#### `i3c_cmd_before_tx_seq`：修改后

```systemverilog
send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b0, 8'd2));
wait (vif.slave_dbg_ack_phase === 1'b1);

// TX FIFO 仍为空时，确认 DUT 已完成地址阶段并保持 busy。
repeat (4) @(posedge vif.clk);
apb_read(REG_STATUS, rdata);
expect_eq("CMD-before-TX waits after address", rdata,
          32'h0000_0001, 32'h0000_0001);

// 先提供第一个 byte，RTL 才会产生下一次 SCL 下降沿。
send_apb(WR, TX_PORT, 32'h0000_00d1);
wait (vif.slave_dbg_ack_phase === 1'b0);
wait (vif.slave_dbg_write_byte === 8'hd1);
```

关键变化不是取消 ACK 检查，而是把“等待 ACK phase 清零”移动到首个 TX byte
写入之后。这样仍然检查了 ACK 的开始和结束，同时打破循环等待。

#### `i3c_sw_reset_seq`：修改前（同类问题）

```systemverilog
vif.slave_ack_addr <= 1'b1;
send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b0, 8'd1));
wait (vif.slave_dbg_ack_phase === 1'b1);
wait (vif.slave_dbg_ack_phase === 1'b0);
apb_read(REG_STATUS, rdata);
expect_eq("busy before sw_rst", rdata, 32'h1, 32'h1);

send_apb(WR, REG_CTRL, 32'h0000_0007);
```

这个场景有意不提供 TX 数据，所以根本不会自然产生使 ACK phase 清零的下一次
SCL 下降沿；等待清零会让软件复位命令永远无法发出。

#### `i3c_sw_reset_seq`：修改后

```systemverilog
vif.slave_ack_addr <= 1'b1;
send_apb(WR, CMD_PORT, private_cmd(SLAVE_ADDR, 1'b0, 8'd1));
wait (vif.slave_dbg_ack_phase === 1'b1);

// 确认命令确实阻塞在等待 TX，然后直接用 sw_rst 中止它。
apb_read(REG_STATUS, rdata);
expect_eq("busy before sw_rst", rdata, 32'h1, 32'h1);

send_apb(WR, REG_CTRL, 32'h0000_0007);
```

这里不再等待 ACK phase 自然结束；软件复位会推进 reset epoch，同时终止 RTL、
target model、monitor 和 predictor 中属于旧事务的状态。

### 修改内容

- 修改文件：`tb/env/i3c_agent/i3c_seq.sv`。
- `i3c_cmd_before_tx_seq` 现在按照以下顺序执行：

  1. 先发 CMD，并等待地址 ACK 阶段开始。
  2. 在 TX FIFO 为空时读取 STATUS，确认 DUT 保持 busy。
  3. 写入首个 TX byte，使 RTL 产生下一次 SCL 下降沿。
  4. target 在 SCL 低期间释放地址 ACK，然后继续传输两个数据 byte。

- `i3c_sw_reset_seq` 原来也在“无 TX 数据”场景等待 ACK phase 清零，会产生同样
  的死锁；现改为地址 ACK 开始后直接检查 busy 并发出软件复位。
- 没有把 target 改成在 SCL 高电平期间直接释放 SDA，因为这会形成
  `SDA 上升且 SCL 为高`，可能被 monitor 和真实协议解释为 STOP。

### 当前源码快照与验收状态

- HEAD：`4b00573`，`i3c/rtl` 与 `i3c/tb` 当前有 1 个未提交修改文件。
- 当前 RTL/TB dirty diff SHA-256：
  `4d338f74ef017e82f4a222e932b3da2d109a63f4245c580ceb318ef435d88221`。
- `git diff --check`：通过。
- 证据等级：L1“已定位并修改”；尚未取得修改后的真实 VCS 编译和仿真结果，
  不能标记为“验证通过”。

### 待复验

1. 重新编译，避免继续运行旧的 simulation image。
2. 单独运行 `i3c_cmd_before_tx_test`，确认能够依次观察到 STATUS busy、TX
   byte `d1/e2` 和 response。
3. 运行 `i3c_sw_reset_test`，确认阻塞命令可被软件复位终止。
4. 最后重新运行 `i3c_full_feature_test`，检查 `UVM_ERROR/UVM_FATAL`、scoreboard
   残留和 test seed，并保存完整日志。

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
