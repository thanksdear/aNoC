`ifndef I3C_DEFINES_VH
`define I3C_DEFINES_VH

// I3C master 共用常量定义。

// APB 寄存器偏移，字节地址
`define REG_BUS_TIMING_0  8'h00   // [31:16]=SCL_HIGH  [15:0]=SCL_LOW    RW
`define REG_BUS_TIMING_1  8'h04   // [15:0]=SDA_HOLD                     RW
`define REG_CTRL          8'h08   // [4]=ibi_mdb_en [3]=ibi_en [2]=sw_rst [1]=core_en [0]=i3c_mode  RW
`define REG_STATUS        8'h0C   // [1]=ibi_pending [0]=busy             RO
`define REG_IBI_STATUS    8'h10   // [16]=valid [15:8]=len [7]=mdb [6:0]=addr  RO/RW1C
`define REG_ERR_STATUS    8'h14   // [1]=nack_err [0]=parity_err          RW1C
`define REG_ENTDAA_STATUS 8'h18   // [8]=valid [6:0]=assigned DA         RO
`define REG_ENTDAA_PID_LO 8'h1C   // 发现的 PID/BCR/DCR[31:0]           RO
`define REG_ENTDAA_PID_HI 8'h30   // 发现的 PID/BCR/DCR[63:32]          RO

// FIFO 端口地址，由顶层译码
`define CMD_PORT          8'h20   // W: 写入 32-bit command descriptor
`define RESP_PORT         8'h24   // R: 读出 32-bit response descriptor
`define TX_PORT           8'h28   // W: 写入 8-bit TX data
`define RX_PORT           8'h2C   // R: 读出 8-bit RX data

// Command descriptor 字段，位于 cmd_fifo 的 32-bit word 中
//   [31:24]  data_len   数据 byte 数，0表示只有 header
//   [23:17]  addr       private 地址或 direct CCC 的 DA
//   [16]     rw         0=write，1=read
//   [15:8]   ccc_code   CCC code
//   [1]      is_ccc     0=private，1=CCC
//   [0]      is_direct  0=broadcast CCC，1=direct CCC
`define CMD_LEN           31:24
`define CMD_ADDR          23:17
`define CMD_RW            16
`define CMD_CCC_CODE      15:8
`define CMD_IS_CCC        1
`define CMD_IS_DIRECT     0

// Response descriptor 字段，位于 resp_fifo 的 32-bit word 中
//   [1]  nack_err    地址阶段 NACK
//   [0]  parity_err  I3C write 的 T-bit parity 错误
`define RESP_NACK         1
`define RESP_PARITY       0

// CCC command code
`define CCC_ENTDAA        8'h07   // broadcast：进入动态地址分配
`define CCC_RSTDAA        8'h06   // broadcast：复位动态地址
`define CCC_ENEC          8'h00   // broadcast：使能事件，如 IBI
`define CCC_DISEC         8'h01   // broadcast：关闭事件
`define CCC_SETMWL        8'h09   // broadcast：设置最大写长度
`define CCC_SETMRL        8'h0A   // broadcast：设置最大读长度
`define CCC_GETSTATUS     8'h90   // direct read：读取设备状态
`define CCC_GETMWL        8'h8B   // direct read：读取最大写长度
`define CCC_GETMRL        8'h8E   // direct read：读取最大读长度
`define CCC_SETDASA       8'h87   // direct write：由静态地址设置动态地址

// ENTDAA 动态地址池：0x01–0x7D 可用，0x7E 为 broadcast，0x7F 保留
`define DAT_ADDR_FIRST    7'h01
`define DAT_ADDR_LAST     7'h7D
`define DAT_POOL_SIZE     125    // 0x01..0x7D

`endif // I3C_DEFINES_VH
