# I3C UVM 学习周报

> 报告快照：2026-07-21  
> 当前 Git HEAD：`ba8d3fd`，工作区有未提交修改  
> RTL/TB dirty diff SHA-256：`e2636dd96bfc3f18e131b88a44cbb3ddea273e7558b29df86f12b22f214b66f5`  
> 结论范围：只代表当前磁盘快照，不沿用缺失的旧日志或覆盖率数字

## 本周结论

当前项目已经形成较广的 UVM 源码骨架和 I3C 定向测试集合，但尚未形成可复核的验证闭环。RTL 静态检查通过；UVM 当前版本存在确定语法阻断，且仓库没有编译日志、仿真日志或覆盖率数据库。因此，本周不能把任何 UVM test 标记为“当前版本已验证通过”。

## 1. 本阶段已经掌握或正在掌握的 UVM 知识点

采用 `learning-plan.md` 的证据等级后，当前能够确认的是“源码实践深度”，不是完整 L4 签核。

| 知识点 | 当前判断 | 项目证据 |
|---|---|---|
| transaction、factory 字段注册、基础 constraint | 已实践，待动态验收 | `tb/env/i3c_agent/i3c_txn.sv:1-25` |
| sequence/sequencer/driver handshake | 已实践，结构明确 | `i3c_seq.sv:39-60`；`i3c_driver.sv:22-27`；`i3c_agent.sv:10-21` |
| phase、objection、config DB、virtual interface | 已实践，结构明确 | `tb/top/tb.top.sv:45-47`；`i3c_base_test.sv:23-42`；`i3c_env.sv:19-58` |
| analysis port 一对多广播 | 已实践，能跟踪数据去向 | `i3c_monitor.sv:20-44`；`i3c_env.sv:32-50` |
| 普通 TLM FIFO 生产者/消费者 | 已实践，当前重点学习项 | `i3c_scoreboard.sv:821-870` |
| predictor 与 actual/expected 分离 | 已实现较完整框架，尚未通过当前版本回归 | `i3c_scoreboard.sv:431-817,1826-1873`；`i3c_bus_monitor.sv:314-559` |
| passive protocol monitor、segment/restart 解码 | 已编码，尚未通过当前版本回归 | `i3c_bus_monitor.sv:53-132,360-535` |
| scoreboard 分层比较 | 已编码，正在理解 | `i3c_scoreboard.sv:1064-1816` |
| coverage subscriber、coverpoint、cross | 已编码，尚未 closure | `i3c_coverage.sv:40-213,288-773` |
| constrained-random、seed regression | 尚未展示掌握 | 只有 `rand/constraint`，工程无 `randomize()` |
| RAL、virtual sequence、factory override、SVA | 尚未展示 | 当前工程没有对应实现 |

严格结论：基础 UVM 数据流已经达到 L1“已接触/已编码”；在恢复编译并完成正反向回归前，不升级为 L3/L4。

## 2. 已完成代码与有证据通过的检查

### 本周可确认通过（仅静态）

| 检查对象 | 实际结果 | 证据等级 |
|---|---|---|
| RTL `i3c_top` 静态 lint/elaboration | Slang：0 errors，0 warnings | `progress-log.md` 中的完整命令与本次会话输出 |
| `tb_i3c_top` + RTL 静态 elaboration | 加 `--timescale 1ns/1ps` 后 0 errors，0 warnings | `progress-log.md` 中的完整命令与本次会话输出 |
| `tb_sync_fifo` + `sync_fifo` 静态 elaboration | 0 errors，0 warnings | `progress-log.md` 中的完整命令与本次会话输出 |

以上均为静态检查，不等价于动态仿真通过。当前有证据的 UVM 动态验证通过项为 **0**。

### 已完成源码、但当前不能认定验证通过

- 24 个 UVM test class，其中 22 个非 full feature test、1 个 base、1 个 full-feature 组合测试；其中 polling 目前只是复用 private-write body。
- 23 项 Makefile regression 入口。
- Private/I2C/CCC/ENTDAA/IBI/reset/IRQ 等定向 sequence。
- APB CSR scoreboard、I3C predictor、bus scoreboard、target model 和 protocol coverage。
- 9 个 covergroup、48 个 coverpoint、13 个 cross。

原因：当前没有与源码快照对应的 compile log、test log、UVM report summary 或 coverage report。

## 3. 尚未解决的错误或薄弱环节

### 当前阻断

1. `tb/env/i3c_scoreboard.sv:505` 为：

   ```systemverilog
   function void apply_target _intent(
   ```

   调用处为 `apply_target_intent(...)`。该问题由带临时 UVM macro stub 的 Slang
   `--parse-only` 定位；stub 检查不等价于真实 UVM 编译，但该函数声明本身是确定的
   SystemVerilog 语法错误。

