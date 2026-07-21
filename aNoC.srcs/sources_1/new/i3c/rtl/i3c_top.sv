`default_nettype none
`include "i3c_defines.vh"

// I3C Master Controller 顶层结构模块。
//
// 层级结构：
//   APB slave + CSR regs + FIFOs
//     └─ Dispatch FSM  读取 cmd_fifo，启动 private 或 CCC 传输
//          ├─ frame_scheduler  private transfer
//          └─ ccc_handler      CCC，包含 ENTDAA
//               └─ entdaa      (instantiated inside ccc_handler)
//          └─── byte_serializer
//                   └─ line_controller ──► SCL / SDA pads
//   ibi_arbiter  监测总线，并可旁路接入 line_controller
//
// Mux 1：serializer 上游在 frame_scheduler / ccc_handler 之间选择。
// Mux 2：LC 上游在 byte_serializer / ENTDAA / IBI 之间选择。
//
// Dispatch FSM：取出命令描述符，等待传输完成，再写入 response FIFO。

module i3c_top (
    // APB master 接口
    input  logic        PCLK,
    input  logic        PRESETn,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic        PWRITE,
    input  logic [11:0] PADDR,
    input  logic [31:0] PWDATA,
    input  logic [3:0]  PSTRB,
    output logic [31:0] PRDATA,
    output logic        PREADY,
    output logic        PSLVERR,

    // I3C pad 拆分接口，wrapper 中连接到 IOBUF
    input  logic        SCL_IN,
    output logic        SCL_OE,
    output logic        SCL_OUT,
    input  logic        SDA_IN,
    output logic        SDA_OE,
    output logic        SDA_OUT,

    // 中断输出
    output logic        IRQ
);

// 内部复位：sw_rst 只复位非 CSR 模块
logic sw_rst;
logic int_rst_n;
assign int_rst_n = PRESETn & ~sw_rst;

// APB 地址译码
logic is_fifo_access;
assign is_fifo_access =
    (PADDR[7:0] == `CMD_PORT)  ||
    (PADDR[7:0] == `RESP_PORT) ||
    (PADDR[7:0] == `TX_PORT)   ||
    (PADDR[7:0] == `RX_PORT);   // 0x20–0x3F

// FIFO 访问直接由 APB 地址译码，不经过 csr_regs
logic cmd_wr_en, tx_wr_en, resp_rd_en, rx_rd_en;
assign cmd_wr_en  = PSEL & PENABLE &  PWRITE & (PADDR[7:0] == `CMD_PORT) & (PSTRB == 4'b1111); // 写 command FIFO
assign tx_wr_en   = PSEL & PENABLE &  PWRITE & (PADDR[7:0] == `TX_PORT)  & PSTRB[0];  // 写 TX FIFO
assign resp_rd_en = PSEL & PENABLE & !PWRITE & (PADDR[7:0] == `RESP_PORT);// 读 response FIFO
assign rx_rd_en   = PSEL & PENABLE & !PWRITE & (PADDR[7:0] == `RX_PORT);  // 读 RX FIFO

// APB slave 输出的 CSR 内部寄存器总线
logic [7:0]  reg_addr;
logic [31:0] reg_wdata;
logic [3:0]  reg_wstrb;
logic        reg_wr_en_raw;    // apb_slave 原始写使能
logic        reg_wr_en;
logic [31:0] apb_prdata_int;   // apb_slave 读数据，顶层不用它直连 PRDATA
logic [31:0] csr_rdata;

assign reg_wr_en = reg_wr_en_raw & ~is_fifo_access;

