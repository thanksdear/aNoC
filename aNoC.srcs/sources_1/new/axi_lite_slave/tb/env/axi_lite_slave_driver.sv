// ===== 3. driver:拿 transaction, 翻译成线上电平(component 体系)=====
class axi_lite_slave_driver extends uvm_driver #(axi_lite_slave_txn);
  `uvm_component_utils(axi_lite_slave_driver)
  virtual axi_lite_slave_if vif;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_lite_slave_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "driver 拿不到 vif")
  endfunction

  task run_phase(uvm_phase phase);
    @(vif.drv_cb);                 // 等第一个时钟事件后, 才能通过 cb 驱动
    vif.drv_cb.awaddr   <= 0;
    vif.drv_cb.awvalid  <= 0;
    vif.drv_cb.wdata    <= 0;
    vif.drv_cb.wstrb    <= 0;
    vif.drv_cb.wvalid   <= 0;
    vif.drv_cb.bready   <= 0;
    vif.drv_cb.araddr   <= 0;
    vif.drv_cb.arvalid  <= 0;
    vif.drv_cb.rready   <= 0;
    forever begin
      axi_lite_slave_txn tr;
      seq_item_port.get_next_item(tr);  // 握手③:跟 sequencer 要一笔, 没有就阻塞
      drive(tr);
      seq_item_port.item_done();        // 握手④:回执"这笔搞定", 放 sequence 走
    end
  endtask

  task axi_write(axi_lite_slave_txn tr);
      vif.drv_cb.awaddr <= tr.addr; vif.drv_cb.awvalid <= 1;
      do@(vif.drv_cb);while(!vif.drv_cb.awready);   // 等 AW 握手完成
      vif.drv_cb.awvalid <= 0;
      repeat(tr.start_delay)@(vif.drv_cb);           // 延迟 5 拍再发 W
      vif.drv_cb.wdata <= tr.data; vif.drv_cb.wstrb <= tr.strb; vif.drv_cb.wvalid <= 1;
      vif.drv_cb.bready <= 1;
      do@(vif.drv_cb);while(!vif.drv_cb.wready);    // 等 W 握手完成
      vif.drv_cb.wvalid <= 0;
      do@(vif.drv_cb);while(!vif.drv_cb.bvalid);    // 等 B 响应
      vif.drv_cb.bready <= 0;
  endtask

  task axi_read(axi_lite_slave_txn tr);
      vif.drv_cb.araddr <= tr.addr;vif.drv_cb.arvalid <= 1;
      vif.drv_cb.rready <= 1;
      do@(vif.drv_cb);while (!vif.drv_cb.arready);
      vif.drv_cb.arvalid <= 0;
      do@(vif.drv_cb);while (!vif.drv_cb.rvalid);
      vif.drv_cb.rready <= 0;
  endtask

  task drive(axi_lite_slave_txn tr);
      @(vif.drv_cb);
      if(tr.op === WR)begin
        axi_write(tr);
      end else begin
        axi_read(tr);
      end
    endtask
endclass