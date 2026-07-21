class i3c_coverage extends uvm_subscriber #(i3c_txn);
  `uvm_component_utils(i3c_coverage)

  localparam bit [7:0] REG_BUS_TIMING_0   = 8'h00;
  localparam bit [7:0] REG_BUS_TIMING_1   = 8'h04;
  localparam bit [7:0] REG_CTRL           = 8'h08;
  localparam bit [7:0] REG_STATUS         = 8'h0c;
  localparam bit [7:0] REG_IBI_STATUS     = 8'h10;
  localparam bit [7:0] REG_ERR_STATUS     = 8'h14;
  localparam bit [7:0] REG_ENTDAA_STATUS  = 8'h18;
  localparam bit [7:0] REG_ENTDAA_PID_LO  = 8'h1c;
  localparam bit [7:0] REG_ENTDAA_PID_HI  = 8'h30;
  localparam bit [7:0] CMD_PORT           = 8'h20;
  localparam bit [7:0] RESP_PORT          = 8'h24;
  localparam bit [7:0] TX_PORT            = 8'h28;
  localparam bit [7:0] RX_PORT            = 8'h2c;

  localparam bit [7:0] CCC_ENEC           = 8'h00;
  localparam bit [7:0] CCC_ENTDAA         = 8'h07;
  localparam bit [7:0] CCC_GETSTATUS      = 8'h90;

  op_e       op_s;
  bit [7:0]  addr_s;
  bit [31:0] data_s;
  bit [3:0]  strb_s;
  bit        is_cmd_s;
  bit        is_ctrl_s;
  bit        is_resp_s;
  bit        is_ibi_status_s;
  bit        cmd_is_ccc_s;
  bit        cmd_is_direct_s;
  bit        cmd_rw_s;
  bit [7:0]  cmd_len_s;
  bit [7:0]  cmd_ccc_s;
  bit        ctrl_i3c_mode_s;
  bit        ctrl_core_en_s;
  bit        ctrl_ibi_en_s;
  bit        ctrl_ibi_mdb_en_s;

  covergroup cg_apb with function sample();
    cp_op: coverpoint op_s {
      bins wr = {WR};
      bins rd = {RD};
    }

    cp_addr: coverpoint addr_s {
      bins bus_timing_0  = {REG_BUS_TIMING_0};
      bins bus_timing_1  = {REG_BUS_TIMING_1};
      bins ctrl          = {REG_CTRL};
      bins status        = {REG_STATUS};
      bins ibi_status    = {REG_IBI_STATUS};
      bins err_status    = {REG_ERR_STATUS};
      bins entdaa_status = {REG_ENTDAA_STATUS};
      bins entdaa_pid_lo = {REG_ENTDAA_PID_LO};
      bins entdaa_pid_hi = {REG_ENTDAA_PID_HI};
      bins cmd_port      = {CMD_PORT};
      bins resp_port     = {RESP_PORT};
      bins tx_port       = {TX_PORT};
      bins rx_port       = {RX_PORT};
      bins others        = default;
    }

    cp_strb: coverpoint strb_s {
      bins none = {4'b0000};
      bins full = {4'b1111};
      bins byte_en[] = {[4'b0001:4'b1110]};
    }

    x_op_addr: cross cp_op, cp_addr {
      ignore_bins wr_ro_status =
        binsof(cp_op.wr) && binsof(cp_addr.status);
      ignore_bins wr_ro_entdaa =
        binsof(cp_op.wr) && (binsof(cp_addr.entdaa_status) ||
                             binsof(cp_addr.entdaa_pid_lo) ||
                             binsof(cp_addr.entdaa_pid_hi));
      ignore_bins wr_read_fifo =
        binsof(cp_op.wr) && (binsof(cp_addr.resp_port) ||
                             binsof(cp_addr.rx_port));
      ignore_bins rd_write_fifo =
        binsof(cp_op.rd) && (binsof(cp_addr.cmd_port) ||
                             binsof(cp_addr.tx_port));
    }
  endgroup

  covergroup cg_ctrl with function sample();
    option.per_instance = 1;

    cp_ctrl_sample: coverpoint is_ctrl_s {
      bins hit = {1};
    }

    cp_mode: coverpoint ctrl_i3c_mode_s iff (is_ctrl_s) {
      bins i2c = {0};
      bins i3c = {1};
    }

    cp_core_en: coverpoint ctrl_core_en_s iff (is_ctrl_s) {
      bins disabled = {0};
      bins enabled  = {1};
    }

    cp_ibi_en: coverpoint ctrl_ibi_en_s iff (is_ctrl_s) {
      bins off = {0};
      bins on  = {1};
    }

    cp_ibi_mdb_en: coverpoint ctrl_ibi_mdb_en_s iff (is_ctrl_s) {
      bins no_mdb = {0};
      bins mdb    = {1};
    }

    x_ibi_cfg: cross cp_ibi_en, cp_ibi_mdb_en;
  endgroup

  covergroup cg_cmd with function sample();
    option.per_instance = 1;

    cp_cmd_hit: coverpoint is_cmd_s {
      bins hit = {1};
    }

    cp_cmd_kind: coverpoint {cmd_is_ccc_s, cmd_is_direct_s} iff (is_cmd_s) {
      bins private_msg   = {2'b00};
      bins broadcast_ccc = {2'b10};
      bins direct_ccc    = {2'b11};
    }

    cp_rw: coverpoint cmd_rw_s iff (is_cmd_s) {
      bins write = {0};
      bins read  = {1};
    }

    cp_len: coverpoint cmd_len_s iff (is_cmd_s) {
      bins zero      = {0};
      bins one       = {1};
      bins two       = {2};
      bins three     = {3};
      bins four_plus = {[4:255]};
    }

    cp_ccc_code: coverpoint cmd_ccc_s iff (is_cmd_s && cmd_is_ccc_s) {
      bins enec      = {CCC_ENEC};
      bins entdaa    = {CCC_ENTDAA};
      bins getstatus = {CCC_GETSTATUS};
      bins others    = default;
    }

    x_kind_rw: cross cp_cmd_kind, cp_rw {
      ignore_bins broadcast_read =
        binsof(cp_cmd_kind.broadcast_ccc) && binsof(cp_rw.read);
    }

    x_kind_len: cross cp_cmd_kind, cp_len {
      ignore_bins broadcast_payload =
        binsof(cp_cmd_kind.broadcast_ccc) &&
        (binsof(cp_len.one) || binsof(cp_len.two) ||
         binsof(cp_len.three) || binsof(cp_len.four_plus));
      ignore_bins direct_len_zero =
        binsof(cp_cmd_kind.direct_ccc) && binsof(cp_len.zero);
      ignore_bins direct_len_three_plus =
        binsof(cp_cmd_kind.direct_ccc) &&
        (binsof(cp_len.three) || binsof(cp_len.four_plus));
    }
  endgroup

  covergroup cg_status with function sample();
    cp_resp_read: coverpoint is_resp_s {
      bins hit = {1};
    }

    cp_ibi_status_access: coverpoint is_ibi_status_s {
      bins hit = {1};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_apb = new();
    cg_ctrl = new();
    cg_cmd = new();
    cg_status = new();
  endfunction

  function void write(i3c_txn t);
    op_s = t.op;
    addr_s = t.addr;
    data_s = t.data;
    strb_s = t.strb;

    is_cmd_s = (t.op == WR) && (t.addr == CMD_PORT);
    is_ctrl_s = (t.op == WR) && (t.addr == REG_CTRL);
    is_resp_s = (t.op == RD) && (t.addr == RESP_PORT);
    is_ibi_status_s = (t.addr == REG_IBI_STATUS);

    cmd_len_s = t.data[31:24];
    cmd_rw_s = t.data[16];
    cmd_ccc_s = t.data[15:8];
    cmd_is_ccc_s = t.data[1];
    cmd_is_direct_s = t.data[0];

    ctrl_i3c_mode_s = t.data[0];
    ctrl_core_en_s = t.data[1];
    ctrl_ibi_en_s = t.data[3];
    ctrl_ibi_mdb_en_s = t.data[4];

    cg_apb.sample();
    if (is_ctrl_s)
      cg_ctrl.sample();
    if (is_cmd_s)
      cg_cmd.sample();
    if (is_resp_s || is_ibi_status_s)
      cg_status.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("COV", $sformatf("APB coverage: %0.1f%%", cg_apb.get_coverage()), UVM_LOW)
    `uvm_info("COV", $sformatf("CTRL coverage: %0.1f%%", cg_ctrl.get_coverage()), UVM_LOW)
    `uvm_info("COV", $sformatf("CMD coverage: %0.1f%%", cg_cmd.get_coverage()), UVM_LOW)
    `uvm_info("COV", $sformatf("STATUS coverage: %0.1f%%", cg_status.get_coverage()), UVM_LOW)
  endfunction
