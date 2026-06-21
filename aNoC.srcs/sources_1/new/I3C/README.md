# I3C 主控制器 RTL 实现

## 概述

本模块实现了一个符合 MIPI I3C v1.1 规范的 **SDR 主控制器**，使用 Verilog 编写，面向 FPGA/ASIC 综合。

支持的功能：
- SDR 主控制器模式（Primary Controller）
- AMBA APB 总线寄存器访问接口
- 可编程总线时序（SCL 高/低周期、SDA 保持时间、总线空闲条件）
- SDR 私有读/写消息（I3C Private Transfer）
- I2C 私有读/写消息（向下兼容 I2C 设备）
- SDR 通用 CCC 消息（广播 CCC 和直接 CCC）
- 动态地址分配（ENTDAA CCC）
- 带内中断（IBI），可配置数据负载
- 中断（IRQ）和轮询（STATUS 寄存器）双模式访问

---

## 文件结构

```
I3C/
├── i3c_defines.vh      # 全局宏定义（CCC码、命令类型、寄存器偏移、位域）
├── i3c_fifo.v          # 参数化同步 FIFO（先行写透 FWFT）
├── i3c_bit_ctrl.v      # 位级总线控制器（SCL/SDA 时序状态机）
├── i3c_ctrl.v          # 帧级事务控制器（协议状态机）
└── i3c_top.v           # 顶层模块（APB 接口 + 寄存器文件 + 模块互联）
```

---

## 模块层次

```
i3c_top
├── i3c_fifo  (TX FIFO, 16×8bit)
├── i3c_fifo  (RX FIFO, 16×8bit)
├── i3c_bit_ctrl  (位级时序)
└── i3c_ctrl      (帧级协议)
```

---

## 顶层端口

### `i3c_top`

| 端口 | 方向 | 宽度 | 描述 |
|------|------|------|------|
| `PCLK` | 输入 | 1 | APB 时钟（同时作为 I3C 工作时钟） |
| `PRESETn` | 输入 | 1 | APB 异步复位（低有效） |
| `PSEL` | 输入 | 1 | APB 片选 |
| `PENABLE` | 输入 | 1 | APB 使能 |
| `PWRITE` | 输入 | 1 | APB 写使能 |
| `PADDR` | 输入 | 8 | APB 地址（字节地址，仅低 8 位有效） |
| `PWDATA` | 输入 | 32 | APB 写数据 |
| `PRDATA` | 输出 | 32 | APB 读数据 |
| `PREADY` | 输出 | 1 | APB 就绪（恒为 1，单周期访问） |
| `PSLVERR` | 输出 | 1 | APB 错误（恒为 0） |
| `IRQ` | 输出 | 1 | 中断请求（高有效，电平触发） |
| `SCL` | 输出 | 1 | I3C 时钟（推挽输出） |
| `SDA` | 双向 | 1 | I3C 数据（内部三态，控制器驱动时为推挽） |

---

## 寄存器映射

基地址由系统总线分配，以下为相对偏移：

| 偏移 | 寄存器名 | 读/写 | 描述 |
|------|----------|-------|------|
| `0x00` | `CTRL` | R/W | 控制寄存器 |
| `0x04` | `STATUS` | R | 状态寄存器（只读） |
| `0x08` | `INTR_EN` | R/W | 中断使能寄存器 |
| `0x0C` | `INTR_ST` | R/W1C | 中断状态寄存器（写 1 清除） |
| `0x10` | `TIMING0` | R/W | SCL 高电平周期计数 |
| `0x14` | `TIMING1` | R/W | SCL 低电平周期计数 |
| `0x18` | `TIMING2` | R/W | SDA 保持时间计数 |
| `0x1C` | `TIMING3` | R/W | 总线空闲时间计数 |
| `0x20` | `CMD` | R/W | 命令寄存器 |
| `0x24` | `TX_DATA` | W | TX FIFO 写入端口（只写） |
| `0x28` | `RX_DATA` | R | RX FIFO 读出端口（只读） |
| `0x2C` | `IBI_CTRL` | R/W | 带内中断控制寄存器 |
| `0x30` | `IBI_INFO` | R | IBI 信息寄存器（只读，事件更新） |
| `0x34` | `DAA_ADDR` | R/W | 动态地址分配寄存器 |
| `0x38` | `FIFO_ST` | R | FIFO 状态寄存器（只读） |

---

### 寄存器位域详解

#### CTRL（0x00）

