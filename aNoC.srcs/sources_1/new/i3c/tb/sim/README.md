# I3C UVM Simulation Makefile 使用说明

本目录用于运行 I3C UVM 验证平台，默认使用 VeriSim 编译和仿真。

## 目录文件

- `Makefile`：编译、运行、回归和覆盖率报告入口。
- `filelist.f`：RTL、TB、UVM package 的编译文件列表。
- `log/`：运行后生成的日志目录。
- `image`：VeriSim 编译生成的仿真镜像。
- `verisim.zdb`：开启覆盖率数据库输出后生成的覆盖率数据库。

## 编译

```sh
make compile
```

如果新增了 test、sequence、coverage 或 RTL 文件，必须重新执行：

```sh
make compile
```

否则可能出现 `+UVM_TESTNAME=xxx not found` 或旧代码仍被运行的问题。

## 运行单个测试

```sh
make run TEST=i3c_apb_reg_access_test
```

常用单测示例：

```sh
make run TEST=i3c_sdr_private_write_test
make run TEST=i3c_direct_ccc_test
make run TEST=i3c_entdaa_test
make run TEST=i3c_ibi_payload_test
make run TEST=i3c_full_feature_test
```

其中 `i3c_full_feature_test` 是全功能串行测试，适合观察整体功能覆盖率。

## 回归测试

```sh
make regress
```

该命令会先执行 `make compile`，然后依次运行 `REGRESSION_TESTS` 中列出的测试。

注意：当前 `REGRESSION_TESTS` 不包含 `i3c_full_feature_test`。如果要跑全功能测试，需要单独执行：

```sh
make run TEST=i3c_full_feature_test
```

## 覆盖率报告

默认 `Makefile` 已开启：

```makefile
VERISIM_FLAGS := ... -code-cov all ...
RUN_FLAGS     ?= -write-sql
```

因此运行 test 后会生成 `verisim.zdb`。生成覆盖率报告：

```sh
make cov
```

## 推荐工作流

第一次运行：

```sh
cd i3c/tb/sim
make compile
make run TEST=i3c_base_test
```

跑单个功能：

```sh
make run TEST=i3c_entdaa_test
```

跑回归：

```sh
make regress

跑全功能覆盖率：

```sh
make compile
make run TEST=i3c_full_feature_test
make cov
```


