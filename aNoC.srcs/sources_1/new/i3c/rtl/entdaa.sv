`default_nettype none

// ENTDAA dynamic-address assignment engine.
//
// ccc_handler starts this block after it has already emitted:
//
//   S 7'h7e/W ACK 8'h07 T
//
// Each ENTDAA arbitration round emitted here is:
//
//   Sr 7'h7e/R ACK  PID[47:0] BCR[7:0] DCR[7:0]
//                    {dynamic_address[6:0], odd_parity} ACK
//
// A NACK on the repeated 7'h7e/R header means that no unaddressed target
// remains and completes ENTDAA normally.  Once a target has ACKed that
// header, a dynamic address must be available and the target must ACK the
// assigned address; either failure is an error.  DAT is consumed only after
// the assigned address is ACKed successfully.
//
// The arbitration stream bypasses byte_serializer and directly issues LC_SR
// and LC_DATA commands.  All ENTDAA signalling remains open drain.

module entdaa (
    input  logic        clk,
    input  logic        rst_n,

    // Start and completion
    input  logic        start,
    output logic        done,
    output logic        error,

    // Dynamic-address table
    input  logic [6:0]  dat_addr,
    input  logic        dat_valid,
    output logic        dat_rd,

    // Successfully discovered target
    output logic [63:0] dev_pid,
    output logic [6:0]  dev_da,
    output logic        dev_valid,

    // Line Controller bypass interface
    output logic [1:0]  lc_cmd,
    output logic        lc_sda_tx,
    output logic        lc_cmd_valid,
    input  logic        lc_cmd_ready,
    input  logic        lc_sda_rx,
    input  logic        lc_sda_rx_valid,
    output logic        lc_open_drain
);

localparam logic [1:0] LC_DATA = 2'b00;
localparam logic [1:0] LC_SR   = 2'b11;
localparam logic [7:0] ENTDAA_READ_HEADER = {7'h7e, 1'b1};

typedef enum logic [3:0] {
    S_IDLE       = 4'd0,
    S_SR         = 4'd1,
    S_HEADER     = 4'd2,
    S_HEADER_ACK = 4'd3,
    S_RCV_ID     = 4'd4,
    S_SEND_DA    = 4'd5,
    S_DA_ACK     = 4'd6,
    S_DONE       = 4'd7,
    S_ERROR      = 4'd8
} entdaa_state_t;

entdaa_state_t state, next_state;

logic [5:0]  bit_idx;
logic        lc_issued;
logic [63:0] id_shift;
logic [6:0]  da_r;
logic [7:0]  da_byte;
logic        data_state;

assign da_byte = {da_r, ~^da_r};

// LC_SR completes when line_controller returns to idle and reasserts ready.
// LC_DATA completes with the sampled-bit pulse from line_controller.
always_comb begin
    next_state = state;

    unique case (state)
        S_IDLE:
            if (start)
                next_state = S_SR;

        S_SR:
            if (lc_issued && lc_cmd_ready)
                next_state = S_HEADER;

        S_HEADER:
            if (lc_issued && lc_sda_rx_valid && bit_idx == 6'd0)
                next_state = S_HEADER_ACK;

        S_HEADER_ACK:
            if (lc_issued && lc_sda_rx_valid) begin
                if (lc_sda_rx)       next_state = S_DONE;
                else if (!dat_valid) next_state = S_ERROR;
                else                 next_state = S_RCV_ID;
            end

        S_RCV_ID:
            if (lc_issued && lc_sda_rx_valid && bit_idx == 6'd0)
                next_state = S_SEND_DA;

        S_SEND_DA:
            if (lc_issued && lc_sda_rx_valid && bit_idx == 6'd0)
                next_state = S_DA_ACK;

        S_DA_ACK:
            if (lc_issued && lc_sda_rx_valid) begin
                if (lc_sda_rx) next_state = S_ERROR;
                else           next_state = S_SR;
            end

        S_DONE,
        S_ERROR:
            next_state = S_IDLE;

        default:
            next_state = S_IDLE;
    endcase
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state      <= S_IDLE;
        bit_idx    <= 6'd7;
        lc_issued  <= 1'b0;
        id_shift   <= '0;
        da_r       <= '0;
        dev_pid    <= '0;
        dev_da     <= '0;
        dev_valid  <= 1'b0;
        dat_rd     <= 1'b0;
        done       <= 1'b0;
        error      <= 1'b0;
    end else begin
        state     <= next_state;
        dev_valid <= 1'b0;
        dat_rd    <= 1'b0;
        done      <= 1'b0;
        error     <= 1'b0;

        // A command is accepted only on a valid/ready handshake.  DATA and
        // passthrough commands have different completion indications below.
        if (lc_cmd_valid && lc_cmd_ready)
            lc_issued <= 1'b1;

        if (lc_issued &&
                (((state == S_SR) && lc_cmd_ready) ||
                 (data_state && lc_sda_rx_valid)))
            lc_issued <= 1'b0;

        // Every round begins with Sr followed by the 7'h7e/R header.
        if (state == S_SR && lc_issued && lc_cmd_ready)
            bit_idx <= 6'd7;

        if (state == S_HEADER && lc_issued && lc_sda_rx_valid) begin
            if (bit_idx != 6'd0)
                bit_idx <= bit_idx - 6'd1;
        end

        // A header ACK selects a target.  Reserve (but do not yet consume)
        // the current DAT entry and begin the 64-bit arbitration stream.
        if (state == S_HEADER_ACK && lc_issued && lc_sda_rx_valid &&
                !lc_sda_rx && dat_valid) begin
            da_r     <= dat_addr;
            id_shift <= '0;
            bit_idx  <= 6'd63;
        end

        if (state == S_RCV_ID && lc_issued && lc_sda_rx_valid) begin
            id_shift <= {id_shift[62:0], lc_sda_rx};
            if (bit_idx != 6'd0)
                bit_idx <= bit_idx - 6'd1;
            else
                bit_idx <= 6'd7;
        end

        if (state == S_SEND_DA && lc_issued && lc_sda_rx_valid) begin
            if (bit_idx != 6'd0)
                bit_idx <= bit_idx - 6'd1;
        end

        // Only a target ACK makes the discovery visible and consumes DAT.
        // A DA NACK is handled by S_ERROR and leaves DAT untouched.
        if (state == S_DA_ACK && lc_issued && lc_sda_rx_valid &&
                !lc_sda_rx) begin
            dev_pid   <= id_shift;
            dev_da    <= da_r;
            dev_valid <= 1'b1;
            dat_rd    <= 1'b1;
        end

        if (state == S_DONE)
            done <= 1'b1;

        if (state == S_ERROR)
            error <= 1'b1;
    end
end

always_comb begin
    unique case (state)
        S_HEADER,
        S_HEADER_ACK,
        S_RCV_ID,
        S_SEND_DA,
        S_DA_ACK: data_state = 1'b1;
        default:  data_state = 1'b0;
    endcase
end

assign lc_cmd = (state == S_SR) ? LC_SR : LC_DATA;

always_comb begin
    unique case (state)
        S_HEADER:  lc_sda_tx = ENTDAA_READ_HEADER[bit_idx[2:0]];
        S_SEND_DA: lc_sda_tx = da_byte[bit_idx[2:0]];
        default:   lc_sda_tx = 1'b1;
    endcase
end

assign lc_cmd_valid = (state == S_SR || data_state) && !lc_issued;
assign lc_open_drain = 1'b1;

endmodule