endclass

// Protocol coverage sampled from the passive bus monitor.  Keep this separate
// from i3c_coverage: the APB transaction describes controller intent, whereas
// i3c_bus_txn describes what was actually observed on SDA/SCL.
class i3c_bus_coverage extends uvm_subscriber #(i3c_bus_txn);
  `uvm_component_utils(i3c_bus_coverage)

  // X/Z 是协议检查失败，不是需要命中的合法功能覆盖目标。VCS 2018 会从
  // 标量 coverpoint 的显式 bin 中删除 X/Z 并产生 PBSI/CPBRM warning；
  // scoreboard 已通过四态 !== 比较报告这些错误，因此这里只覆盖合法的 0/1。

  typedef enum bit [1:0] {
    NINTH_COUNTS_EMPTY,
    NINTH_COUNTS_ALIGNED,
    NINTH_COUNTS_MISSING,
    NINTH_COUNTS_EXTRA
  } ninth_count_status_e;

  typedef enum bit [2:0] {
    ENTDAA_ROUND_INCOMPLETE,
    ENTDAA_ROUND_SUCCESS,
    ENTDAA_ROUND_FINAL_HEADER_NACK,
    ENTDAA_ROUND_DA_NACK,
    ENTDAA_ROUND_MALFORMED
  } entdaa_round_outcome_e;

  typedef enum bit [1:0] {
    ENTDAA_PARITY_NOT_PRESENT,
    ENTDAA_PARITY_GOOD,
    ENTDAA_PARITY_BAD,
    ENTDAA_PARITY_UNKNOWN
  } entdaa_parity_status_e;

  i3c_bus_kind_e       kind_s;
  i3c_bus_origin_e     origin_s;
  int unsigned         segment_count_s;
  int unsigned         entdaa_round_count_s;
  bit                  has_start_s;
  bit                  has_restart_s;
  bit                  has_stop_s;
  bit                  has_null_segment_s;
  bit                  has_incomplete_header_s;

  i3c_direction_e      direction_s;
  i3c_bus_boundary_e   start_boundary_s;
  i3c_bus_boundary_e   end_boundary_s;
  int unsigned         payload_len_s;
  bit                  header_complete_s;
  logic                addr_ninth_s;
  ninth_count_status_e ninth_count_status_s;

  logic                data_ninth_s;
  logic                data_ninth_controller_low_s;
  logic                data_ninth_target_low_s;

  int unsigned         ibi_mdb_count_s;
  logic                ibi_header_ninth_s;
  i3c_bus_boundary_e   ibi_end_boundary_s;
  logic                ibi_t_s;
  logic                ibi_controller_t_low_s;
  logic                ibi_target_t_low_s;

  entdaa_round_outcome_e entdaa_round_outcome_s;
  entdaa_parity_status_e entdaa_parity_status_s;
  i3c_bus_boundary_e     entdaa_start_boundary_s;
  i3c_bus_boundary_e     entdaa_end_boundary_s;
  logic [7:0]            entdaa_header_s;
  logic                  entdaa_header_ninth_s;

  covergroup cg_transfer with function sample();
    option.per_instance = 1;

    cp_kind: coverpoint kind_s {
      bins tr_kind_unknown   = {I3C_KIND_UNKNOWN};
      bins tr_kind_private   = {I3C_KIND_PRIVATE};
      bins tr_kind_broadcast = {I3C_KIND_BROADCAST_CCC};
      bins tr_kind_direct    = {I3C_KIND_DIRECT_CCC};
      bins tr_kind_entdaa    = {I3C_KIND_ENTDAA};
      bins tr_kind_ibi       = {I3C_KIND_IBI};
    }

    cp_origin: coverpoint origin_s {
      bins tr_origin_unknown    = {I3C_ORIGIN_UNKNOWN};
      bins tr_origin_controller = {I3C_ORIGIN_CONTROLLER};
      bins tr_origin_target     = {I3C_ORIGIN_TARGET};
    }

    cp_segment_count: coverpoint segment_count_s {
      bins tr_seg_count_empty = {0};
      bins tr_seg_count_one   = {1};
      bins tr_seg_count_two   = {2};
      bins tr_seg_count_many  = default;
    }

    cp_entdaa_round_count: coverpoint entdaa_round_count_s {
      bins tr_entdaa_round_none   = {0};
      bins tr_entdaa_round_one    = {1};
      bins tr_entdaa_round_two    = {2};
      bins tr_entdaa_round_many   = default;
    }

    cp_has_start: coverpoint has_start_s {
      bins tr_start_absent  = {0};
      bins tr_start_present = {1};
    }

    cp_has_restart: coverpoint has_restart_s {
      bins tr_restart_absent  = {0};
      bins tr_restart_present = {1};
    }

    cp_has_stop: coverpoint has_stop_s {
      bins tr_stop_absent  = {0};
      bins tr_stop_present = {1};
    }

    cp_null_segment: coverpoint has_null_segment_s {
      bins tr_null_segment_none = {0};
      bins tr_null_segment_seen = {1};
    }

    cp_incomplete_header: coverpoint has_incomplete_header_s {
      bins tr_incomplete_header_none = {0};
      bins tr_incomplete_header_seen = {1};
    }

    // Legal initiation combinations.  IBI is target initiated; all currently
    // supported controller commands are controller initiated.
    x_kind_origin: cross cp_kind, cp_origin {
      ignore_bins unknown =
        binsof(cp_kind.tr_kind_unknown) ||
        binsof(cp_origin.tr_origin_unknown);
      ignore_bins controller_ibi =
        binsof(cp_kind.tr_kind_ibi) &&
        binsof(cp_origin.tr_origin_controller);
      ignore_bins target_command =
        (binsof(cp_kind.tr_kind_private) ||
         binsof(cp_kind.tr_kind_broadcast) ||
         binsof(cp_kind.tr_kind_direct) ||
         binsof(cp_kind.tr_kind_entdaa)) &&
        binsof(cp_origin.tr_origin_target);
    }

    // Private, broadcast and target-initiated IBI transfers end without Sr.
    // Direct CCC and ENTDAA use repeated START in the implemented flows.
    x_kind_restart: cross cp_kind, cp_has_restart {
      ignore_bins unknown = binsof(cp_kind.tr_kind_unknown);
      ignore_bins private_with_restart =
        binsof(cp_kind.tr_kind_private) &&
        binsof(cp_has_restart.tr_restart_present);
      ignore_bins broadcast_with_restart =
        binsof(cp_kind.tr_kind_broadcast) &&
        binsof(cp_has_restart.tr_restart_present);
      ignore_bins direct_without_restart =
        binsof(cp_kind.tr_kind_direct) &&
        binsof(cp_has_restart.tr_restart_absent);
      ignore_bins entdaa_without_restart =
        binsof(cp_kind.tr_kind_entdaa) &&
        binsof(cp_has_restart.tr_restart_absent);
      ignore_bins ibi_with_restart =
        binsof(cp_kind.tr_kind_ibi) &&
        binsof(cp_has_restart.tr_restart_present);
    }
  endgroup

  covergroup cg_segment with function sample();
    option.per_instance = 1;

    cp_kind: coverpoint kind_s {
      bins seg_kind_unknown   = {I3C_KIND_UNKNOWN};
      bins seg_kind_private   = {I3C_KIND_PRIVATE};
      bins seg_kind_broadcast = {I3C_KIND_BROADCAST_CCC};
      bins seg_kind_direct    = {I3C_KIND_DIRECT_CCC};
      bins seg_kind_entdaa    = {I3C_KIND_ENTDAA};
      bins seg_kind_ibi       = {I3C_KIND_IBI};
    }

    cp_direction: coverpoint direction_s {
      bins seg_direction_write   = {I3C_WRITE};
      bins seg_direction_read    = {I3C_READ};
      bins seg_direction_unknown = {I3C_DIRECTION_UNKNOWN};
    }

    cp_payload_len: coverpoint payload_len_s {
      bins seg_payload_zero       = {0};
      bins seg_payload_one        = {1};
      bins seg_payload_two        = {2};
      bins seg_payload_three_four = {[3:4]};
      bins seg_payload_five_plus  = default;
    }

    cp_header_complete: coverpoint header_complete_s {
      bins seg_header_incomplete = {0};
      bins seg_header_complete   = {1};
    }

    // The sampled value is deliberately raw.  Low/high are ACK/NACK only for
    // address headers; this coverpoint does not infer data T-bit correctness.
    cp_addr_ninth: coverpoint addr_ninth_s iff (header_complete_s) {
      bins seg_addr_ninth_ack  = {1'b0};
      bins seg_addr_ninth_nack = {1'b1};
    }

    cp_start_boundary: coverpoint start_boundary_s {
      bins seg_start_boundary_none    = {I3C_BOUNDARY_NONE};
      bins seg_start_boundary_initial = {I3C_BOUNDARY_START};
      bins seg_start_boundary_restart = {I3C_BOUNDARY_RESTART};
      bins seg_start_boundary_reset   = {I3C_BOUNDARY_RESET};
    }

    cp_end_boundary: coverpoint end_boundary_s {
      bins seg_end_boundary_none    = {I3C_BOUNDARY_NONE};
      bins seg_end_boundary_restart = {I3C_BOUNDARY_RESTART};
      bins seg_end_boundary_stop    = {I3C_BOUNDARY_STOP};
      bins seg_end_boundary_reset   = {I3C_BOUNDARY_RESET};
    }

    cp_ninth_count_status: coverpoint ninth_count_status_s {
      bins seg_ninth_count_empty   = {NINTH_COUNTS_EMPTY};
      bins seg_ninth_count_aligned = {NINTH_COUNTS_ALIGNED};
      bins seg_ninth_count_missing = {NINTH_COUNTS_MISSING};
      bins seg_ninth_count_extra   = {NINTH_COUNTS_EXTRA};
    }

    x_kind_direction: cross cp_kind, cp_direction {
      ignore_bins unknown =
        binsof(cp_kind.seg_kind_unknown) ||
        binsof(cp_direction.seg_direction_unknown);
      ignore_bins broadcast_read =
        binsof(cp_kind.seg_kind_broadcast) &&
        binsof(cp_direction.seg_direction_read);
      ignore_bins ibi_write =
        binsof(cp_kind.seg_kind_ibi) &&
        binsof(cp_direction.seg_direction_write);
    }

    x_kind_addr_ack: cross cp_kind, cp_addr_ninth {
      ignore_bins unknown_kind = binsof(cp_kind.seg_kind_unknown);
    }
  endgroup

  covergroup cg_data_ninth with function sample();
    option.per_instance = 1;

    cp_kind: coverpoint kind_s {
      bins d9_kind_unknown   = {I3C_KIND_UNKNOWN};
      bins d9_kind_private   = {I3C_KIND_PRIVATE};
      bins d9_kind_broadcast = {I3C_KIND_BROADCAST_CCC};
      bins d9_kind_direct    = {I3C_KIND_DIRECT_CCC};
      bins d9_kind_entdaa    = {I3C_KIND_ENTDAA};
      bins d9_kind_ibi       = {I3C_KIND_IBI};
    }

    cp_raw_ninth: coverpoint data_ninth_s {
      bins d9_value_low  = {1'b0};
      bins d9_value_high = {1'b1};
    }

    cp_read_controller_low: coverpoint data_ninth_controller_low_s
      iff (direction_s == I3C_READ) {
      bins d9_controller_released = {1'b0};
      bins d9_controller_low      = {1'b1};
    }

    cp_read_target_low: coverpoint data_ninth_target_low_s
      iff (direction_s == I3C_READ) {
      bins d9_target_released = {1'b0};
      bins d9_target_low      = {1'b1};
    }

    // Hits distinguish ordinary continuation, controller-only early end,
    // target-only End-of-Data, and the equal-length case where both pull low.
    x_read_t_drivers: cross cp_read_controller_low, cp_read_target_low;

    x_kind_data_ninth: cross cp_kind, cp_raw_ninth {
      ignore_bins unknown_kind = binsof(cp_kind.d9_kind_unknown);
    }
  endgroup

  // IBI-specific closure: distinguish the legal no-MDB and one-MDB forms,
  // and retain both OD contributors for the final target-driven T-bit.
  covergroup cg_ibi with function sample();
    option.per_instance = 1;

    cp_mdb_count: coverpoint ibi_mdb_count_s {
      bins no_mdb  = {0};
      bins one_mdb = {1};
      bins multiple_mdb = default;
    }

    cp_header_ninth: coverpoint ibi_header_ninth_s {
      bins header_ack  = {1'b0};
      bins header_nack = {1'b1};
    }

    cp_end_boundary: coverpoint ibi_end_boundary_s {
      bins ibi_stop_boundary = {I3C_BOUNDARY_STOP};
      bins ibi_other_boundary = default;
    }

    cp_final_t: coverpoint ibi_t_s iff (ibi_mdb_count_s == 1) {
      bins ibi_t_end = {1'b0};
      bins ibi_t_continue = {1'b1};
    }

    cp_controller_t_low: coverpoint ibi_controller_t_low_s
      iff (ibi_mdb_count_s == 1) {
      bins released = {1'b0};
      bins drove_low = {1'b1};
    }

    cp_target_t_low: coverpoint ibi_target_t_low_s
      iff (ibi_mdb_count_s == 1) {
      bins released = {1'b0};
      bins drove_low = {1'b1};
    }

    x_shape_ack_end: cross cp_mdb_count, cp_header_ninth, cp_end_boundary;
    x_final_t_drivers: cross cp_controller_t_low, cp_target_t_low;
  endgroup

  covergroup cg_entdaa_round with function sample();
    option.per_instance = 1;

    cp_outcome: coverpoint entdaa_round_outcome_s {
      bins round_incomplete        = {ENTDAA_ROUND_INCOMPLETE};
      bins round_success           = {ENTDAA_ROUND_SUCCESS};
      bins round_final_header_nack = {ENTDAA_ROUND_FINAL_HEADER_NACK};
      bins round_da_nack           = {ENTDAA_ROUND_DA_NACK};
      bins round_malformed         = {ENTDAA_ROUND_MALFORMED};
    }

    cp_header: coverpoint entdaa_header_s {
      bins round_entdaa_read_header = {8'hfd};
      bins round_other_header       = default;
    }

    cp_header_ninth: coverpoint entdaa_header_ninth_s {
      bins round_header_ack  = {1'b0};
      bins round_header_nack = {1'b1};
    }

    cp_parity: coverpoint entdaa_parity_status_s {
      bins round_parity_not_present = {ENTDAA_PARITY_NOT_PRESENT};
      bins round_parity_good        = {ENTDAA_PARITY_GOOD};
      bins round_parity_bad         = {ENTDAA_PARITY_BAD};
      bins round_parity_unknown     = {ENTDAA_PARITY_UNKNOWN};
    }

    cp_start_boundary: coverpoint entdaa_start_boundary_s {
      bins round_start_restart = {I3C_BOUNDARY_RESTART};
      bins round_start_other   = default;
    }

    cp_end_boundary: coverpoint entdaa_end_boundary_s {
      bins round_end_restart = {I3C_BOUNDARY_RESTART};
      bins round_end_stop    = {I3C_BOUNDARY_STOP};
      bins round_end_reset   = {I3C_BOUNDARY_RESET};
      bins round_end_other   = default;
    }

    x_outcome_end: cross cp_outcome, cp_end_boundary;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_transfer   = new();
    cg_segment    = new();
    cg_data_ninth = new();
    cg_ibi        = new();
    cg_entdaa_round = new();
  endfunction

  function void write(i3c_bus_txn t);
    if (t == null) begin
      `uvm_warning("BUS_COV", "Ignoring null i3c_bus_txn")
      return;
    end

    kind_s                  = t.kind;
    origin_s                = t.origin;
    segment_count_s         = t.segments.size();
    entdaa_round_count_s    = t.entdaa_rounds.size();
    has_start_s             = 1'b0;
    has_restart_s           = 1'b0;
    has_stop_s              = 1'b0;
    has_null_segment_s      = 1'b0;
    has_incomplete_header_s = 1'b0;

    foreach (t.segments[i]) begin
      if (t.segments[i] == null) begin
        has_null_segment_s = 1'b1;
      end
      else begin
        if (t.segments[i].start_boundary == I3C_BOUNDARY_START)
          has_start_s = 1'b1;
        if ((t.segments[i].start_boundary == I3C_BOUNDARY_RESTART) ||
            (t.segments[i].end_boundary == I3C_BOUNDARY_RESTART) ||
            t.segments[i].ended_by_restart)
          has_restart_s = 1'b1;
        if ((t.segments[i].end_boundary == I3C_BOUNDARY_STOP) ||
            t.segments[i].ended_by_stop)
          has_stop_s = 1'b1;
        if (!t.segments[i].header_complete)
          has_incomplete_header_s = 1'b1;
      end
    end

    if ((t.kind == I3C_KIND_IBI) &&
        (t.segments.size() == 1) &&
        (t.segments[0] != null)) begin
      ibi_mdb_count_s       = t.segments[0].data.size();
      ibi_header_ninth_s    = t.segments[0].addr_ninth;
      ibi_end_boundary_s    = t.segments[0].end_boundary;
      ibi_t_s               = 1'bx;
      ibi_controller_t_low_s = 1'bx;
      ibi_target_t_low_s     = 1'bx;
      if (t.segments[0].data_ninth_bits.size() > 0)
        ibi_t_s = t.segments[0].data_ninth_bits[0];
      if (t.segments[0].data_ninth_controller_low.size() > 0)
        ibi_controller_t_low_s =
          t.segments[0].data_ninth_controller_low[0];
      if (t.segments[0].data_ninth_target_low.size() > 0)
        ibi_target_t_low_s = t.segments[0].data_ninth_target_low[0];
      cg_ibi.sample();
    end


    foreach (t.entdaa_rounds[i]) begin
      if (t.entdaa_rounds[i] == null) begin
        has_null_segment_s = 1'b1;
      end
      else begin
        if ((t.entdaa_rounds[i].start_boundary == I3C_BOUNDARY_RESTART) ||
            (t.entdaa_rounds[i].end_boundary == I3C_BOUNDARY_RESTART) ||
            t.entdaa_rounds[i].ended_by_restart)
          has_restart_s = 1'b1;
        if ((t.entdaa_rounds[i].end_boundary == I3C_BOUNDARY_STOP) ||
            t.entdaa_rounds[i].ended_by_stop)
          has_stop_s = 1'b1;
        if (!t.entdaa_rounds[i].header_complete)
          has_incomplete_header_s = 1'b1;
      end
    end

    cg_transfer.sample();

    foreach (t.segments[i]) begin
      if (t.segments[i] != null) begin
        direction_s       = t.segments[i].direction;
        start_boundary_s  = t.segments[i].start_boundary;
        end_boundary_s    = t.segments[i].end_boundary;
        payload_len_s     = t.segments[i].data.size();
        header_complete_s = t.segments[i].header_complete;
        addr_ninth_s      = t.segments[i].addr_ninth;

        if ((t.segments[i].data.size() == 0) &&
            (t.segments[i].data_ninth_bits.size() == 0))
          ninth_count_status_s = NINTH_COUNTS_EMPTY;
        else if (t.segments[i].data_ninth_bits.size() ==
                 t.segments[i].data.size())
          ninth_count_status_s = NINTH_COUNTS_ALIGNED;
        else if (t.segments[i].data_ninth_bits.size() <
                 t.segments[i].data.size())
          ninth_count_status_s = NINTH_COUNTS_MISSING;
        else
          ninth_count_status_s = NINTH_COUNTS_EXTRA;

        cg_segment.sample();

        foreach (t.segments[i].data_ninth_bits[j]) begin
          data_ninth_s = t.segments[i].data_ninth_bits[j];
          if (j < t.segments[i].data_ninth_controller_low.size())
            data_ninth_controller_low_s =
              t.segments[i].data_ninth_controller_low[j];
          else
            data_ninth_controller_low_s = 1'bx;
          if (j < t.segments[i].data_ninth_target_low.size())
            data_ninth_target_low_s = t.segments[i].data_ninth_target_low[j];
          else
            data_ninth_target_low_s = 1'bx;
          cg_data_ninth.sample();
        end
      end
    end


    foreach (t.entdaa_rounds[i]) begin
      if (t.entdaa_rounds[i] != null) begin
        entdaa_start_boundary_s = t.entdaa_rounds[i].start_boundary;
        entdaa_end_boundary_s   = t.entdaa_rounds[i].end_boundary;
        entdaa_header_s         = t.entdaa_rounds[i].header;
        entdaa_header_ninth_s   = t.entdaa_rounds[i].header_ninth;

        if (!t.entdaa_rounds[i].assigned_da_complete)
          entdaa_parity_status_s = ENTDAA_PARITY_NOT_PRESENT;
        else if ((^{t.entdaa_rounds[i].assigned_da,
                    t.entdaa_rounds[i].da_parity}) === 1'b1)
          entdaa_parity_status_s = ENTDAA_PARITY_GOOD;
        else if ((^{t.entdaa_rounds[i].assigned_da,
                    t.entdaa_rounds[i].da_parity}) === 1'b0)
          entdaa_parity_status_s = ENTDAA_PARITY_BAD;
        else
          entdaa_parity_status_s = ENTDAA_PARITY_UNKNOWN;

        if (t.entdaa_rounds[i].is_successful())
          entdaa_round_outcome_s = ENTDAA_ROUND_SUCCESS;
        else if (t.entdaa_rounds[i].is_final_header_nack())
          entdaa_round_outcome_s = ENTDAA_ROUND_FINAL_HEADER_NACK;
        else if (t.entdaa_rounds[i].header_complete &&
                 (t.entdaa_rounds[i].header === 8'hfd) &&
                 (t.entdaa_rounds[i].header_ninth === 1'b0) &&
                 t.entdaa_rounds[i].id_complete &&
                 t.entdaa_rounds[i].assigned_da_complete &&
                 (entdaa_parity_status_s == ENTDAA_PARITY_GOOD) &&
                 t.entdaa_rounds[i].da_ack_complete &&
                 (t.entdaa_rounds[i].da_ack === 1'b1) &&
                 (t.entdaa_rounds[i].end_boundary == I3C_BOUNDARY_STOP))
          entdaa_round_outcome_s = ENTDAA_ROUND_DA_NACK;
        else if (!t.entdaa_rounds[i].header_complete ||
                 ((t.entdaa_rounds[i].header_ninth === 1'b0) &&
                  (!t.entdaa_rounds[i].id_complete ||
                   !t.entdaa_rounds[i].assigned_da_complete ||
                   !t.entdaa_rounds[i].da_ack_complete)))
          entdaa_round_outcome_s = ENTDAA_ROUND_INCOMPLETE;
        else
          entdaa_round_outcome_s = ENTDAA_ROUND_MALFORMED;

        cg_entdaa_round.sample();
      end
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("BUS_COV", $sformatf("Transfer coverage: %0.1f%%",
              cg_transfer.get_coverage()), UVM_LOW)
    `uvm_info("BUS_COV", $sformatf("Segment coverage: %0.1f%%",
              cg_segment.get_coverage()), UVM_LOW)
    `uvm_info("BUS_COV", $sformatf("Data ninth-bit coverage: %0.1f%%",
              cg_data_ninth.get_coverage()), UVM_LOW)
    `uvm_info("BUS_COV", $sformatf("IBI coverage: %0.1f%%",
              cg_ibi.get_coverage()), UVM_LOW)
    `uvm_info("BUS_COV", $sformatf("ENTDAA round coverage: %0.1f%%",
              cg_entdaa_round.get_coverage()), UVM_LOW)
  endfunction
endclass
