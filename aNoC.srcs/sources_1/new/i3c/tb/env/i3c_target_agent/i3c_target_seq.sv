// Generic target sequence.  Tests can fill req directly, while derived
// sequences can add constraints without touching the target driver or vif.
class i3c_target_seq extends uvm_sequence #(i3c_target_txn);
  `uvm_object_utils(i3c_target_seq)

  i3c_target_txn req;

  function new(string name = "i3c_target_seq");
    super.new(name);
  endfunction

  task body();
    if (req == null)
      `uvm_fatal("TGT_SEQ", "target sequence req is null")
    start_item(req);
    finish_item(req);
  endtask
endclass

class i3c_target_idle_seq extends uvm_sequence #(i3c_target_txn);
  `uvm_object_utils(i3c_target_idle_seq)

  function new(string name = "i3c_target_idle_seq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn req;
    req = i3c_target_txn::type_id::create("req");
    start_item(req);
    req.op = I3C_TARGET_CONFIG;
    finish_item(req);
  endtask
endclass

class i3c_target_ibi_seq extends uvm_sequence #(i3c_target_txn);
  `uvm_object_utils(i3c_target_ibi_seq)

  logic [6:0] addr = 7'h12;
  logic       has_mdb = 1'b0;
  logic [7:0] mdb = '0;
  logic       expect_addr_ack = 1'b1;

  function new(string name = "i3c_target_ibi_seq");
    super.new(name);
  endfunction

  task body();
    i3c_target_txn req;
    req = i3c_target_txn::type_id::create("req");
    start_item(req);
    req.op = I3C_TARGET_IBI;
    req.ibi_addr = addr;
    req.ibi_has_mdb = has_mdb;
    req.ibi_mdb = mdb;
    req.ibi_expect_addr_ack = expect_addr_ack;
    finish_item(req);
  endtask
endclass