2. 本次工具检查未找到 `verisim`、`vericov`、`vcs`、`urg` 或其他动态模拟器；Makefile 默认的 `../../../uvm-1.2` 也不存在，因而当前构建无法执行真实 UVM compile/regression。这里不绝对断言机器其他位置没有 UVM。

3. 当前仓库没有 `log/`、simulation image、`verisim.zdb`、`cov.txt` 或 LCOV 报告；覆盖率为未知，不能引用百分比。

### 验证架构薄弱点

- `process_bus()` 对 actual 使用阻塞 `get()`，对 expected 使用非阻塞 `try_get()`；expected 晚到可能误报，漏一笔后可能 FIFO 级联错位。
- APB driver/monitor 没有采集或检查 `PSLVERR`，APB error response 尚未形成 stimulus/checker 闭环。
- target BFM 不是独立 target agent，部分 sequence 直接修改共享 `vif`；bus monitor 依赖 `slave_drive_low` 等 TB sideband，黑盒复用性有限。
- target model 固定为单 target，read plan 只支持 1～4 byte，IBI 只覆盖无 MDB/单 MDB；报告中的“完整”必须限定为当前 RTL/学习平台子集，不能代表完整 MIPI I3C 标准。
- `polling_access_seq` 没有独立 body；timing tests 没有测量实际总线周期。
- `rand/constraint` 没有被 `randomize()` 使用，缺少 seed stress 和可复现随机回归。
- coverage 把 unknown、null、incomplete、X/Z、bad parity、malformed 和部分不可达状态作为普通 bins，100% closure 目标失真。
- 若干原始 `wait` 缺 timeout；test 结尾大量使用固定 `repeat(20)`，缺统一 completion/drain 策略。
- Makefile 回归只看 simulator 退出码，没有强制检查 UVM report summary；`full_feature_test` 不在默认回归，也不能替代全部单测。
- 尚无 RAL、SVA、virtual sequence/sequencer、factory override 实例和可复用 target UVC。

### 历史线索

旧截图中的 full-feature 日志曾有 `UVM_ERROR : 28`，旧 URG 报告曾出现 `Design not yet loaded`。原始文件已不存在，构建流程和源码也已经变化，因此这些只能作为待复验线索，不能代表当前结果。

## 4. 当前总体进度

当前阶段定位：**学习内容的广度已经触及路线阶段 1～4，但证据成熟度仍停在阶段 0 阻塞/L1，尚未通过阶段 1、2 或 3 的验收。**

不使用缺少分母和 requirement 矩阵的主观百分比，当前按证据等级记录：

- 阶段 0：阻塞。真实 UVM compile、动态回归和 coverage 证据链未建立。
- 阶段 1～4：均有代码实践入口，最高只能记 L1；不能因 test/covergroup 数量升级。
- 阶段 5：RAL、SVA、virtual sequence、target UVC 等尚未开始或处于早期。

当前最大的瓶颈不是“测试数量不够”，而是没有一条从当前源码、编译、每项 test、UVM summary 到 coverage report 的可信证据链。

## 5. 下一阶段最值得完成的三个任务

### 任务 1：恢复真实 UVM 编译并建立回归证据基线

- 修复 `apply_target_intent` 函数名。
- 配置真实 UVM 1.2 和可用模拟器。
- 先运行 `i3c_base_test`、private write/read，再运行 23 项 regression。
- 自动汇总每个日志的 test、seed、`UVM_ERROR`、`UVM_FATAL` 和 scoreboard 残留。
- 保存当前 commit/tool/version 对应的 compile log、sim logs 和 summary。

验收：当前源码 compile 0 error；全部目标测试 UVM error/fatal 为 0；失败能由 test+seed 重现。

### 任务 2：加固 scoreboard 配对并证明 checker 有效

- 将 expected/actual 配对改成 reset-aware、带 timeout 的等待，消除 `try_get()` 到达竞态。
- 对 payload、地址 ACK、I3C T-bit、legacy I2C data ACK 各做一次故障注入。
- 确认每种错误由正确 checker 报出，恢复 DUT 后回归重新变为 0 error。

验收：到达顺序变化、复位中断和缺失 expected 不死锁、不误配；四类故障注入均被检测。

### 任务 3：建立 verification plan 和第一轮 coverage closure

- 建 requirement -> test -> checker -> coverpoint 矩阵。
- 修订异常/不可达 coverage bins，区分 legal closure 与 negative decoder coverage。
- 优先补真正的 timing measurement/SVA、Direct CCC length 2、真实 polling，以及 ENTDAA/IBI 失败路径。
- 生成并保存 functional/code coverage 报告，对每个未命中 required bin给出测试或 waiver。

验收：required bins 全命中或有审批 waiver；coverage 数字可追溯到当前源码和回归，不再只看 full-feature 单测。