| 位 | 名称 | 描述 |
|----|------|------|
| [0] | `EN` | 控制器使能。置 1 后才能发起事务 |
| [1] | `START` | 启动事务（写 1 触发，硬件自动清零） |
| [2] | `ABORT` | 中止当前事务（高电平有效，发完当前位后停止） |
| [3] | `SWRST` | 软件复位（写 1 触发，复位所有子模块和 FIFO） |

> **使用方法**：先写 `CTRL = 0x01`（EN=1），再配置 CMD，填充 TX FIFO，最后写 `CTRL = 0x03`（同时置 EN 和 START）。

#### STATUS（0x04）只读

| 位 | 名称 | 描述 |
|----|------|------|
| [0] | `BUSY` | 总线忙（事务进行中） |
| [1] | `ARB_LOST` | 仲裁丢失（主控仲裁败） |
| [2] | `NACK_ERR` | 收到 NACK 或 T-bit 错误 |
| [3] | `IBI_REQ` | 检测到 IBI 请求 |
| [4] | `DAA_DONE` | ENTDAA 序列完成 |
| [5] | `TX_FULL` | TX FIFO 满 |
| [6] | `TX_EMPTY` | TX FIFO 空 |
| [7] | `RX_FULL` | RX FIFO 满 |
| [8] | `RX_EMPTY` | RX FIFO 空 |
| [9] | `DONE` | 事务完成（脉冲，读 STATUS 可知是否结束） |

#### INTR_EN / INTR_ST（0x08 / 0x0C）

两个寄存器位域相同，INTR_ST 写 1 清除：

| 位 | 名称 | 描述 |
|----|------|------|
| [0] | `DONE` | 事务完成中断 |
| [1] | `NACK` | NACK 错误中断 |
| [2] | `ARB_LOST` | 仲裁丢失中断 |
| [3] | `IBI` | IBI 事件中断 |
| [4] | `DAA_DONE` | ENTDAA 完成中断 |
| [5] | `TX_EMPTY` | TX FIFO 空中断 |
| [6] | `RX_FULL` | RX FIFO 满中断 |

IRQ = `|(INTR_ST[6:0] & INTR_EN[6:0])`，电平触发，须写 INTR_ST 清除。

#### TIMING0～TIMING3（0x10～0x1C）低 16 位有效

| 寄存器 | 含义 | 默认值（@100MHz） |
|--------|------|-----------------|
| `TIMING0` | SCL 高电平持续时钟数 | 4（≈40 ns，对应 ~12.5 MHz SCL） |
| `TIMING1` | SCL 低电平持续时钟数 | 4（≈40 ns） |
| `TIMING2` | SCL 下降沿后 SDA 保持时钟数（t_HD;DAT） | 1（≈10 ns） |
| `TIMING3` | START/STOP 条件建立/保持时钟数（总线空闲） | 8（≈80 ns） |

> **注意**：`TIMING2 < TIMING1` 时，SCL 低电平时间 = TIMING2（SDA 建立）+ (TIMING1 - TIMING2)（剩余低电平）。

#### CMD（0x20）

| 位域 | 名称 | 描述 |
|------|------|------|
| [7:0] | `CCC_CODE` | CCC 命令码（仅 BC_CCC/DC_CCC/ENTDAA 有效） |
| [15:8] | `DATA_LEN` | 数据字节数（TX 写出或 RX 读入的字节数） |
| [22:16] | `TGT_ADDR` | 目标设备 7 位地址（私有传输和直接 CCC 有效） |
| [27:24] | `CMD_TYPE` | 命令类型（见下表） |
| [28] | `I2C_MODE` | 1 = I2C 兼容模式（ACK/NACK 语义，开漏） |

**CMD_TYPE 编码**

| 值 | 宏名 | 描述 |
|----|------|------|
| `4'd0` | `CMD_PRIV_WR` | I3C SDR 私有写 |
| `4'd1` | `CMD_PRIV_RD` | I3C SDR 私有读 |
| `4'd2` | `CMD_BC_CCC` | 广播 CCC（发送至 0x7E） |
| `4'd3` | `CMD_DC_CCC_WR` | 直接 CCC 写 |
| `4'd4` | `CMD_DC_CCC_RD` | 直接 CCC 读 |
| `4'd5` | `CMD_ENTDAA` | 动态地址分配 |
| `4'd6` | `CMD_I2C_WR` | I2C 私有写（开漏 ACK） |
| `4'd7` | `CMD_I2C_RD` | I2C 私有读（开漏 ACK） |

