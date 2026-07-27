// Coordinates controller/APB and target-side stimulus without making either
// sequence reach through the virtual interface to configure its peer.
class i3c_virtual_sequencer extends uvm_sequencer;
  `uvm_component_utils(i3c_virtual_sequencer)

  uvm_sequencer #(i3c_txn)        apb_sqr;
  uvm_sequencer #(i3c_target_txn) target_sqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
