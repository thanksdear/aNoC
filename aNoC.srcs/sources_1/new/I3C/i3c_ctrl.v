`include "i3c_defines.vh"

module i3c_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // Command configuration
    input  wire [3:0]  cmd_type,
    input  wire [6:0]  tgt_addr,
    input  wire [7:0]  ccc_code,
    input  wire [7:0]  data_len,
    input  wire        i2c_mode,

    // DAA configuration
    input  wire [6:0]  cfg_daa_addr,

    // IBI configuration
    input  wire        ibi_en,
    input  wire        ibi_data_en,
    input  wire        ibi_auto_ack,

    // Control
    input  wire        start,
    input  wire        abort,

    // TX FIFO interface
    output reg         tx_rd_en,
    input  wire [7:0]  tx_rd_data,
    input  wire        tx_empty,

    // RX FIFO interface
    output reg         rx_wr_en,
    output reg  [7:0]  rx_wr_data,
    input  wire        rx_full,

    // IBI detection
    input  wire        ibi_det,

    // Bit-ctrl interface
    output reg  [2:0]  bc_cmd,
    output reg         bc_cmd_bit,
    output reg         bc_cmd_valid,
    input  wire        bc_cmd_ready,
    input  wire        bc_rd_bit,
    input  wire        bc_rd_valid,

    // Status
    output reg         busy,
    output reg         done,
    output reg         nack_err,
    output reg         arb_lost,
    output reg         ibi_active,
    output reg         daa_done,

    // IBI info
    output reg  [6:0]  ibi_src_addr,
    output reg  [7:0]  ibi_data_byte,
    output reg         ibi_data_vld
);

    // -------------------------------------------------------
    // State encoding
    // -------------------------------------------------------
    localparam FC_IDLE       = 5'd0;
    localparam FC_START      = 5'd1;
    localparam FC_BCAST_ADDR = 5'd2;
    localparam FC_BCAST_TBIT = 5'd3;
    localparam FC_CCC_BYTE   = 5'd4;
    localparam FC_CCC_TBIT   = 5'd5;
    localparam FC_RSTART     = 5'd6;
    localparam FC_TARG_ADDR  = 5'd7;
    localparam FC_TARG_TBIT  = 5'd8;
    localparam FC_TX_BYTE    = 5'd9;
    localparam FC_TX_TBIT    = 5'd10;
    localparam FC_RX_BYTE    = 5'd11;
    localparam FC_RX_TBIT    = 5'd12;
    localparam FC_DAA_RX     = 5'd13;
    localparam FC_DAA_TX     = 5'd14;
    localparam FC_IBI_START  = 5'd15;
    localparam FC_IBI_ADDR   = 5'd16;
    localparam FC_IBI_TBIT   = 5'd17;
    localparam FC_IBI_DATA   = 5'd18;
    localparam FC_IBI_STOP   = 5'd19;
    localparam FC_STOP       = 5'd20;
    localparam FC_DONE       = 5'd21;
    localparam FC_ERROR      = 5'd22;

    // -------------------------------------------------------
    // Internal registers
    // -------------------------------------------------------
    reg [4:0]  state;
    reg [3:0]  bit_cnt;
    reg [7:0]  byte_cnt;
    reg [7:0]  shift_reg;
    reg [7:0]  rx_accum;
    reg [3:0]  cmd_type_r;
    reg [6:0]  tgt_addr_r;
    reg [7:0]  ccc_code_r;
    reg [7:0]  data_len_r;
    reg        i2c_mode_r;
    reg        last_byte;
    reg [6:0]  ibi_addr_r;
    reg [5:0]  daa_byte_cnt;
    reg        ibi_pend;
    reg        bc_issued;

    // Latch for read bit — bc_rd_valid pulses during SCL high phase,
    // before bc_cmd_ready returns. We capture it immediately.
    reg        rd_bit_lat;
    reg        rd_valid_lat;

    // -------------------------------------------------------
    // bc_rd_bit latch: capture when bc_rd_valid pulses
    // -------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_bit_lat   <= 1'b0;
            rd_valid_lat <= 1'b0;
        end else begin
            if (bc_rd_valid) begin
                rd_bit_lat   <= bc_rd_bit;
                rd_valid_lat <= 1'b1;
            end else if (bc_cmd_ready && !bc_cmd_valid) begin
                // Clear latch once we've consumed the result (cmd done)
                rd_valid_lat <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------
    // IBI pending capture
    // -------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ibi_pend <= 1'b0;
        else if (ibi_det && ibi_en && (state == FC_IDLE))
            ibi_pend <= 1'b1;
        else if (state == FC_IBI_START)
            ibi_pend <= 1'b0;
    end

    // -------------------------------------------------------
    // Issue helper task
    // -------------------------------------------------------
    task issue_bc;
        input [2:0] op;
        input       bit_val;
        begin
            bc_cmd       <= op;
            bc_cmd_bit   <= bit_val;
            bc_cmd_valid <= 1'b1;
        end
    endtask

    // -------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= FC_IDLE;
            bit_cnt       <= 4'd7;
            byte_cnt      <= 8'd0;
            shift_reg     <= 8'd0;
            rx_accum      <= 8'd0;
            cmd_type_r    <= 4'd0;
            tgt_addr_r    <= 7'd0;
            ccc_code_r    <= 8'd0;
            data_len_r    <= 8'd0;
            i2c_mode_r    <= 1'b0;
            last_byte     <= 1'b0;
            ibi_addr_r    <= 7'd0;
            daa_byte_cnt  <= 6'd0;
            bc_cmd        <= `BC_IDLE;
            bc_cmd_bit    <= 1'b0;
            bc_cmd_valid  <= 1'b0;
            bc_issued     <= 1'b0;
            tx_rd_en      <= 1'b0;
            rx_wr_en      <= 1'b0;
            rx_wr_data    <= 8'd0;
            busy          <= 1'b0;
            done          <= 1'b0;
            nack_err      <= 1'b0;
            arb_lost      <= 1'b0;
            ibi_active    <= 1'b0;
            daa_done      <= 1'b0;
            ibi_src_addr  <= 7'd0;
            ibi_data_byte <= 8'd0;
            ibi_data_vld  <= 1'b0;
        end else begin
            // Default one-shot deasserts
            bc_cmd_valid <= 1'b0;
            tx_rd_en     <= 1'b0;
            rx_wr_en     <= 1'b0;
            done         <= 1'b0;
            daa_done     <= 1'b0;
            ibi_data_vld <= 1'b0;

            case (state)

                // =================================================
                FC_IDLE: begin
                    busy       <= 1'b0;
                    nack_err   <= 1'b0;
                    arb_lost   <= 1'b0;
                    ibi_active <= 1'b0;
                    bc_issued  <= 1'b0;
                    if (abort) begin
                        state <= FC_IDLE;
                    end else if (ibi_pend) begin
                        busy       <= 1'b1;
                        ibi_active <= 1'b1;
                        state      <= FC_IBI_START;
                    end else if (start) begin
                        busy       <= 1'b1;
                        cmd_type_r <= cmd_type;
                        tgt_addr_r <= tgt_addr;
                        ccc_code_r <= ccc_code;
                        data_len_r <= data_len;
                        i2c_mode_r <= i2c_mode;
                        byte_cnt   <= data_len;
                        bit_cnt    <= 4'd7;
                        state      <= FC_START;
                    end
                end

                // =================================================
                FC_START: begin
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_START, 1'b0);
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        bc_issued <= 1'b0;
                        bit_cnt   <= 4'd7;
                        case (cmd_type_r)
                            `CMD_PRIV_WR,
                            `CMD_PRIV_RD: begin
                                shift_reg <= {tgt_addr_r,
                                              (cmd_type_r == `CMD_PRIV_RD) ? 1'b1 : 1'b0};
                                state     <= FC_TARG_ADDR;
                            end
                            `CMD_I2C_WR,
                            `CMD_I2C_RD: begin
                                shift_reg <= {tgt_addr_r,
                                              (cmd_type_r == `CMD_I2C_RD) ? 1'b1 : 1'b0};
                                state     <= FC_TARG_ADDR;
                            end
                            `CMD_BC_CCC,
                            `CMD_DC_CCC_WR,
                            `CMD_DC_CCC_RD,
                            `CMD_ENTDAA: begin
                                shift_reg <= {`I3C_BCAST_ADDR, 1'b0};
                                state     <= FC_BCAST_ADDR;
                            end
                            default: state <= FC_ERROR;
                        endcase
                    end
                end

                // =================================================
                // Broadcast address 0x7E+W (8 bits total)
                // =================================================
                FC_BCAST_ADDR: begin
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_WRITE, shift_reg[7]);
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        bc_issued <= 1'b0;
                        if (bit_cnt == 4'd0) begin
                            state <= FC_BCAST_TBIT;
                        end else begin
                            bit_cnt <= bit_cnt - 4'd1;
                        end
                    end
                end

                FC_BCAST_TBIT: begin
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_READ, 1'b0);
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        bc_issued <= 1'b0;
                        bit_cnt   <= 4'd7;
                        shift_reg <= ccc_code_r;
                        state     <= FC_CCC_BYTE;
                    end
                end

                // =================================================
                // CCC byte
                // =================================================
                FC_CCC_BYTE: begin
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_WRITE, shift_reg[7]);
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        bc_issued <= 1'b0;
                        if (bit_cnt == 4'd0) begin
                            state <= FC_CCC_TBIT;
                        end else begin
                            bit_cnt <= bit_cnt - 4'd1;
                        end
                    end
                end

                FC_CCC_TBIT: begin
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_READ, 1'b0);
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        bc_issued <= 1'b0;
                        bit_cnt   <= 4'd7;
                        case (cmd_type_r)
                            `CMD_BC_CCC: begin
                                if (data_len_r == 8'd0) begin
                                    state <= FC_STOP;
                                end else begin
                                    byte_cnt  <= data_len_r - 8'd1;
                                    last_byte <= (data_len_r == 8'd1);
                                    shift_reg <= tx_rd_data;
                                    tx_rd_en  <= 1'b1;
                                    state     <= FC_TX_BYTE;
                                end
                            end
                            `CMD_DC_CCC_WR,
                            `CMD_DC_CCC_RD,
                            `CMD_ENTDAA: begin
                                state <= FC_RSTART;
                            end
                            default: state <= FC_ERROR;
                        endcase
                    end
                end

                // =================================================
                // Repeated START
                // =================================================
                FC_RSTART: begin
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_RSTART, 1'b0);
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        bc_issued <= 1'b0;
                        bit_cnt   <= 4'd7;
                        case (cmd_type_r)
                            `CMD_DC_CCC_WR: begin
                                shift_reg <= {tgt_addr_r, 1'b0};
                                state     <= FC_TARG_ADDR;
                            end
                            `CMD_DC_CCC_RD: begin
                                shift_reg <= {tgt_addr_r, 1'b1};
                                state     <= FC_TARG_ADDR;
                            end
                            `CMD_ENTDAA: begin
                                shift_reg    <= {`I3C_BCAST_ADDR, 1'b1}; // 0x7E+R
                                daa_byte_cnt <= 6'd0;
                                state        <= FC_TARG_ADDR;
                            end
                            default: state <= FC_ERROR;
                        endcase
                    end
                end

                // =================================================
                // Target address (8 bits: addr[6:0] + R/W)
                // =================================================
                FC_TARG_ADDR: begin
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_WRITE, shift_reg[7]);
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        bc_issued <= 1'b0;
                        if (bit_cnt == 4'd0) begin
                            state <= FC_TARG_TBIT;
                        end else begin
                            bit_cnt <= bit_cnt - 4'd1;
                        end
                    end
                end

                // T-bit/ACK after address — read result and decide next state
                FC_TARG_TBIT: begin
                    if (!bc_issued && bc_cmd_ready) begin
                        // Always read the T-bit (I2C: slave drives ACK; I3C: slave T-bit)
                        issue_bc(`BC_READ, 1'b0);
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        // At this point rd_valid_lat should be set
                        bc_issued <= 1'b0;
                        if (rd_bit_lat && !i2c_mode_r) begin
                            // I3C T-bit=1 after address: no slave ACK'd (treat as NACK)
                            nack_err <= 1'b1;
                            state    <= FC_ERROR;
                        end else if (rd_bit_lat && i2c_mode_r) begin
                            // I2C: NACK
                            nack_err <= 1'b1;
                            state    <= FC_ERROR;
                        end else begin
                            bit_cnt <= 4'd7;
                            case (cmd_type_r)
                                `CMD_PRIV_WR, `CMD_DC_CCC_WR, `CMD_I2C_WR,
                                `CMD_BC_CCC: begin
                                    if (data_len_r == 8'd0) begin
                                        state <= FC_STOP;
                                    end else begin
                                        byte_cnt  <= data_len_r - 8'd1;
                                        last_byte <= (data_len_r == 8'd1);
                                        shift_reg <= tx_rd_data;
                                        tx_rd_en  <= 1'b1;
                                        state     <= FC_TX_BYTE;
                                    end
                                end
                                `CMD_PRIV_RD, `CMD_DC_CCC_RD, `CMD_I2C_RD: begin
                                    if (data_len_r == 8'd0) begin
                                        state <= FC_STOP;
                                    end else begin
                                        byte_cnt  <= data_len_r - 8'd1;
                                        last_byte <= (data_len_r == 8'd1);
                                        rx_accum  <= 8'd0;
                                        state     <= FC_RX_BYTE;
                                    end
                                end
                                `CMD_ENTDAA: begin
                                    daa_byte_cnt <= 6'd0;
                                    rx_accum     <= 8'd0;
                                    state        <= FC_DAA_RX;
                                end
                                default: state <= FC_ERROR;
                            endcase
                        end
                    end
                end

                // =================================================
                // TX byte: shift out MSB first
                // =================================================
                FC_TX_BYTE: begin
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_WRITE, shift_reg[7]);
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        bc_issued <= 1'b0;
                        if (bit_cnt == 4'd0) begin
                            bit_cnt <= 4'd7;
                            state   <= FC_TX_TBIT;
                        end else begin
                            bit_cnt <= bit_cnt - 4'd1;
                        end
                    end
                end

                FC_TX_TBIT: begin
                    if (!bc_issued && bc_cmd_ready) begin
                        // I2C: read ACK from slave; I3C: read T-bit from target
                        issue_bc(`BC_READ, 1'b0);
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        bc_issued <= 1'b0;
                        if (rd_bit_lat && i2c_mode_r) begin
                            // I2C NACK after data byte
                            nack_err <= 1'b1;
                            state    <= FC_ERROR;
                        end else if (byte_cnt == 8'd0) begin
                            state <= FC_STOP;
                        end else begin
                            byte_cnt  <= byte_cnt - 8'd1;
                            last_byte <= (byte_cnt == 8'd1);
                            shift_reg <= tx_rd_data;
                            tx_rd_en  <= 1'b1;
                            bit_cnt   <= 4'd7;
                            state     <= FC_TX_BYTE;
                        end
                    end
                end

                // =================================================
                // RX byte: sample MSB first into rx_accum
                // =================================================
                FC_RX_BYTE: begin
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_READ, 1'b0);
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_rd_valid) begin
                        // Capture immediately when rd_valid pulses
                        rx_accum  <= {rx_accum[6:0], bc_rd_bit};
                        bc_issued <= 1'b0;
                        if (bit_cnt == 4'd0) begin
                            bit_cnt <= 4'd7;
                            state   <= FC_RX_TBIT;
                        end else begin
                            bit_cnt <= bit_cnt - 4'd1;
                        end
                    end
                end

                FC_RX_TBIT: begin
                    // Commit accumulated byte to RX FIFO
                    if (!rx_full) begin
                        rx_wr_en   <= 1'b1;
                        rx_wr_data <= rx_accum;
                    end
                    if (!bc_issued && bc_cmd_ready) begin
                        rx_wr_en <= 1'b0;
                        if (i2c_mode_r) begin
                            // I2C master drives ACK(0) or NACK(1) on last byte
                            issue_bc(`BC_WRITE, last_byte ? 1'b1 : 1'b0);
                        end else begin
                            // I3C: read T-bit driven by target
                            issue_bc(`BC_READ, 1'b0);
                        end
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        bc_issued <= 1'b0;
                        rx_accum  <= 8'd0;
                        if (byte_cnt == 8'd0) begin
                            state <= FC_STOP;
                        end else begin
                            byte_cnt  <= byte_cnt - 8'd1;
                            last_byte <= (byte_cnt == 8'd1);
                            bit_cnt   <= 4'd7;
                            state     <= FC_RX_BYTE;
                        end
                    end
                end

                // =================================================
                // DAA: read 9 bytes (PID[47:0]+BCR+DCR), write DA
                // =================================================
                FC_DAA_RX: begin
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_READ, 1'b0);
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_rd_valid) begin
                        rx_accum  <= {rx_accum[6:0], bc_rd_bit};
                        bc_issued <= 1'b0;
                        if (bit_cnt == 4'd0) begin
                            bit_cnt <= 4'd7;
                            // Store received byte to RX FIFO for SW readout
                            if (!rx_full) begin
                                rx_wr_en   <= 1'b1;
                                rx_wr_data <= {rx_accum[6:0], bc_rd_bit};
                            end
                            rx_accum     <= 8'd0;
                            daa_byte_cnt <= daa_byte_cnt + 6'd1;
                            if (daa_byte_cnt == 6'd7) begin
                                // Pre-load DA byte: addr[6:0] + odd parity
                                shift_reg <= {cfg_daa_addr, ~(^cfg_daa_addr)};
                                bit_cnt   <= 4'd7;
                                state     <= FC_DAA_TX;
                            end
                            // else stay in FC_DAA_RX, next byte
                        end else begin
                            bit_cnt <= bit_cnt - 4'd1;
                        end
                    end
                end

                FC_DAA_TX: begin
                    // shift_reg holds DA[6:0] + odd_parity, pre-loaded in FC_DAA_RX transition.
                    if (!bc_issued && bc_cmd_ready) begin
                        // Send current MSB
                        issue_bc(`BC_WRITE, shift_reg[7]);
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        bc_issued <= 1'b0;
                        if (bit_cnt == 4'd0) begin
                            bit_cnt  <= 4'd7;
                            daa_done <= 1'b1;
                            state    <= FC_STOP;
                        end else begin
                            bit_cnt <= bit_cnt - 4'd1;
                        end
                    end
                end

                // =================================================
                // IBI handling
                // =================================================
                FC_IBI_START: begin
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_START, 1'b0);
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        bc_issued <= 1'b0;
                        bit_cnt   <= 4'd7;
                        rx_accum  <= 8'd0;
                        state     <= FC_IBI_ADDR;
                    end
                end

                FC_IBI_ADDR: begin
                    // Read 8 bits: addr[6:0] + parity/direction
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_READ, 1'b0);
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_rd_valid) begin
                        rx_accum  <= {rx_accum[6:0], bc_rd_bit};
                        bc_issued <= 1'b0;
                        if (bit_cnt == 4'd0) begin
                            // rx_accum[7:1] = IBI address (bit 0 = parity/direction)
                            ibi_addr_r <= {rx_accum[6:0]};
                            bit_cnt    <= 4'd7;
                            state      <= FC_IBI_TBIT;
                        end else begin
                            bit_cnt <= bit_cnt - 4'd1;
                        end
                    end
                end

                FC_IBI_TBIT: begin
                    // Controller sends ACK or NACK
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_WRITE, ibi_auto_ack ? 1'b0 : 1'b1);
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        bc_issued    <= 1'b0;
                        ibi_src_addr <= ibi_addr_r;
                        if (!ibi_auto_ack) begin
                            state <= FC_IBI_STOP;
                        end else if (ibi_data_en) begin
                            bit_cnt  <= 4'd7;
                            rx_accum <= 8'd0;
                            state    <= FC_IBI_DATA;
                        end else begin
                            state <= FC_IBI_STOP;
                        end
                    end
                end

                FC_IBI_DATA: begin
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_READ, 1'b0);
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_rd_valid) begin
                        rx_accum  <= {rx_accum[6:0], bc_rd_bit};
                        bc_issued <= 1'b0;
                        if (bit_cnt == 4'd0) begin
                            ibi_data_byte <= {rx_accum[6:0], bc_rd_bit};
                            ibi_data_vld  <= 1'b1;
                            state         <= FC_IBI_STOP;
                        end else begin
                            bit_cnt <= bit_cnt - 4'd1;
                        end
                    end
                end

                FC_IBI_STOP: begin
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_STOP, 1'b0);
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        bc_issued  <= 1'b0;
                        ibi_active <= 1'b0;
                        state      <= FC_DONE;
                    end
                end

                // =================================================
                FC_STOP: begin
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_STOP, 1'b0);
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        bc_issued <= 1'b0;
                        state     <= FC_DONE;
                    end
                end

                // =================================================
                FC_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= FC_IDLE;
                end

                // =================================================
                FC_ERROR: begin
                    // Attempt clean STOP before returning to IDLE
                    if (!bc_issued && bc_cmd_ready) begin
                        issue_bc(`BC_STOP, 1'b0);
                        bc_issued <= 1'b1;
                    end else if (bc_issued && bc_cmd_ready && !bc_cmd_valid) begin
                        bc_issued <= 1'b0;
                        done      <= 1'b1;
                        busy      <= 1'b0;
                        state     <= FC_IDLE;
                    end
                end

                default: state <= FC_IDLE;

            endcase

            // -------------------------------------------------------
            // Abort override
            // -------------------------------------------------------
            if (abort && busy && state != FC_IDLE && state != FC_STOP &&
                state != FC_DONE && state != FC_ERROR) begin
                state     <= FC_ERROR;
                bc_issued <= 1'b0;
            end

            // (shift_reg is loaded at each FC_TX_BYTE entry point using
            //  the FWFT FIFO's combinational rd_data — no delayed latch needed)

        end
    end

endmodule
