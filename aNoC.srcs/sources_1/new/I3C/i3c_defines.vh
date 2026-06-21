`ifndef I3C_DEFINES_VH
`define I3C_DEFINES_VH

// ============================================================
// CCC Codes (Common Command Codes)
// ============================================================
// Broadcast CCC codes (sent to 0x7E)
`define CCC_ENEC        8'h00   // Enable Events Command (broadcast)
`define CCC_DISEC       8'h01   // Disable Events Command (broadcast)
`define CCC_ENTAS0      8'h02   // Enter Activity State 0 (broadcast)
`define CCC_ENTAS1      8'h03   // Enter Activity State 1 (broadcast)
`define CCC_ENTAS2      8'h04   // Enter Activity State 2 (broadcast)
`define CCC_ENTAS3      8'h05   // Enter Activity State 3 (broadcast)
`define CCC_RSTDAA      8'h06   // Reset Dynamic Address Assignment (broadcast)
`define CCC_ENTDAA      8'h07   // Enter Dynamic Address Assignment (broadcast)
`define CCC_DEFSLVS     8'h08   // Define List of Slaves (broadcast)
`define CCC_SETMWL      8'h09   // Set Max Write Length (broadcast)
`define CCC_SETMRL      8'h0A   // Set Max Read Length (broadcast)
`define CCC_ENTTM       8'h0B   // Enter Test Mode (broadcast)
`define CCC_SETBUSCON   8'h0C   // Set Bus Context (broadcast)
`define CCC_ENDXFER     8'h12   // End of Transfer (broadcast)
`define CCC_ENTHDR0     8'h20   // Enter HDR Mode 0 (broadcast)
`define CCC_ENTHDR1     8'h21   // Enter HDR Mode 1 (broadcast)
`define CCC_ENTHDR2     8'h22   // Enter HDR Mode 2 (broadcast)
`define CCC_SETXTIME    8'h28   // Exchange Timing Information (broadcast)
`define CCC_SETAASA     8'h29   // Set All Addresses to Static Addresses (broadcast)

// Direct CCC codes
`define CCC_ENEC_D      8'h80   // Enable Events Command (direct)
`define CCC_DISEC_D     8'h81   // Disable Events Command (direct)
`define CCC_ENTAS0_D    8'h82   // Enter Activity State 0 (direct)
`define CCC_ENTAS1_D    8'h83   // Enter Activity State 1 (direct)
`define CCC_ENTAS2_D    8'h84   // Enter Activity State 2 (direct)
`define CCC_ENTAS3_D    8'h85   // Enter Activity State 3 (direct)
`define CCC_SETDASA     8'h87   // Set Dynamic Address from Static Address (direct)
`define CCC_SETNEWDA    8'h88   // Set New Dynamic Address (direct)
`define CCC_SETMWL_D    8'h89   // Set Max Write Length (direct)
`define CCC_SETMRL_D    8'h8A   // Set Max Read Length (direct)
`define CCC_GETMWL      8'h8B   // Get Max Write Length (direct)
`define CCC_GETMRL      8'h8C   // Get Max Read Length (direct)
`define CCC_GETPID      8'h8D   // Get Provisioned ID (direct)
`define CCC_GETBCR      8'h8E   // Get Bus Characteristics Register (direct)
`define CCC_GETDCR      8'h8F   // Get Device Characteristics Register (direct)
`define CCC_GETSTATUS   8'h90   // Get Device Status (direct)
`define CCC_GETACCMST   8'h91   // Get Accept Mastership (direct)
`define CCC_SETBRGTGT   8'h93   // Set Bridge Targets (direct)
`define CCC_GETMXDS     8'h94   // Get Max Data Speed (direct)
`define CCC_GETHDRCAP   8'h95   // Get HDR Capability (direct)
`define CCC_SETXTIME_D  8'h98   // Exchange Timing Information (direct)
`define CCC_GETXTIME    8'h99   // Get Exchange Timing Information (direct)

// ============================================================
// I3C Broadcast Address
// ============================================================
`define I3C_BCAST_ADDR  7'h7E   // I3C broadcast address

// ============================================================
// Command Types (CMD register [27:24])
// ============================================================
`define CMD_PRIV_WR     4'd0    // SDR private write
`define CMD_PRIV_RD     4'd1    // SDR private read
`define CMD_BC_CCC      4'd2    // Broadcast CCC
`define CMD_DC_CCC_WR   4'd3    // Direct CCC write
`define CMD_DC_CCC_RD   4'd4    // Direct CCC read
`define CMD_ENTDAA      4'd5    // Dynamic Address Assignment
`define CMD_I2C_WR      4'd6    // I2C private write
`define CMD_I2C_RD      4'd7    // I2C private read

