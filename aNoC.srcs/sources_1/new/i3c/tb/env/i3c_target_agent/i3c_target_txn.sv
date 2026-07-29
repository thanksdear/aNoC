typedef enum logic [1:0] {
  I3C_TARGET_CONFIG,
  I3C_TARGET_IBI
} i3c_target_op_e;

class i3c_target_cfg extends uvm_object;
  `uvm_object_utils(i3c_target_cfg)

  uvm_active_passive_enum is_active = UVM_ACTIVE;
  logic [6:0]              static_addr = 7'h12;
  logic [63:0]             entdaa_id = 64'h1234_5678_9abc_de01;
  logic [6:0]              entdaa_expected_da = 7'h01;
  int unsigned             max_read_bytes = 256;

  function new(string name = "i3c_target_cfg");
    super.new(name);
  endfunction
endclass

// Target-side stimulus item.  Controller/APB sequences must not need to know
// which interface sideband controls the target BFM; they describe the desired
// target behavior with this object and send it through the target sequencer.
class i3c_target_txn extends uvm_sequence_item;
  rand i3c_target_op_e op;

  // Response configuration used by controller-initiated transfers.
  rand logic          ack_addr;
  rand logic          read_enable;
  rand logic          i2c_read_mode;
  rand logic          i3c_write_tbit_mode;
  rand int unsigned   i2c_write_ack_count;
  // -1 disables injection; otherwise corrupt this zero-based I3C write
  // payload byte's odd-parity T-bit.
  rand int            write_parity_error_index;
  rand logic          ccc_ack_enable;
  rand logic          ccc_direct_enable;
  rand logic          entdaa_participate;
  // A participating target may reject the controller-assigned dynamic
  // address.  This terminates ENTDAA after exactly one arbitration round.
  rand logic          entdaa_expect_da_ack;
  rand logic [7:0]    read_data[];

  // Target-initiated IBI request.
  rand logic [6:0]    ibi_addr;
  rand logic          ibi_has_mdb;
  rand logic [7:0]    ibi_mdb;
  rand logic          ibi_expect_addr_ack;

  constraint c_read_size {
    read_data.size() <= 256;
  }

  `uvm_object_utils_begin(i3c_target_txn)
    `uvm_field_enum(i3c_target_op_e, op, UVM_ALL_ON)
    `uvm_field_int(ack_addr, UVM_ALL_ON)
    `uvm_field_int(read_enable, UVM_ALL_ON)
    `uvm_field_int(i2c_read_mode, UVM_ALL_ON)
    `uvm_field_int(i3c_write_tbit_mode, UVM_ALL_ON)
    `uvm_field_int(i2c_write_ack_count, UVM_ALL_ON)
    `uvm_field_int(write_parity_error_index, UVM_ALL_ON)
    `uvm_field_int(ccc_ack_enable, UVM_ALL_ON)
    `uvm_field_int(ccc_direct_enable, UVM_ALL_ON)
    `uvm_field_int(entdaa_participate, UVM_ALL_ON)
    `uvm_field_int(entdaa_expect_da_ack, UVM_ALL_ON)
    `uvm_field_array_int(read_data, UVM_ALL_ON)
    `uvm_field_int(ibi_addr, UVM_ALL_ON)
    `uvm_field_int(ibi_has_mdb, UVM_ALL_ON)
    `uvm_field_int(ibi_mdb, UVM_ALL_ON)
    `uvm_field_int(ibi_expect_addr_ack, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "i3c_target_txn");
    super.new(name);
    op = I3C_TARGET_CONFIG;
    ack_addr = 1'b0;
    read_enable = 1'b0;
    i2c_read_mode = 1'b0;
    i3c_write_tbit_mode = 1'b0;
    i2c_write_ack_count = 0;
    write_parity_error_index = -1;
    ccc_ack_enable = 1'b0;
    ccc_direct_enable = 1'b0;
    entdaa_participate = 1'b0;
    entdaa_expect_da_ack = 1'b1;
    ibi_addr = 7'h12;
    ibi_has_mdb = 1'b0;
    ibi_mdb = '0;
    ibi_expect_addr_ack = 1'b1;
  endfunction
endclass
