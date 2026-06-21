`include "i3c_defines.vh"

module i3c_top (
    // APB slave interface
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [7:0]  PADDR,
    input  wire [31:0] PWDATA,
    output reg  [31:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,

    // IRQ output
    output wire        IRQ,

    // I3C bus signals
    output wire        SCL,
    inout  wire        SDA
);

    // -------------------------------------------------------
    // APB always ready, no error
    // -------------------------------------------------------
    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    // -------------------------------------------------------
    // Internal registers
    // -------------------------------------------------------
    reg [31:0] reg_ctrl;
    reg [31:0] reg_intr_en;
    reg [31:0] reg_intr_st;
    reg [15:0] reg_timing0;  // SCL high count
    reg [15:0] reg_timing1;  // SCL low count
    reg [15:0] reg_timing2;  // SDA hold count
    reg [15:0] reg_timing3;  // bus idle count
    reg [31:0] reg_cmd;
    reg [31:0] reg_ibi_ctrl;
    reg [31:0] reg_ibi_info;
    reg [6:0]  reg_daa_addr;

    // Internal signals from submodules
    wire        ctrl_en;
    wire        sw_abort;

    // TX FIFO signals
    wire        tx_wr_en;
    wire [7:0]  tx_wr_data;
    wire        tx_rd_en;
    wire [7:0]  tx_rd_data;
    wire        tx_full;
    wire        tx_empty;
    wire [4:0]  tx_count;

    // RX FIFO signals
    wire        rx_rd_en;
    wire [7:0]  rx_rd_data;
    wire        rx_wr_en;
    wire [7:0]  rx_wr_data;
    wire        rx_full;
    wire        rx_empty;
    wire [4:0]  rx_count;

    // Bit-ctrl signals
    wire [2:0]  bc_cmd;
    wire        bc_cmd_bit;
    wire        bc_cmd_valid;
    wire        bc_cmd_ready;
    wire        bc_rd_bit;
    wire        bc_rd_valid;
    wire        scl_out_w;
    wire        sda_oe_w;
    wire        sda_out_w;
    wire        sda_in_w;
    wire        ibi_det_w;

    // ctrl signals
    wire        ctrl_busy;
    wire        ctrl_done;
    wire        ctrl_nack_err;
    wire        ctrl_arb_lost;
    wire        ctrl_ibi_active;
    wire        ctrl_daa_done;
    wire [6:0]  ctrl_ibi_src_addr;
    wire [7:0]  ctrl_ibi_data_byte;
    wire        ctrl_ibi_data_vld;

    // Internal control
    reg         start_r;        // one-cycle start pulse to ctrl
    reg         swrst_r;        // software reset
    reg  [1:0]  done_sync;      // edge detect on done

    // -------------------------------------------------------
    // Bus signal tristate
    // -------------------------------------------------------
    assign SCL    = scl_out_w;
    assign SDA    = sda_oe_w ? sda_out_w : 1'bz;
    assign sda_in_w = SDA;

    // -------------------------------------------------------
    // Convenience register field decodes
    // -------------------------------------------------------
    assign ctrl_en  = reg_ctrl[`CTRL_EN];
    assign sw_abort = reg_ctrl[`CTRL_ABORT];

    // -------------------------------------------------------
    // APB write decoder
    // -------------------------------------------------------
    wire apb_wr = PSEL & PENABLE & PWRITE;
    wire apb_rd = PSEL & PENABLE & ~PWRITE;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            reg_ctrl    <= 32'd0;
            reg_intr_en <= 32'd0;
            reg_intr_st <= 32'd0;
            reg_timing0 <= `DEF_HI_CNT;
            reg_timing1 <= `DEF_LO_CNT;
            reg_timing2 <= `DEF_HD_CNT;
            reg_timing3 <= `DEF_IDLE_CNT;
            reg_cmd     <= 32'd0;
            reg_ibi_ctrl<= 32'd0;
            reg_ibi_info<= 32'd0;
            reg_daa_addr<= 7'd0;
            start_r     <= 1'b0;
            swrst_r     <= 1'b0;
        end else begin
            // Self-clearing bits
            start_r <= 1'b0;
            swrst_r <= 1'b0;

            // Auto-clear START and SWRST in register
            if (reg_ctrl[`CTRL_START]) begin
                reg_ctrl[`CTRL_START] <= 1'b0;
                start_r               <= ctrl_en;
            end
            if (reg_ctrl[`CTRL_SWRST]) begin
                reg_ctrl[`CTRL_SWRST] <= 1'b0;
                swrst_r               <= 1'b1;
            end

            // Interrupt status: set on events
            if (ctrl_done)
                reg_intr_st[`INTR_DONE]     <= 1'b1;
            if (ctrl_nack_err)
                reg_intr_st[`INTR_NACK]     <= 1'b1;
            if (ctrl_arb_lost)
                reg_intr_st[`INTR_ARB_LOST] <= 1'b1;
            if (ctrl_daa_done)
                reg_intr_st[`INTR_DAA_DONE] <= 1'b1;
            if (ctrl_ibi_data_vld || ctrl_ibi_active)
                reg_intr_st[`INTR_IBI]      <= 1'b1;
            if (tx_empty)
                reg_intr_st[`INTR_TX_EMPTY] <= 1'b1;
            if (rx_full)
                reg_intr_st[`INTR_RX_FULL]  <= 1'b1;

            // IBI info update
            if (ctrl_ibi_active)
                reg_ibi_info[6:0] <= ctrl_ibi_src_addr;
            if (ctrl_ibi_data_vld)
                reg_ibi_info[15:8] <= ctrl_ibi_data_byte;

            // APB writes
            if (apb_wr) begin
                case (PADDR)
                    `REG_CTRL: begin
                        reg_ctrl <= PWDATA;
                        if (PWDATA[`CTRL_START] && ctrl_en)
                            start_r <= 1'b1;
                        if (PWDATA[`CTRL_SWRST])
                            swrst_r <= 1'b1;
                    end
                    `REG_INTR_EN: reg_intr_en <= PWDATA;
                    `REG_INTR_ST: reg_intr_st <= reg_intr_st & ~PWDATA; // W1C
                    `REG_TIMING0: reg_timing0 <= PWDATA[15:0];
                    `REG_TIMING1: reg_timing1 <= PWDATA[15:0];
                    `REG_TIMING2: reg_timing2 <= PWDATA[15:0];
                    `REG_TIMING3: reg_timing3 <= PWDATA[15:0];
                    `REG_CMD:     reg_cmd     <= PWDATA;
                    `REG_IBI_CTRL:reg_ibi_ctrl<= PWDATA;
                    `REG_DAA_ADDR:reg_daa_addr<= PWDATA[6:0];
                    default: ;
                endcase
            end
        end
    end

    // -------------------------------------------------------
    // APB read decoder
    // -------------------------------------------------------
    wire [31:0] status_word;
    assign status_word = {22'd0,
                          rx_empty,           // [8]
                          rx_full,            // [7]
                          tx_empty,           // [6]
                          tx_full,            // [5]
                          ctrl_daa_done,      // [4]
                          ctrl_ibi_active,    // [3]
                          ctrl_nack_err,      // [2]
                          ctrl_arb_lost,      // [1]
                          ctrl_busy           // [0]
                         };

    wire [31:0] fifo_st_word;
    assign fifo_st_word = {19'd0, rx_count, 3'd0, tx_count};

    always @(*) begin
        PRDATA = 32'd0;
        if (apb_rd) begin
            case (PADDR)
                `REG_CTRL:     PRDATA = reg_ctrl;
                `REG_STATUS:   PRDATA = status_word;
                `REG_INTR_EN:  PRDATA = reg_intr_en;
                `REG_INTR_ST:  PRDATA = reg_intr_st;
                `REG_TIMING0:  PRDATA = {16'd0, reg_timing0};
                `REG_TIMING1:  PRDATA = {16'd0, reg_timing1};
                `REG_TIMING2:  PRDATA = {16'd0, reg_timing2};
                `REG_TIMING3:  PRDATA = {16'd0, reg_timing3};
                `REG_CMD:      PRDATA = reg_cmd;
                `REG_RX_DATA:  PRDATA = {24'd0, rx_rd_data};
                `REG_IBI_CTRL: PRDATA = reg_ibi_ctrl;
                `REG_IBI_INFO: PRDATA = reg_ibi_info;
                `REG_DAA_ADDR: PRDATA = {25'd0, reg_daa_addr};
                `REG_FIFO_ST:  PRDATA = fifo_st_word;
                default:       PRDATA = 32'd0;
            endcase
        end
    end

    // -------------------------------------------------------
    // TX FIFO write (from APB TX_DATA register write)
    // -------------------------------------------------------
    assign tx_wr_en   = apb_wr && (PADDR == `REG_TX_DATA);
    assign tx_wr_data = PWDATA[7:0];

    // -------------------------------------------------------
    // RX FIFO read (from APB RX_DATA register read)
    // -------------------------------------------------------
    assign rx_rd_en = apb_rd && (PADDR == `REG_RX_DATA);

    // -------------------------------------------------------
    // IRQ generation
    // -------------------------------------------------------
    assign IRQ = |(reg_intr_st[6:0] & reg_intr_en[6:0]);

    // -------------------------------------------------------
    // Software reset: generate async-capable reset for submodules
    // We use synchronous reset via swrst_r to avoid glitch issues
    // -------------------------------------------------------

    // -------------------------------------------------------
    // TX FIFO
    // -------------------------------------------------------
    i3c_fifo #(
        .DATA_W(8),
        .DEPTH (16),
        .CNT_W (5)
    ) u_tx_fifo (
        .clk     (PCLK),
        .rst_n   (PRESETn & ~swrst_r),
        .wr_en   (tx_wr_en),
        .wr_data (tx_wr_data),
        .rd_en   (tx_rd_en),
        .rd_data (tx_rd_data),
        .full    (tx_full),
        .empty   (tx_empty),
        .count   (tx_count)
    );

    // -------------------------------------------------------
    // RX FIFO
    // -------------------------------------------------------
    i3c_fifo #(
        .DATA_W(8),
        .DEPTH (16),
        .CNT_W (5)
    ) u_rx_fifo (
        .clk     (PCLK),
        .rst_n   (PRESETn & ~swrst_r),
        .wr_en   (rx_wr_en),
        .wr_data (rx_wr_data),
        .rd_en   (rx_rd_en),
        .rd_data (rx_rd_data),
        .full    (rx_full),
        .empty   (rx_empty),
        .count   (rx_count)
    );

    // -------------------------------------------------------
    // Bit-level controller
    // -------------------------------------------------------
    i3c_bit_ctrl u_bit_ctrl (
        .clk         (PCLK),
        .rst_n       (PRESETn & ~swrst_r),
        .cfg_hi_cnt  (reg_timing0),
        .cfg_lo_cnt  (reg_timing1),
        .cfg_hd_cnt  (reg_timing2),
        .cfg_idle_cnt(reg_timing3),
        .cmd         (bc_cmd),
        .cmd_bit     (bc_cmd_bit),
        .cmd_valid   (bc_cmd_valid),
        .cmd_ready   (bc_cmd_ready),
        .rd_bit      (bc_rd_bit),
        .rd_valid    (bc_rd_valid),
        .scl_out     (scl_out_w),
        .sda_oe      (sda_oe_w),
        .sda_out     (sda_out_w),
        .sda_in      (sda_in_w),
        .ibi_det     (ibi_det_w)
    );

    // -------------------------------------------------------
    // Frame-level controller
    // -------------------------------------------------------
    i3c_ctrl u_ctrl (
        .clk             (PCLK),
        .rst_n           (PRESETn & ~swrst_r),
        .cmd_type        (reg_cmd[`CMD_TYPE]),
        .tgt_addr        (reg_cmd[`CMD_TGT_ADDR]),
        .ccc_code        (reg_cmd[`CMD_CCC_CODE]),
        .data_len        (reg_cmd[`CMD_DATA_LEN]),
        .i2c_mode        (reg_cmd[`CMD_I2C_MODE]),
        .cfg_daa_addr    (reg_daa_addr),
        .ibi_en          (reg_ibi_ctrl[`IBI_EN]),
        .ibi_data_en     (reg_ibi_ctrl[`IBI_DATA_EN]),
        .ibi_auto_ack    (reg_ibi_ctrl[`IBI_AUTO_ACK]),
        .start           (start_r),
        .abort           (sw_abort),
        .tx_rd_en        (tx_rd_en),
        .tx_rd_data      (tx_rd_data),
        .tx_empty        (tx_empty),
        .rx_wr_en        (rx_wr_en),
        .rx_wr_data      (rx_wr_data),
        .rx_full         (rx_full),
        .ibi_det         (ibi_det_w),
        .bc_cmd          (bc_cmd),
        .bc_cmd_bit      (bc_cmd_bit),
        .bc_cmd_valid    (bc_cmd_valid),
        .bc_cmd_ready    (bc_cmd_ready),
        .bc_rd_bit       (bc_rd_bit),
        .bc_rd_valid     (bc_rd_valid),
        .busy            (ctrl_busy),
        .done            (ctrl_done),
        .nack_err        (ctrl_nack_err),
        .arb_lost        (ctrl_arb_lost),
        .ibi_active      (ctrl_ibi_active),
        .daa_done        (ctrl_daa_done),
        .ibi_src_addr    (ctrl_ibi_src_addr),
        .ibi_data_byte   (ctrl_ibi_data_byte),
        .ibi_data_vld    (ctrl_ibi_data_vld)
    );

endmodule
