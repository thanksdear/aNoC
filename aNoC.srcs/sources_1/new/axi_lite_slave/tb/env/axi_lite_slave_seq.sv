// ===== 2. sequence:造一串 transaction 的"剧本"(也是 object,跑在自己线程里)=====
class axi_lite_slave_seq extends uvm_sequence #(axi_lite_slave_txn);
  `uvm_object_utils(axi_lite_slave_seq)
  function new(string name = "axi_lite_slave_seq"); super.new(name); endfunction

  task body();
    repeat(16)begin
      axi_lite_slave_txn tr = axi_lite_slave_txn::type_id::create("tr");
      start_item(tr);               // 握手①:申请通道, 阻塞等 driver 来要
      assert(tr.randomize() with {op == WR;}); // 拿到通道后再随机填 data
      finish_item(tr);                  // 握手②:交付, 阻塞等 driver 说"处理完了"
      `uvm_info("SEQ", $sformatf("WRITE 0x%08h", tr.data), UVM_MEDIUM)
    end
    repeat (16) begin
      axi_lite_slave_txn tr = axi_lite_slave_txn::type_id::create("tr");
      start_item(tr);               // 握手①:申请通道, 阻塞等 driver 来要
      assert(tr.randomize() with {op == RD;}); // 拿到通道后再随机填 data
      finish_item(tr);                  // 握手②:交付, 阻塞等 driver 说"处理完了"
      `uvm_info("SEQ", "READ",UVM_MEDIUM)
    end
  endtask
endclass