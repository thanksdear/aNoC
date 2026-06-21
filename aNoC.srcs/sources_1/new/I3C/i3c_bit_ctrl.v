`include "i3c_defines.vh"

module i3c_bit_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // Timing configuration
    input  wire [15:0] cfg_hi_cnt,
    input  wire [15:0] cfg_lo_cnt,
    input  wire [15:0] cfg_hd_cnt,
    input  wire [15:0] cfg_idle_cnt,

    // Command interface (handshake)
    input  wire [2:0]  cmd,
    input  wire        cmd_bit,     // bit to write (for BC_WRITE)
    input  wire        cmd_valid,
    output reg         cmd_ready,

    // Read result
    output reg         rd_bit,
    output reg         rd_valid,

    // Bus signals
    output reg         scl_out,
    output reg         sda_oe,
    output reg         sda_out,
    input  wire        sda_in,

    // IBI detection
    output reg         ibi_det
);

    // -------------------------------------------------------
    // FSM state encoding
    // -------------------------------------------------------
    localparam ST_IDLE      = 4'd0;
    localparam ST_START_SDA = 4'd1;
    localparam ST_START_SCL = 4'd2;
    localparam ST_RS_SDA_H  = 4'd3;
    localparam ST_RS_SCL_H  = 4'd4;
    localparam ST_RS_SDA_L  = 4'd5;
    localparam ST_RS_SCL_L  = 4'd6;
    localparam ST_WR_HD     = 4'd7;
    localparam ST_WR_HI     = 4'd8;
    localparam ST_WR_LO     = 4'd9;
    localparam ST_RD_HD     = 4'd10;
    localparam ST_RD_HI     = 4'd11;
    localparam ST_RD_LO     = 4'd12;
    localparam ST_STOP_SDA  = 4'd13;
    localparam ST_STOP_HI   = 4'd14;
    localparam ST_STOP_DONE = 4'd15;

    reg [3:0]  state;
    reg [15:0] timer;
    reg        cmd_bit_r;

    // -------------------------------------------------------
    // IBI detection: sda_in goes L while SCL=H and IDLE
    // -------------------------------------------------------
    reg sda_in_prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_in_prev <= 1'b1;
            ibi_det     <= 1'b0;
        end else begin
            sda_in_prev <= sda_in;
            ibi_det     <= (state == ST_IDLE) && scl_out && (!sda_in) && sda_in_prev;
        end
    end

    // -------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            timer      <= 16'd0;
            cmd_ready  <= 1'b1;
            rd_bit     <= 1'b0;
            rd_valid   <= 1'b0;
            scl_out    <= 1'b1;
            sda_oe     <= 1'b1;
            sda_out    <= 1'b1;
            cmd_bit_r  <= 1'b0;
        end else begin
            rd_valid <= 1'b0; // default: pulse only one cycle

            case (state)
                // -------------------------------------------------
                ST_IDLE: begin
                    scl_out   <= 1'b1;
                    sda_oe    <= 1'b1;
                    sda_out   <= 1'b1;
                    cmd_ready <= 1'b1;
                    if (cmd_valid) begin
                        cmd_ready <= 1'b0;
                        cmd_bit_r <= cmd_bit;
                        case (cmd)
                            `BC_START: begin
                                // SCL=H, SDA=H -> SDA goes L
                                sda_out <= 1'b0;
                                timer   <= cfg_idle_cnt;
                                state   <= ST_START_SDA;
                            end
                            `BC_RSTART: begin
                                // Release SDA first (SDA->H)
                                sda_out <= 1'b1;
                                timer   <= cfg_hd_cnt;
                                state   <= ST_RS_SDA_H;
                            end
                            `BC_WRITE: begin
                                sda_out <= cmd_bit;
                                sda_oe  <= 1'b1;
                                timer   <= cfg_hd_cnt;
                                state   <= ST_WR_HD;
                            end
                            `BC_READ: begin
                                sda_oe <= 1'b0; // release SDA
                                timer  <= cfg_hd_cnt;
                                state  <= ST_RD_HD;
                            end
                            `BC_STOP: begin
                                // SDA->L, SCL stays L (already L after last bit)
                                sda_oe  <= 1'b1;
                                sda_out <= 1'b0;
                                scl_out <= 1'b0;
                                timer   <= cfg_hd_cnt;
                                state   <= ST_STOP_SDA;
                            end
                            default: begin
                                cmd_ready <= 1'b1;
                                state     <= ST_IDLE;
                            end
                        endcase
                    end
                end

                // -------------------------------------------------
                // START: SDA goes L, wait idle_cnt, then SCL goes L
                // -------------------------------------------------
                ST_START_SDA: begin
                    if (timer == 16'd0) begin
                        scl_out <= 1'b0;
                        state   <= ST_START_SCL;
                        timer   <= cfg_lo_cnt;
                    end else begin
                        timer <= timer - 16'd1;
                    end
                end

                ST_START_SCL: begin
                    if (timer == 16'd0) begin
                        cmd_ready <= 1'b1;
                        state     <= ST_IDLE;
                    end else begin
                        timer <= timer - 16'd1;
                    end
                end

                // -------------------------------------------------
                // REPEATED START
                // -------------------------------------------------
                // Step 1: SDA->H while SCL=L
                ST_RS_SDA_H: begin
                    if (timer == 16'd0) begin
                        scl_out <= 1'b1; // SCL->H
                        timer   <= cfg_hi_cnt;
                        state   <= ST_RS_SCL_H;
                    end else begin
                        timer <= timer - 16'd1;
                    end
                end

                // Step 2: SCL=H, setup time
                ST_RS_SCL_H: begin
                    if (timer == 16'd0) begin
                        sda_out <= 1'b0; // SDA->L (START condition)
                        timer   <= cfg_hd_cnt;
                        state   <= ST_RS_SDA_L;
                    end else begin
                        timer <= timer - 16'd1;
                    end
                end

                // Step 3: SDA=L, hold, then SCL->L
                ST_RS_SDA_L: begin
                    if (timer == 16'd0) begin
                        scl_out <= 1'b0;
                        timer   <= cfg_lo_cnt;
                        state   <= ST_RS_SCL_L;
                    end else begin
                        timer <= timer - 16'd1;
                    end
                end

                // Step 4: SCL=L, low period done
                ST_RS_SCL_L: begin
                    if (timer == 16'd0) begin
                        cmd_ready <= 1'b1;
                        state     <= ST_IDLE;
                    end else begin
                        timer <= timer - 16'd1;
                    end
                end

                // -------------------------------------------------
                // WRITE BIT
                // -------------------------------------------------
                // Phase 1: hold SDA for hd_cnt cycles (SCL=L)
                ST_WR_HD: begin
                    if (timer == 16'd0) begin
                        scl_out <= 1'b1;
                        timer   <= cfg_hi_cnt;
                        state   <= ST_WR_HI;
                    end else begin
                        timer <= timer - 16'd1;
                    end
                end

                // Phase 2: SCL=H for hi_cnt cycles
                ST_WR_HI: begin
                    if (timer == 16'd0) begin
                        scl_out <= 1'b0;
                        // Remaining low = lo_cnt - hd_cnt (already spent hd_cnt pre-SCL-H)
                        timer   <= (cfg_lo_cnt > cfg_hd_cnt)
                                   ? (cfg_lo_cnt - cfg_hd_cnt - 16'd1)
                                   : 16'd0;
                        state   <= ST_WR_LO;
                    end else begin
                        timer <= timer - 16'd1;
                    end
                end

                // Phase 3: SCL=L for remaining lo_cnt - hd_cnt cycles
                ST_WR_LO: begin
                    if (timer == 16'd0) begin
                        cmd_ready <= 1'b1;
                        state     <= ST_IDLE;
                    end else begin
                        timer <= timer - 16'd1;
                    end
                end

                // -------------------------------------------------
                // READ BIT
                // -------------------------------------------------
                // Phase 1: release SDA, wait hd_cnt (SCL=L)
                ST_RD_HD: begin
                    if (timer == 16'd0) begin
                        scl_out <= 1'b1;
                        timer   <= cfg_hi_cnt;
                        state   <= ST_RD_HI;
                    end else begin
                        timer <= timer - 16'd1;
                    end
                end

                // Phase 2: SCL=H for hi_cnt; sample SDA on last cycle
                ST_RD_HI: begin
                    if (timer == 16'd1) begin
                        // Sample near end of high period
                        rd_bit   <= sda_in;
                        rd_valid <= 1'b1;
                    end
                    if (timer == 16'd0) begin
                        scl_out <= 1'b0;
                        timer   <= (cfg_lo_cnt > cfg_hd_cnt)
                                   ? (cfg_lo_cnt - cfg_hd_cnt - 16'd1)
                                   : 16'd0;
                        state   <= ST_RD_LO;
                    end else begin
                        timer <= timer - 16'd1;
                    end
                end

                // Phase 3: SCL=L for remaining time
                ST_RD_LO: begin
                    if (timer == 16'd0) begin
                        cmd_ready <= 1'b1;
                        state     <= ST_IDLE;
                    end else begin
                        timer <= timer - 16'd1;
                    end
                end

                // -------------------------------------------------
                // STOP
                // -------------------------------------------------
                // Phase 1: SDA=L, SCL=L, wait hd_cnt
                ST_STOP_SDA: begin
                    if (timer == 16'd0) begin
                        scl_out <= 1'b1;
                        timer   <= cfg_hi_cnt;
                        state   <= ST_STOP_HI;
                    end else begin
                        timer <= timer - 16'd1;
                    end
                end

                // Phase 2: SCL=H for hi_cnt, then SDA->H
                ST_STOP_HI: begin
                    if (timer == 16'd0) begin
                        sda_out <= 1'b1; // STOP condition: SDA rises while SCL=H
                        state   <= ST_STOP_DONE;
                        timer   <= cfg_idle_cnt;
                    end else begin
                        timer <= timer - 16'd1;
                    end
                end

                // Phase 3: hold idle
                ST_STOP_DONE: begin
                    if (timer == 16'd0) begin
                        cmd_ready <= 1'b1;
                        state     <= ST_IDLE;
                    end else begin
                        timer <= timer - 16'd1;
                    end
                end

                default: begin
                    state     <= ST_IDLE;
                    cmd_ready <= 1'b1;
                end
            endcase
        end
    end

endmodule