// ============================================================
// Bit-Level Controller Operations (cmd[2:0])
// ============================================================
`define BC_IDLE         3'd0    // No operation
`define BC_START        3'd1    // Generate START condition
`define BC_RSTART       3'd2    // Generate Repeated START condition
`define BC_WRITE        3'd3    // Write one bit
`define BC_READ         3'd4    // Read one bit
`define BC_STOP         3'd5    // Generate STOP condition

// ============================================================
// APB Register Offsets (byte addresses)
// ============================================================
`define REG_CTRL        8'h00   // Control register
`define REG_STATUS      8'h04   // Status register
`define REG_INTR_EN     8'h08   // Interrupt enable register
`define REG_INTR_ST     8'h0C   // Interrupt status register (W1C)
`define REG_TIMING0     8'h10   // SCL high period count
`define REG_TIMING1     8'h14   // SCL low period count
`define REG_TIMING2     8'h18   // SDA hold count
`define REG_TIMING3     8'h1C   // Bus idle count
`define REG_CMD         8'h20   // Command register
`define REG_TX_DATA     8'h24   // TX FIFO write port (WO)
`define REG_RX_DATA     8'h28   // RX FIFO read port (RO)
`define REG_IBI_CTRL    8'h2C   // IBI control
`define REG_IBI_INFO    8'h30   // IBI information (RO)
`define REG_DAA_ADDR    8'h34   // Dynamic address for DAA
`define REG_FIFO_ST     8'h38   // FIFO status (RO)

// ============================================================
// CTRL Register Bit Positions
// ============================================================
`define CTRL_EN         0       // Controller enable
`define CTRL_START      1       // Start transaction (W1S, self-clears)
`define CTRL_ABORT      2       // Abort current transaction
`define CTRL_SWRST      3       // Software reset (self-clears)

// ============================================================
// STATUS Register Bit Positions
// ============================================================
`define STAT_BUSY       0       // Transaction in progress
`define STAT_ARB_LOST   1       // Arbitration lost
`define STAT_NACK_ERR   2       // NACK received (error)
`define STAT_IBI_REQ    3       // IBI request received
`define STAT_DAA_DONE   4       // DAA sequence complete
`define STAT_TX_FULL    5       // TX FIFO full
`define STAT_TX_EMPTY   6       // TX FIFO empty
`define STAT_RX_FULL    7       // RX FIFO full
`define STAT_RX_EMPTY   8       // RX FIFO empty
`define STAT_DONE       9       // Transaction done

// ============================================================
// INTR_EN / INTR_ST Bit Positions
// ============================================================
`define INTR_DONE       0       // Transaction done interrupt
`define INTR_NACK       1       // NACK error interrupt
`define INTR_ARB_LOST   2       // Arbitration lost interrupt
`define INTR_IBI        3       // IBI received interrupt
`define INTR_DAA_DONE   4       // DAA done interrupt
`define INTR_TX_EMPTY   5       // TX FIFO empty interrupt
`define INTR_RX_FULL    6       // RX FIFO full interrupt

// ============================================================
// IBI_CTRL Register Bit Positions
// ============================================================
`define IBI_EN          0       // IBI detection enable
`define IBI_DATA_EN     1       // IBI mandatory data byte enable
`define IBI_AUTO_ACK    2       // Auto-ACK IBI requests

// ============================================================
// CMD Register Bit Fields
// ============================================================
`define CMD_CCC_CODE    7:0     // CCC code field
`define CMD_DATA_LEN    15:8    // Data length field
`define CMD_TGT_ADDR    22:16   // Target 7-bit address field
`define CMD_TYPE        27:24   // Command type field
`define CMD_I2C_MODE    28      // I2C mode flag

// ============================================================
// FIFO Parameters
// ============================================================
`define FIFO_DEPTH      16
`define FIFO_DATA_W     8
`define FIFO_CNT_W      5       // log2(DEPTH)+1

// ============================================================
// Default Timing Values (for ~12.5MHz I3C at 100MHz clk)
// ============================================================
`define DEF_HI_CNT      16'd4   // SCL high period: 4 cycles @ 100MHz = 40ns
`define DEF_LO_CNT      16'd4   // SCL low period:  4 cycles @ 100MHz = 40ns
`define DEF_HD_CNT      16'd1   // SDA hold time:   1 cycle  @ 100MHz = 10ns
`define DEF_IDLE_CNT    16'd8   // Bus idle:         8 cycles @ 100MHz = 80ns

// ============================================================
// Odd Parity Helper (used inline)
// ============================================================
// Odd parity for 7-bit address: ^addr gives even parity bit,
// so parity bit = ~(^addr) for odd parity per I3C spec.

`endif // I3C_DEFINES_VH
