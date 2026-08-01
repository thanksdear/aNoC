// Lightweight RAL model for the memory-mapped CSR set.  FIFO data ports are
// intentionally excluded because CMD/TX writes and RESP/RX reads have push/pop
// side effects and must not be mirrored like ordinary registers.

class i3c_bus_timing_0_reg extends uvm_reg;
  `uvm_object_utils(i3c_bus_timing_0_reg)

  rand uvm_reg_field scl_low;
  rand uvm_reg_field scl_high;

  function new(string name = "i3c_bus_timing_0_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    scl_low = uvm_reg_field::type_id::create("scl_low");
    scl_low.configure(this, 16, 0, "RW", 0, 16'd6, 1, 1, 1);
    scl_high = uvm_reg_field::type_id::create("scl_high");
    scl_high.configure(this, 16, 16, "RW", 0, 16'd6, 1, 1, 1);
  endfunction
endclass

class i3c_bus_timing_1_reg extends uvm_reg;
  `uvm_object_utils(i3c_bus_timing_1_reg)

  rand uvm_reg_field sda_hold;

  function new(string name = "i3c_bus_timing_1_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    sda_hold = uvm_reg_field::type_id::create("sda_hold");
    sda_hold.configure(this, 16, 0, "RW", 0, 16'd2, 1, 1, 1);
  endfunction
endclass

class i3c_ctrl_reg extends uvm_reg;
  `uvm_object_utils(i3c_ctrl_reg)

  rand uvm_reg_field i3c_mode;
  rand uvm_reg_field core_en;
  uvm_reg_field      sw_rst;
  rand uvm_reg_field ibi_en;
  rand uvm_reg_field ibi_mdb_en;

  function new(string name = "i3c_ctrl_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    i3c_mode = uvm_reg_field::type_id::create("i3c_mode");
    i3c_mode.configure(this, 1, 0, "RW", 0, 1'b1, 1, 1, 1);
    core_en = uvm_reg_field::type_id::create("core_en");
    core_en.configure(this, 1, 1, "RW", 0, 1'b0, 1, 1, 1);

    // Hardware clears this field on the cycle after a write.  Volatile keeps
    // RAL from assuming the value remains equal to the last frontdoor write.
    sw_rst = uvm_reg_field::type_id::create("sw_rst");
    sw_rst.configure(this, 1, 2, "RW", 1, 1'b0, 1, 0, 1);

    ibi_en = uvm_reg_field::type_id::create("ibi_en");
    ibi_en.configure(this, 1, 3, "RW", 0, 1'b0, 1, 1, 1);
    ibi_mdb_en = uvm_reg_field::type_id::create("ibi_mdb_en");
    ibi_mdb_en.configure(this, 1, 4, "RW", 0, 1'b0, 1, 1, 1);
  endfunction
endclass

class i3c_status_reg extends uvm_reg;
  `uvm_object_utils(i3c_status_reg)

  uvm_reg_field busy;
  uvm_reg_field ibi_pending;

  function new(string name = "i3c_status_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    busy = uvm_reg_field::type_id::create("busy");
    busy.configure(this, 1, 0, "RO", 1, 1'b0, 1, 0, 1);
    ibi_pending = uvm_reg_field::type_id::create("ibi_pending");
    ibi_pending.configure(this, 1, 1, "RO", 1, 1'b0, 1, 0, 1);
  endfunction
endclass

class i3c_ibi_status_reg extends uvm_reg;
  `uvm_object_utils(i3c_ibi_status_reg)

  uvm_reg_field ibi_addr;
  uvm_reg_field has_mdb;
  uvm_reg_field length;
  uvm_reg_field valid;

  function new(string name = "i3c_ibi_status_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    ibi_addr = uvm_reg_field::type_id::create("ibi_addr");
    ibi_addr.configure(this, 7, 0, "RO", 1, 7'h00, 1, 0, 1);
    has_mdb = uvm_reg_field::type_id::create("has_mdb");
    has_mdb.configure(this, 1, 7, "RO", 1, 1'b0, 1, 0, 1);
    length = uvm_reg_field::type_id::create("length");
    length.configure(this, 8, 8, "RO", 1, 8'h00, 1, 0, 1);
    valid = uvm_reg_field::type_id::create("valid");
    valid.configure(this, 1, 16, "W1C", 1, 1'b0, 1, 0, 1);
  endfunction
endclass

class i3c_err_status_reg extends uvm_reg;
  `uvm_object_utils(i3c_err_status_reg)

  uvm_reg_field parity_err;
  uvm_reg_field nack_err;

  function new(string name = "i3c_err_status_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    parity_err = uvm_reg_field::type_id::create("parity_err");
    parity_err.configure(this, 1, 0, "W1C", 1, 1'b0, 1, 0, 1);
    nack_err = uvm_reg_field::type_id::create("nack_err");
    nack_err.configure(this, 1, 1, "W1C", 1, 1'b0, 1, 0, 1);
  endfunction
endclass

class i3c_entdaa_status_reg extends uvm_reg;
  `uvm_object_utils(i3c_entdaa_status_reg)

  uvm_reg_field assigned_da;
  uvm_reg_field valid;

  function new(string name = "i3c_entdaa_status_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    assigned_da = uvm_reg_field::type_id::create("assigned_da");
    assigned_da.configure(this, 7, 0, "RO", 1, 7'h00, 1, 0, 1);
    valid = uvm_reg_field::type_id::create("valid");
    valid.configure(this, 1, 8, "RO", 1, 1'b0, 1, 0, 1);
  endfunction
endclass

class i3c_pid_reg extends uvm_reg;
  `uvm_object_utils(i3c_pid_reg)

  uvm_reg_field value;

  function new(string name = "i3c_pid_reg");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    value = uvm_reg_field::type_id::create("value");
    value.configure(this, 32, 0, "RO", 1, 32'h0, 1, 0, 1);
  endfunction
endclass

class i3c_reg_block extends uvm_reg_block;
  `uvm_object_utils(i3c_reg_block)

  rand i3c_bus_timing_0_reg bus_timing_0;
  rand i3c_bus_timing_1_reg bus_timing_1;
  rand i3c_ctrl_reg         ctrl;
  rand i3c_status_reg       status;
  rand i3c_ibi_status_reg   ibi_status;
  rand i3c_err_status_reg   err_status;
  rand i3c_entdaa_status_reg entdaa_status;
  rand i3c_pid_reg          entdaa_pid_lo;
  rand i3c_pid_reg          entdaa_pid_hi;

  function new(string name = "i3c_reg_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    default_map = create_map(
      "apb_map",
      'h0,
      4,
      UVM_LITTLE_ENDIAN,
      1
    );

    bus_timing_0 =
      i3c_bus_timing_0_reg::type_id::create("bus_timing_0");
    bus_timing_0.configure(this);
    bus_timing_0.build();
    default_map.add_reg(bus_timing_0, 'h00, "RW");

    bus_timing_1 =
      i3c_bus_timing_1_reg::type_id::create("bus_timing_1");
    bus_timing_1.configure(this);
    bus_timing_1.build();
    default_map.add_reg(bus_timing_1, 'h04, "RW");

    ctrl = i3c_ctrl_reg::type_id::create("ctrl");
    ctrl.configure(this);
    ctrl.build();
    default_map.add_reg(ctrl, 'h08, "RW");

    status = i3c_status_reg::type_id::create("status");
    status.configure(this);
    status.build();
    default_map.add_reg(status, 'h0c, "RO");

    ibi_status =
      i3c_ibi_status_reg::type_id::create("ibi_status");
    ibi_status.configure(this);
    ibi_status.build();
    default_map.add_reg(ibi_status, 'h10, "RW");

    err_status =
      i3c_err_status_reg::type_id::create("err_status");
    err_status.configure(this);
    err_status.build();
    default_map.add_reg(err_status, 'h14, "RW");

    entdaa_status =
      i3c_entdaa_status_reg::type_id::create("entdaa_status");
    entdaa_status.configure(this);
    entdaa_status.build();
    default_map.add_reg(entdaa_status, 'h18, "RO");

    entdaa_pid_lo = i3c_pid_reg::type_id::create("entdaa_pid_lo");
    entdaa_pid_lo.configure(this);
    entdaa_pid_lo.build();
    default_map.add_reg(entdaa_pid_lo, 'h1c, "RO");

    entdaa_pid_hi = i3c_pid_reg::type_id::create("entdaa_pid_hi");
    entdaa_pid_hi.configure(this);
    entdaa_pid_hi.build();
    default_map.add_reg(entdaa_pid_hi, 'h30, "RO");
  endfunction
endclass

class i3c_reg_adapter extends uvm_reg_adapter;
  `uvm_object_utils(i3c_reg_adapter)

  function new(string name = "i3c_reg_adapter");
    super.new(name);
    supports_byte_enable = 1;
    provides_responses = 0;
  endfunction

  virtual function uvm_sequence_item reg2bus(
    const ref uvm_reg_bus_op rw
  );
    i3c_txn tr;

    tr = i3c_txn::type_id::create("ral_apb_req");
    tr.op = (rw.kind == UVM_READ) ? RD : WR;
    tr.addr = rw.addr[7:0];
    tr.data = rw.data;
    tr.strb =
      (rw.kind == UVM_WRITE) ? rw.byte_en[3:0] : 4'h0;
    tr.start_delay = 0;
    return tr;
  endfunction

  virtual function void bus2reg(
    uvm_sequence_item bus_item,
    ref uvm_reg_bus_op rw
  );
    i3c_txn tr;

    if (!$cast(tr, bus_item)) begin
      `uvm_fatal("RAL_ADAPTER", "bus item is not an i3c_txn")
      return;
    end
    rw.kind = (tr.op == RD) ? UVM_READ : UVM_WRITE;
    rw.addr = tr.addr;
    rw.data = tr.data;
    rw.byte_en = tr.strb;
    rw.status = UVM_IS_OK;
  endfunction
endclass

// The APB monitor observes FIFO ports as well as CSRs.  This analysis filter
// prevents the generic predictor from looking up side-effect ports that are
// intentionally absent from the register map.
class i3c_reg_apb_filter extends uvm_component;
  `uvm_component_utils(i3c_reg_apb_filter)

  uvm_analysis_imp  #(i3c_txn, i3c_reg_apb_filter) bus_in;
  uvm_analysis_port #(i3c_txn)                     csr_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    bus_in = new("bus_in", this);
    csr_ap = new("csr_ap", this);
  endfunction

  function bit is_csr_addr(logic [7:0] addr);
    return addr inside {
      8'h00, 8'h04, 8'h08, 8'h0c, 8'h10,
      8'h14, 8'h18, 8'h1c, 8'h30
    };
  endfunction

  function void write(i3c_txn tr);
    if (is_csr_addr(tr.addr))
      csr_ap.write(tr);
  endfunction
endclass