#### IBI_CTRL（0x2C）

| 位 | 名称 | 描述 |
|----|------|------|
| [0] | `IBI_EN` | 使能 IBI 检测。置 0 时忽略 SDA 拉低事件 |
| [1] | `IBI_DATA_EN` | 置 1 时，ACK 后读取 1 字节 IBI 强制数据 |
| [2] | `IBI_AUTO_ACK` | 置 1 时自动 ACK IBI；置 0 时自动 NACK |

#### IBI_INFO（0x30）只读

| 位域 | 描述 |
|------|------|
| [6:0] | IBI 源设备动态地址 |
| [15:8] | IBI 强制数据字节（IBI_DATA_EN=1 时有效） |

#### DAA_ADDR（0x34）

| 位域 | 描述 |
|------|------|
| [6:0] | ENTDAA 过程中分配给下一个目标设备的动态地址 |

> 在 ENTDAA 进行中，每完成一轮（DAA_DONE 中断），软件更新此寄存器，再次触发 START 继续下一设备的地址分配。

#### FIFO_ST（0x38）只读

| 位域 | 描述 |
|------|------|
| [4:0] | TX FIFO 中当前字节数 |
| [12:8] | RX FIFO 中当前字节数 |

---

## 协议帧格式

### 1. I3C SDR 私有写

```
S  [ADDR+W]  T  [DATA0]  T  [DATA1]  T  ...  [DATAn]  T  P
```

### 2. I3C SDR 私有读

```
S  [ADDR+R]  T  <DATA0>  T  <DATA1>  T  ...  <DATAn>  T(NACK)  P
```

### 3. 广播 CCC（以 RSTDAA 为例）

```
S  [0x7E+W]  T  [CCC_CODE]  T  P
```

带数据的广播 CCC（如 SETMWL）：

```
S  [0x7E+W]  T  [CCC_CODE]  T  [DATA0]  T  ...  P
```

### 4. 直接 CCC 写（如 SETNEWDA）

```
S  [0x7E+W]  T  [CCC_CODE]  T  Sr  [ADDR+W]  T  [DATA]  T  P
```

### 5. 直接 CCC 读（如 GETSTATUS）

```
S  [0x7E+W]  T  [CCC_CODE]  T  Sr  [ADDR+R]  T  <DATA0>  T  ...  P
```

### 6. ENTDAA

```
S  [0x7E+W]  T  [0x07]  T  Sr  [0x7E+R]  T
  <PID[47:0]>  <BCR>  <DCR>   (来自设备，共 8 字节)
  [DA[6:0]+奇校验]  (控制器写入分配地址)
  T  P           (如还有未分配设备，重复 Sr 开始的步骤)
```

> - 每轮 DAA 完成后触发 `DAA_DONE` 中断
> - 软件更新 `DAA_ADDR` 后再次写 `CTRL.START` 继续下一台设备

### 7. IBI 处理

```
(总线空闲时设备拉低 SDA)
S  <ADDR[6:0]+P_bit>  [T:ACK/NACK]  (<IBI_DATA>)  P
```

> - 控制器检测到 SDA 下降沿时，自动发 START 参与仲裁
> - `IBI_AUTO_ACK=1`：硬件自动发 ACK，触发 `IBI` 中断并上报地址/数据
> - `IBI_AUTO_ACK=0`：硬件自动发 NACK 拒绝

**符号说明**：`S`=START，`Sr`=Repeated START，`P`=STOP，`T`=T-bit（类 ACK），`[x]`=主控发送，`<x>`=设备发送

---

## 软件使用指南

### 初始化

```c
// 1. 配置 SCL 时序（以 100MHz 系统时钟，12.5MHz I3C 为例）
I3C_WR(TIMING0, 4);   // SCL 高：4 clk = 40ns
I3C_WR(TIMING1, 4);   // SCL 低：4 clk = 40ns
I3C_WR(TIMING2, 1);   // SDA 保持：1 clk
I3C_WR(TIMING3, 8);   // 总线空闲：8 clk

// 2. 使能控制器和所需中断
I3C_WR(INTR_EN, 0x1F);  // 使能 DONE/NACK/ARB_LOST/IBI/DAA_DONE
I3C_WR(CTRL, 0x01);     // EN = 1
```

### 私有写（3 字节）

