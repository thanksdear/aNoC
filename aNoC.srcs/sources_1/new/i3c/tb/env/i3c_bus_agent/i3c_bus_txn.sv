typedef enum bit {
  I3C_WRITE,
  I3C_READ
} i3c_direction_e;

//这个transaction是对总线上的一笔事务的抽象，包含了所有的状态信息。
class i3c_bus_txn extends uvm_sequence_item;
  i3c_direction_e  direction;
  bit [6:0]        addr;
  bit [7:0]        data[$];
  bit              data_ninth_bits[$];
  bit              stop_seen;
  bit              addr_ack;

  `uvm_object_utils_begin(i3c_bus_txn)
    `uvm_field_enum(i3c_direction_e, direction, UVM_ALL_ON)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_int(stop_seen, UVM_ALL_ON)
    `uvm_field_int(addr_ack, UVM_ALL_ON)
    `uvm_field_queue_int(data, UVM_ALL_ON)
    `uvm_field_queue_int(data_ninth_bits, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "i3c_bus_txn");
    super.new(name);
  endfunction
endclass