// PRDATA mux：CSR 或 FIFO 数据
logic [31:0] resp_rd_data;
logic [7:0]  rx_rd_data;
always_comb begin
    case (PADDR[7:0])
        `RESP_PORT: PRDATA = resp_rd_data;
        `RX_PORT:   PRDATA = {24'd0, rx_rd_data};
        default:    PRDATA = csr_rdata;
    endcase
end

// CSR 输出
logic [15:0] scl_high_period, scl_low_period, sda_hold_time;
logic        i3c_mode, core_en, ibi_en, ibi_mdb_en;
logic        hw_busy, hw_ibi_pending;
logic [6:0]  hw_ibi_addr;
logic        hw_ibi_mdb;
logic [7:0]  hw_ibi_len;
logic        hw_ibi_set, hw_parity_err_set, hw_nack_err_set;

// FIFO 信号
logic [31:0] cmd_rd_data;
logic        cmd_rd_en, cmd_empty, cmd_full;

logic [31:0] resp_wr_data;
logic        resp_wr_en, resp_empty, resp_full;

logic [7:0]  tx_rd_data;
logic        tx_rd_en, tx_empty, tx_full;

logic [7:0]  rx_wr_data;
logic        rx_wr_en, rx_empty, rx_full;

// Dispatch FSM
typedef enum logic [1:0] {
    DS_IDLE  = 2'd0,
    DS_FETCH = 2'd1,
    DS_RUN   = 2'd2,
    DS_RESP  = 2'd3
} ds_t;
ds_t ds_state;

// 锁存后的命令描述符字段
logic [7:0]  ds_len;
logic [6:0]  ds_addr;
logic        ds_rw;
logic [7:0]  ds_ccc_code;
logic        ds_is_ccc;
logic        ds_is_direct;
logic        ds_started;

// 当前活动模块的完成信号
logic ds_done, ds_nack;
logic ds_parity_err;

// 子模块完成信号
logic sched_xfer_done, sched_xfer_nack;
logic ccc_done, ccc_nack;

// serializer 状态输出
logic        ser_cmd_ready;
logic [7:0]  ser_rx_data;
logic        ser_byte_done, ser_ack_ok, ser_parity_err;
logic        ser_read_continue;

// serializer、ENTDAA、IBI 共用 LC 反馈
logic        lc_cmd_ready, lc_sda_rx, lc_sda_rx_valid;

assign ds_done       = ds_is_ccc ? ccc_done       : sched_xfer_done;
assign ds_nack       = ds_is_ccc ? ccc_nack        : sched_xfer_nack;
// 子模块完成/错误是单周期 pulse，这里锁存到 DS_RESP 写 response。
logic nack_seen;
logic parity_seen;
always_ff @(posedge PCLK or negedge int_rst_n) begin
    if (!int_rst_n) begin
        nack_seen   <= 1'b0;
        parity_seen <= 1'b0;
    end else if (ds_state == DS_IDLE) begin
        nack_seen   <= 1'b0;   // 命令之间清零
        parity_seen <= 1'b0;
    end else begin
        if (ds_nack)        nack_seen   <= 1'b1;
        if (ser_parity_err) parity_seen <= 1'b1;
    end
end
assign ds_parity_err = parity_seen;

// IBI 会阻塞命令派发；只有主传输路径和 LC 都空闲时才允许检测 IBI。
logic ibi_req;
assign hw_busy = (ds_state != DS_IDLE) | ibi_req;

always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        ds_state    <= DS_IDLE;
        ds_len      <= '0;
        ds_addr     <= '0;
        ds_rw       <= 1'b0;
        ds_ccc_code <= '0;
        ds_is_ccc   <= 1'b0;
        ds_is_direct<= 1'b0;
        ds_started  <= 1'b0;
    end else if (sw_rst) begin
        ds_state    <= DS_IDLE;
        ds_started  <= 1'b0;
    end else begin
        case (ds_state)
            DS_IDLE:
                if (!cmd_empty && !ibi_req && core_en)
                    ds_state <= DS_FETCH;
            DS_FETCH: begin
                    ds_len       <= cmd_rd_data[`CMD_LEN];
                    ds_addr      <= cmd_rd_data[`CMD_ADDR];
                    ds_rw        <= cmd_rd_data[`CMD_RW];
                    ds_ccc_code  <= cmd_rd_data[`CMD_CCC_CODE];
                    ds_is_ccc    <= cmd_rd_data[`CMD_IS_CCC];
                    ds_is_direct <= cmd_rd_data[`CMD_IS_DIRECT];
                    ds_started   <= 1'b0;
                    ds_state     <= DS_RUN;
            end
            DS_RUN: begin
                if (!ds_started)
                    ds_started <= 1'b1;
                if (ds_done || ds_nack)
                    ds_state <= DS_RESP;
            end
            DS_RESP:
                if (!resp_full)
                    ds_state <= DS_IDLE;
            default: ds_state <= DS_IDLE;
        endcase
    end
end

// DS_FETCH 时 cmd_rd_data 仍指向 FIFO 队首，字段采样后指针再前进。
assign cmd_rd_en  = (ds_state == DS_FETCH) && !cmd_empty && !ibi_req && core_en;

// 传输完成后写 response FIFO
assign resp_wr_en   = (ds_state == DS_RESP) && !resp_full;
assign resp_wr_data = {30'd0, nack_seen, ds_parity_err};

// Mux 1：serializer 上游选择 frame_scheduler 或 ccc_handler
logic use_ccc;
assign use_ccc = ds_is_ccc && (ds_state == DS_RUN);

// frame_scheduler 输出
logic [1:0]  s_cmd;  logic [7:0] s_tx;
logic        s_is_read, s_is_addr, s_tbit_cont, s_cmd_valid;

// ccc_handler 输出
logic [1:0]  c_cmd;  logic [7:0] c_tx;
logic        c_is_read, c_is_addr, c_tbit_cont, c_cmd_valid;

// mux 后送入 serializer
logic [1:0]  ser_cmd;   logic [7:0] ser_tx_data;
logic        ser_is_read, ser_is_addr, ser_tbit_cont, ser_cmd_valid;
// 选择 CCC 或 private 数据路径
assign ser_cmd       = use_ccc ? c_cmd       : s_cmd;
assign ser_tx_data   = use_ccc ? c_tx        : s_tx;
assign ser_is_read   = use_ccc ? c_is_read   : s_is_read;
assign ser_is_addr   = use_ccc ? c_is_addr   : s_is_addr;
assign ser_tbit_cont = use_ccc ? c_tbit_cont : s_tbit_cont;
assign ser_cmd_valid = use_ccc ? c_cmd_valid : s_cmd_valid;

// TX/RX FIFO 路由
logic sched_tx_ready, ccc_tx_ready;
logic [7:0] sched_rx_byte; logic sched_rx_valid;
logic [7:0] ccc_rx_byte;   logic ccc_rx_valid;

assign tx_rd_en  = use_ccc ? ccc_tx_ready : sched_tx_ready;
// rx_wr_en/rx_wr_data 在后面的 always_comb 中统一处理，包含 IBI 情况

// Mux 2：LC 上游选择 byte_serializer、ENTDAA 或 IBI
logic ibi_grant;
assign ibi_grant = ibi_req && (ds_state == DS_IDLE) && core_en;
logic ibi_bus_idle;
assign ibi_bus_idle = (ds_state == DS_IDLE) && cmd_empty && lc_cmd_ready && SCL_IN;

// byte_serializer 到 LC
logic [1:0]  bs_lc_cmd;  logic bs_lc_sda_tx, bs_lc_cmd_valid, bs_lc_open_drain;
// ENTDAA 到 LC 的旁路
logic        entdaa_lc_active;
logic [1:0]  entdaa_lc_cmd;
logic        entdaa_lc_sda_tx, entdaa_lc_cmd_valid, entdaa_lc_open_drain;
// IBI arbiter 到 LC
logic [1:0]  ib_lc_cmd;  logic ib_lc_sda_tx, ib_lc_cmd_valid, ib_lc_open_drain;

logic [1:0]  lc_cmd;
logic        lc_sda_tx, lc_cmd_valid, lc_open_drain;

assign lc_cmd        = ibi_grant        ? ib_lc_cmd             :
                       entdaa_lc_active ? entdaa_lc_cmd         : bs_lc_cmd;
assign lc_sda_tx     = ibi_grant        ? ib_lc_sda_tx          :
                       entdaa_lc_active ? entdaa_lc_sda_tx      : bs_lc_sda_tx;
assign lc_cmd_valid  = ibi_grant        ? ib_lc_cmd_valid       :
                       entdaa_lc_active ? entdaa_lc_cmd_valid   : bs_lc_cmd_valid;
assign lc_open_drain = ibi_grant        ? ib_lc_open_drain      :
                       entdaa_lc_active ? entdaa_lc_open_drain  : bs_lc_open_drain;

// IBI 状态更新到 CSR
logic [6:0]  ibi_addr;
logic [7:0]  ibi_mdb_data;
logic        ibi_mdb_valid, ibi_done, ibi_nacked;

assign hw_ibi_set     = ibi_done;
assign hw_ibi_addr    = ibi_addr;
assign hw_ibi_mdb     = ibi_mdb_valid;
assign hw_ibi_len     = ibi_mdb_valid ? 8'd1 : 8'd0;
assign hw_ibi_pending = ibi_req;

// IBI 的 MDB 写入 RX FIFO；IBI 只在 DS_IDLE 活动，不会与普通传输冲突。
always_comb begin
    if (ibi_mdb_valid) begin
        rx_wr_en   = 1'b1;
        rx_wr_data = ibi_mdb_data;
    end else if (use_ccc) begin
        rx_wr_en   = ccc_rx_valid;
        rx_wr_data = ccc_rx_byte;
    end else begin
        rx_wr_en   = sched_rx_valid;
        rx_wr_data = sched_rx_byte;
    end
end

// Parity/NACK 错误更新到 CSR
assign hw_parity_err_set = ser_parity_err;
assign hw_nack_err_set   = ds_nack;

// ENTDAA 地址池，简单计数器，DA 范围 0x01–0x7D
logic [6:0] dat_ptr;
logic       dat_valid_sig, dat_rd_sig;
logic [63:0] dev_pid;  logic [6:0] dev_da;  logic dev_valid_sig;

assign dat_valid_sig = (dat_ptr <= `DAT_ADDR_LAST);

always_ff @(posedge PCLK or negedge int_rst_n) begin
    if (!int_rst_n) dat_ptr <= `DAT_ADDR_FIRST;
    else if (dat_rd_sig && dat_valid_sig) dat_ptr <= dat_ptr + 7'd1;
end

// IRQ 电平中断：response、IBI 或 error 需要软件服务时置位
logic irq_r;
logic ibi_status_clr;
assign ibi_status_clr = reg_wr_en && (reg_addr == `REG_IBI_STATUS) 
                        && reg_wstrb[2] && reg_wdata[16];
always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn)              irq_r <= 1'b0;
    else if (sw_rst)           irq_r <= 1'b0;
    else if (resp_wr_en || ibi_done || ds_nack || ser_parity_err)
                               irq_r <= 1'b1;
    else if (ibi_status_clr)   irq_r <= 1'b0;   // 软件清 IBI_STATUS
    else if (resp_rd_en)       irq_r <= 1'b0;   // 软件读取 response
end
assign IRQ = irq_r;

// 模块实例化

apb_slave u_apb (
    .PCLK(PCLK), .PRESETn(PRESETn),
    .PSEL(PSEL), .PENABLE(PENABLE), .PWRITE(PWRITE),
    .PADDR(PADDR), .PWDATA(PWDATA), .PSTRB(PSTRB),
    .PRDATA(apb_prdata_int),        // 顶层通过组合 mux 驱动 PRDATA
    .PREADY(PREADY), .PSLVERR(PSLVERR),
    .reg_addr(reg_addr), .reg_wdata(reg_wdata),.reg_wstrb (reg_wstrb),
    .reg_wr_en(reg_wr_en_raw), .reg_rdata(csr_rdata)
);

csr_regs u_csr (
    .clk(PCLK), .rst_n(PRESETn),
    .reg_addr(reg_addr), .reg_wdata(reg_wdata),
    .reg_wr_en(reg_wr_en), .reg_rdata(csr_rdata),.reg_wstrb (reg_wstrb),
    .scl_high_period(scl_high_period), .scl_low_period(scl_low_period),
    .sda_hold_time(sda_hold_time),
    .i3c_mode(i3c_mode), .core_en(core_en), .ibi_en(ibi_en),
    .ibi_mdb_en(ibi_mdb_en), .sw_rst(sw_rst),
    .hw_busy(hw_busy), .hw_ibi_pending(hw_ibi_pending),
    .hw_ibi_addr(hw_ibi_addr), .hw_ibi_mdb(hw_ibi_mdb),
    .hw_ibi_len(hw_ibi_len), .hw_ibi_set(hw_ibi_set),
    .hw_parity_err_set(hw_parity_err_set),
    .hw_nack_err_set(hw_nack_err_set),
    .hw_entdaa_pid(dev_pid),
    .hw_entdaa_da(dev_da),
    .hw_entdaa_valid(dev_valid_sig)
);

// FIFOs
sync_fifo #(.WIDTH(32), .DEPTH(8)) u_cmd_fifo (
    .clk(PCLK), .rst_n(int_rst_n),
    .wr_en(cmd_wr_en), .wr_data(PWDATA),
    .rd_en(cmd_rd_en), .rd_data(cmd_rd_data),
    .full(cmd_full),   .empty(cmd_empty)
);

sync_fifo #(.WIDTH(32), .DEPTH(8)) u_resp_fifo (
    .clk(PCLK), .rst_n(int_rst_n),
    .wr_en(resp_wr_en), .wr_data(resp_wr_data),
    .rd_en(resp_rd_en), .rd_data(resp_rd_data),
    .full(resp_full),   .empty(resp_empty)
);

sync_fifo #(.WIDTH(8), .DEPTH(32)) u_tx_fifo (
    .clk(PCLK), .rst_n(int_rst_n),
    .wr_en(tx_wr_en), .wr_data(PWDATA[7:0]),
    .rd_en(tx_rd_en), .rd_data(tx_rd_data),
    .full(tx_full),   .empty(tx_empty)
);

sync_fifo #(.WIDTH(8), .DEPTH(32)) u_rx_fifo (
    .clk(PCLK), .rst_n(int_rst_n),
    .wr_en(rx_wr_en), .wr_data(rx_wr_data),
    .rd_en(rx_rd_en), .rd_data(rx_rd_data),
    .full(rx_full),   .empty(rx_empty)
);

// Frame Scheduler
logic sched_xfer_valid, sched_xfer_ready;
assign sched_xfer_valid = (ds_state == DS_RUN) && !ds_is_ccc && !ds_started;

frame_scheduler u_sched (
    .clk(PCLK), .rst_n(int_rst_n),
    .xfer_addr(ds_addr), .xfer_rw(ds_rw), .xfer_len(ds_len),
    .xfer_valid(sched_xfer_valid), .xfer_ready(sched_xfer_ready),
    .tx_byte(tx_rd_data), .tx_valid(!tx_empty), .tx_ready(sched_tx_ready),
    .rx_byte(sched_rx_byte), .rx_valid(sched_rx_valid),
    .xfer_done(sched_xfer_done), .xfer_nack(sched_xfer_nack),
    .ser_cmd(s_cmd), .ser_tx_data(s_tx),
    .ser_is_read(s_is_read), .ser_is_addr(s_is_addr),
    .ser_tbit_cont(s_tbit_cont), .ser_cmd_valid(s_cmd_valid),
    .ser_cmd_ready(ser_cmd_ready), .ser_rx_data(ser_rx_data),
    .ser_byte_done(ser_byte_done), .ser_ack_ok(ser_ack_ok),
    .ser_read_continue(ser_read_continue),
    .ser_parity_err(ser_parity_err)
);

// CCC Handler
logic ccc_valid_sig, ccc_ready_sig;
assign ccc_valid_sig = (ds_state == DS_RUN) && ds_is_ccc && !ds_started;

ccc_handler u_ccc (
    .clk(PCLK), .rst_n(int_rst_n),
    .ccc_type(ds_is_direct), .ccc_code(ds_ccc_code),
    .target_addr(ds_addr), .target_rw(ds_rw), .data_len(ds_len),
    .ccc_valid(ccc_valid_sig), .ccc_ready(ccc_ready_sig),
    .tx_byte(tx_rd_data), .tx_valid(!tx_empty), .tx_ready(ccc_tx_ready),
    .rx_byte(ccc_rx_byte), .rx_valid(ccc_rx_valid),
    .ccc_done(ccc_done), .ccc_nack(ccc_nack),
    .dat_addr(dat_ptr), .dat_valid(dat_valid_sig),
    .dat_rd(dat_rd_sig), .dev_pid(dev_pid),
    .dev_da(dev_da), .dev_valid(dev_valid_sig),
	    .ser_cmd(c_cmd), .ser_tx_data(c_tx),
	    .ser_is_read(c_is_read), .ser_is_addr(c_is_addr),
	    .ser_tbit_cont(c_tbit_cont), .ser_cmd_valid(c_cmd_valid),
	    .ser_cmd_ready(ser_cmd_ready), .ser_rx_data(ser_rx_data),
	    .ser_byte_done(ser_byte_done), .ser_ack_ok(ser_ack_ok),
	    .ser_read_continue(ser_read_continue),
	    .ser_parity_err(ser_parity_err),
	    .entdaa_lc_active(entdaa_lc_active),
	    .entdaa_lc_cmd(entdaa_lc_cmd),
	    .entdaa_lc_sda_tx(entdaa_lc_sda_tx),
	    .entdaa_lc_cmd_valid(entdaa_lc_cmd_valid),
	    .lc_cmd_ready(lc_cmd_ready),
	    .lc_sda_rx(lc_sda_rx),
	    .lc_sda_rx_valid(lc_sda_rx_valid),
	    .entdaa_lc_open_drain(entdaa_lc_open_drain)
	);

// Byte Serializer
byte_serializer u_ser (
    .clk(PCLK), .rst_n(int_rst_n),
    .i3c_mode(i3c_mode),
    .cmd(ser_cmd), .tx_data(ser_tx_data),
    .is_read(ser_is_read), .is_addr(ser_is_addr), .tbit_cont(ser_tbit_cont),
    .cmd_valid(ser_cmd_valid), .cmd_ready(ser_cmd_ready),
    .rx_data(ser_rx_data), .byte_done(ser_byte_done),
    .ack_ok(ser_ack_ok), .parity_err(ser_parity_err),
    .read_continue(ser_read_continue),
    .lc_cmd(bs_lc_cmd), .lc_sda_tx(bs_lc_sda_tx),
    .lc_cmd_valid(bs_lc_cmd_valid), .lc_cmd_ready(lc_cmd_ready),
    .lc_sda_rx(lc_sda_rx), .lc_sda_rx_valid(lc_sda_rx_valid),
    .lc_open_drain(bs_lc_open_drain)
);

// Line Controller
line_controller u_lc (
    .clk(PCLK), .rst_n(int_rst_n),
    .scl_high_period(scl_high_period), .scl_low_period(scl_low_period),
    .sda_hold_time(sda_hold_time), .open_drain_mode(lc_open_drain),
    .cmd(lc_cmd), .sda_tx(lc_sda_tx),
    .cmd_valid(lc_cmd_valid), .cmd_ready(lc_cmd_ready),
    .sda_rx(lc_sda_rx), .sda_rx_valid(lc_sda_rx_valid),
    .scl_oe(SCL_OE), .scl_out(SCL_OUT), .scl_in(SCL_IN),
    .sda_oe(SDA_OE), .sda_out(SDA_OUT), .sda_in(SDA_IN)
);

// IBI Arbiter
ibi_arbiter u_ibi (
    .clk(PCLK), .rst_n(int_rst_n),
    .bus_idle(ibi_bus_idle), .sda_in(SDA_IN),
    .ibi_en(ibi_en), .ibi_accept(1'b1), .ibi_mdb_en(ibi_mdb_en),
    .ibi_req(ibi_req), .ibi_grant(ibi_grant),
    .lc_cmd(ib_lc_cmd), .lc_sda_tx(ib_lc_sda_tx),
    .lc_cmd_valid(ib_lc_cmd_valid), .lc_cmd_ready(lc_cmd_ready),
    .lc_sda_rx(lc_sda_rx), .lc_sda_rx_valid(lc_sda_rx_valid),
    .lc_open_drain(ib_lc_open_drain),
    .ibi_addr(ibi_addr), .ibi_mdb_data(ibi_mdb_data),
    .ibi_mdb_valid(ibi_mdb_valid), .ibi_done(ibi_done),
    .ibi_nacked(ibi_nacked)
);

// 避免未使用信号告警
logic _unused;
assign _unused = &{apb_prdata_int, cmd_full, resp_empty, tx_full,
                   rx_full, rx_empty, sched_xfer_ready, ccc_ready_sig,
                   ibi_nacked, dev_pid, dev_da, dev_valid_sig};

endmodule