```c
// 配置命令：目标地址 0x08，写 3 字节
I3C_WR(CMD, (0x08 << 16) | (3 << 8) | (CMD_PRIV_WR << 24));

// 填充 TX FIFO
I3C_WR(TX_DATA, 0xAA);
I3C_WR(TX_DATA, 0xBB);
I3C_WR(TX_DATA, 0xCC);

// 启动事务
I3C_WR(CTRL, 0x03);  // EN + START

// 轮询等待（或等待中断）
while (!(I3C_RD(STATUS) & (1 << 9)));  // 等待 DONE

// 检查错误
if (I3C_RD(STATUS) & (1 << 2)) { /* NACK 错误处理 */ }

// 清除中断
I3C_WR(INTR_ST, 0xFF);
```

### 私有读（4 字节）

```c
I3C_WR(CMD, (0x08 << 16) | (4 << 8) | (CMD_PRIV_RD << 24));
I3C_WR(CTRL, 0x03);  // 启动

// 等待完成
while (!(I3C_RD(STATUS) & (1 << 9)));

// 读取 RX FIFO
for (int i = 0; i < 4; i++) {
    data[i] = I3C_RD(RX_DATA) & 0xFF;
}
```

### 广播 CCC（RSTDAA，重置所有动态地址）

```c
I3C_WR(CMD, (0x06 << 0) | (0 << 8) | (CMD_BC_CCC << 24));
// CCC_CODE=0x06(RSTDAA), DATA_LEN=0
I3C_WR(CTRL, 0x03);
while (!(I3C_RD(STATUS) & (1 << 9)));
```

### 直接 CCC 读（GETSTATUS，读目标设备状态）

```c
// 读目标 0x08 的状态，期望返回 2 字节
I3C_WR(CMD, (0x90 << 0) | (2 << 8) | (0x08 << 16) | (CMD_DC_CCC_RD << 24));
I3C_WR(CTRL, 0x03);
while (!(I3C_RD(STATUS) & (1 << 9)));
uint8_t s0 = I3C_RD(RX_DATA);
uint8_t s1 = I3C_RD(RX_DATA);
```

### ENTDAA（动态地址分配）

```c
// 先广播 RSTDAA 清除已有地址
// ... （同上）

int assigned_addr = 0x08;  // 从 0x08 开始分配

I3C_WR(DAA_ADDR, assigned_addr);
I3C_WR(CMD, (CMD_ENTDAA << 24));  // 其余字段不使用
I3C_WR(CTRL, 0x03);

// 等待 DAA_DONE 中断（每分配一台设备触发一次）
// 中断处理中：
//   1. 读 RX FIFO 中的 8 字节（PID 6B + BCR 1B + DCR 1B）
//   2. 更新 DAA_ADDR 为下一个地址
//   3. 清除中断，再次写 START 继续（若还有设备）
//   4. 当 DONE 中断（非 DAA_DONE）触发时，DAA 序列结束
```

### IBI 配置（自动 ACK，带数据字节）

```c
I3C_WR(IBI_CTRL, 0x07);  // IBI_EN=1, IBI_DATA_EN=1, IBI_AUTO_ACK=1
I3C_WR(INTR_EN, I3C_RD(INTR_EN) | (1 << 3));  // 使能 IBI 中断

// 中断处理：
void ibi_isr() {
    uint32_t info = I3C_RD(IBI_INFO);
    uint8_t src_addr  = info & 0x7F;
    uint8_t ibi_data  = (info >> 8) & 0xFF;
    // 处理 IBI ...
    I3C_WR(INTR_ST, 1 << 3);  // 清除 IBI 中断
}
```

### I2C 兼容模式（访问 I2C 设备）

```c
// 向 I2C 地址 0x48 写 1 字节（开漏 ACK 语义）
I3C_WR(CMD, (0x48 << 16) | (1 << 8) | (CMD_I2C_WR << 24) | (1 << 28));
//                                                             ↑ I2C_MODE=1
I3C_WR(TX_DATA, 0x01);
I3C_WR(CTRL, 0x03);
while (!(I3C_RD(STATUS) & (1 << 9)));
```

---

## 时序说明

### SCL 时序计算

设系统时钟频率 `f_clk`，期望 SCL 频率 `f_scl`：

```
TIMING0 = f_clk / (2 × f_scl)    // SCL 高电平计数
TIMING1 = f_clk / (2 × f_scl)    // SCL 低电平计数
TIMING2 = max(1, t_HD_DAT × f_clk)   // SDA 保持时间（t_HD;DAT ≥ 0ns in I3C）
TIMING3 = max(4, t_CBP × f_clk)      // 总线空闲/START 建立时间
```

