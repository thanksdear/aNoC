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
