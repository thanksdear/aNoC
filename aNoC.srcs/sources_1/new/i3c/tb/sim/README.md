# I3C UVM Simulation Makefile 使用说明

本目录用于运行 I3C UVM 验证平台，默认使用 VCS 编译、URG 生成覆盖率报告、
Verdi 查看波形与覆盖率。

## 目录文件

- `Makefile`：编译、运行、回归和覆盖率报告入口。
- `filelist.f`：RTL、TB、UVM package 的编译文件列表。
- `out/build/`：VCS 编译生成的 `simv` 和编译日志。
- `out/runs/<test>/`：每个测试独立的 `sim.log` 与 `i3c.fsdb`。
- `out/simv.vdb`：VCS 覆盖率数据库。

## 编译

```sh
make comp
```

如果新增了 test、sequence、coverage 或 RTL 文件，必须重新执行：

```sh
make comp
```

否则可能出现 `+UVM_TESTNAME=xxx not found` 或旧代码仍被运行的问题。

## 运行单个测试

```sh
make run TEST=i3c_apb_reg_access_test
```

常用单测示例：

```sh
make run TEST=i3c_sdr_private_write_test
make run TEST=i3c_ral_access_test
make run TEST=i3c_direct_ccc_test
make run TEST=i3c_entdaa_test
make run TEST=i3c_entdaa_da_nack_test
make run TEST=i3c_ibi_payload_test
make run TEST=i3c_constrained_random_private_test \
  RUN_ARGS="+ntb_random_seed=1 +RAND_ITERS=30"
make run TEST=i3c_full_feature_test
```

其中 `i3c_full_feature_test` 是全功能串行测试，适合观察整体功能覆盖率。

## 回归测试

```sh
make regress
```

该命令会先执行 `make comp`，然后依次运行 `REGRESSION_TESTS` 中列出的测试。

运行APB、Private、CCC及ENTDAA/IBI四类受约束随机测试的多seed回归：

```sh
make random-regress RAND_SEEDS="1 2 3 4 5" RAND_ITERS=25
```

失败场景可使用日志文件名中的seed单独复现：

```sh
make run TEST=i3c_constrained_random_ccc_test \
  RUN_ARGS="+ntb_random_seed=3 +RAND_ITERS=25"
```

注意：当前 `REGRESSION_TESTS` 不包含 `i3c_full_feature_test`。如果要跑全功能测试，需要单独执行：

```sh
make run TEST=i3c_full_feature_test
```

## 覆盖率报告

默认 `Makefile` 已开启：

```makefile
CM_TYPES := line+cond+fsm+tgl+branch
CM       := -cm $(CM_TYPES) -cm_dir $(COV_DB)
```

因此运行 test 后会生成 `out/simv.vdb`。生成 HTML 和文本覆盖率报告：

```sh
make cov
```

使用 Verdi 查看覆盖率或某个测试的波形：

```sh
make verdi-cov
make verdi TEST=i3c_ral_access_test
```

## 推荐工作流

第一次运行：

```sh
cd i3c/tb/sim
make comp
make run TEST=i3c_base_test
```

跑单个功能：

```sh
make run TEST=i3c_entdaa_test
```

跑回归：

```sh
make regress
```

跑全功能覆盖率：

```sh
make comp
make run TEST=i3c_full_feature_test
make cov
```