| 目标 SCL | @100MHz TIMING0/1 | @200MHz TIMING0/1 |
|----------|------------------|--------------------|
| 12.5 MHz | 4 | 8 |
| 6.25 MHz | 8 | 16 |
| 1 MHz（I2C Fast）| 50 | 100 |
| 400 kHz（I2C Standard）| 125 | 250 |

### I3C T-bit 行为

- **写方向**：设备驱动 T-bit（0=ACK，1=NACK/错误）
- **读方向**：控制器驱动 T-bit（0=继续读，1=最后一字节 NACK）
- **I2C 模式**：使用标准 I2C ACK（SDA=0）/NACK（SDA=1）

---

## 位级控制器状态机

`i3c_bit_ctrl` 实现了 5 种原子总线操作，每种操作通过独立子状态完成：

```
START:  SCL=H, SDA: H→L (idle_cnt), SCL→L (lo_cnt)
RSTART: SDA→H (hd_cnt), SCL→H (hi_cnt), SDA→L (hd_cnt), SCL→L
WRITE:  SDA=bit (hd_cnt), SCL→H (hi_cnt), SCL→L (lo_cnt-hd_cnt)
READ:   SDA=Z (hd_cnt),   SCL→H (hi_cnt, 在最后一拍采样), SCL→L
STOP:   SDA→L (hd_cnt), SCL→H (hi_cnt), SDA→H (idle_cnt)
```

IBI 检测：在 `IDLE` 状态（SCL=H, SDA=H）下，若 `sda_in` 出现下降沿，输出 `ibi_det` 脉冲。

---

## 帧控制器状态机

`i3c_ctrl` 的顶层状态（简化）：

```
FC_IDLE
  ↓ start / ibi_pend
FC_START → FC_BCAST_ADDR → FC_CCC_BYTE ←───────────────────────┐
                              ↓                                   │
                         FC_RSTART → FC_TARG_ADDR → FC_TARG_TBIT │
                                                        ↓         │
                                              FC_TX_BYTE/FC_RX_BYTE
                                              FC_DAA_RX → FC_DAA_TX
                                                        ↓
                                                    FC_STOP → FC_DONE
                                                        ↓
                                                    FC_IDLE
```

IBI 路径：
```
FC_IBI_START → FC_IBI_ADDR → FC_IBI_TBIT → [FC_IBI_DATA] → FC_IBI_STOP → FC_DONE
```

---

## FIFO 设计

TX/RX FIFO 均采用**先行写透（First-Word Fall-Through, FWFT）**结构：
- `rd_data` 为组合输出，始终反映当前读指针指向的数据
- `rd_en` 上升沿推进读指针（消费当前数据）
- 容量：16×8 bit，计数宽度 5 bit

> 使用前需检查 TX FIFO 非满（`STATUS[5]=0`）再写 TX_DATA；
> 使用前需检查 RX FIFO 非空（`STATUS[8]=0`）再读 RX_DATA。

---

## 约束与限制

1. **单主模式**：本实现为纯主控，不支持次级控制器（Secondary Controller）或主控切换
2. **SDR only**：不支持 HDR 模式（HDR-DDR、HDR-TSP、HDR-TSL）
3. **ENTDAA 简化**：每次 ENTDAA 事务只处理一台设备的地址分配，多台设备需软件循环触发
4. **IBI 数据**：仅支持 1 字节强制数据（Mandatory Byte），不支持扩展 IBI 数据
5. **仲裁丢失**：`arb_lost` 位保留，当前版本不实现实际的总线仲裁检测
6. **热插拔**：不支持设备热插拔通知（Hot-Join）
7. **时钟域**：APB 时钟与 I3C 工作时钟共用同一时钟（`PCLK`），不支持跨时钟域

---

## 综合指导

- **工具**：Vivado / Quartus / Design Compiler 均可综合
- **目标器件**：FPGA（Artix-7 / Kintex-7 / Cyclone V 等）或 ASIC 标准单元库
- **关键路径**：APB 读多路选择器（约 3～4 级逻辑）；位控制器计数器（16 bit 减法）
- **约束**：需为 `SCL` 和 `SDA` 的 IO 约束加 `KEEPER` 或外部上拉（I2C 模式需开漏缓冲器）
- **面积估计**（28nm ASIC）：约 2k～3k 等效门（不含 FIFO 内存）

---

## 版本说明

| 版本 | 日期 | 说明 |
|------|------|------|
| 1.0 | 2026-06-18 | 初始版本，支持全部列出功能 |
