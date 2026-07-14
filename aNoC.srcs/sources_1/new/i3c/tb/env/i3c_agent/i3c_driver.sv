// ===== 3. driver:拿 transaction, 翻译成线上电平(component 体系)=====
class i3c_driver extends uvm_driver #(i3c_txn);
	`uvm_component_utils(i3c_driver)
	virtual i3c_if vif;

  	function new(string name, uvm_component parent); super.new(name, parent); endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if (!uvm_config_db#(virtual i3c_if)::get(this, "", "vif", vif))
		`uvm_fatal("DRV", "driver 拿不到 vif")
	endfunction

	task run_phase(uvm_phase phase);
	    @(vif.drv_cb);                 // 等第一个时钟事件后, 才能通过 cb 驱动
	    vif.drv_cb.psel    <= 0;
	    vif.drv_cb.penable <= 0;
	    vif.drv_cb.pwrite  <= 0;
	    vif.drv_cb.paddr   <= 0;
	    vif.drv_cb.pwdata  <= 0;
	    vif.drv_cb.pstrb   <= 0;
    forever begin
      i3c_txn tr;
      seq_item_port.get_next_item(tr);  // 握手③:跟 sequencer 要一笔, 没有就阻塞
      drive(tr);
      seq_item_port.item_done();        // 握手④:回执"这笔搞定", 放 sequence 走
    end
  	endtask

	task apb_write(i3c_txn tr);
	    repeat(tr.start_delay) @(vif.drv_cb);
	    vif.drv_cb.paddr   <= {4'd0, tr.addr};
	    vif.drv_cb.pwdata  <= tr.data;
	    vif.drv_cb.pstrb   <= tr.strb;
	    vif.drv_cb.pwrite  <= 1'b1;
	    vif.drv_cb.psel    <= 1'b1;
	    vif.drv_cb.penable <= 1'b0;
	    @(vif.drv_cb);
	    vif.drv_cb.penable <= 1'b1;
	    do @(vif.drv_cb); while (!vif.drv_cb.pready);
	    vif.drv_cb.psel    <= 1'b0;
	    vif.drv_cb.penable <= 1'b0;
	    vif.drv_cb.pwrite  <= 1'b0;
	    vif.drv_cb.pstrb   <= 4'd0;
	endtask

	task apb_read(i3c_txn tr);
	    repeat(tr.start_delay) @(vif.drv_cb);
	    vif.drv_cb.paddr   <= {4'd0, tr.addr};
	    vif.drv_cb.pwdata  <= '0;
	    vif.drv_cb.pstrb   <= 4'd0;
	    vif.drv_cb.pwrite  <= 1'b0;
	    vif.drv_cb.psel    <= 1'b1;
	    vif.drv_cb.penable <= 1'b0;
	    @(vif.drv_cb);
	    vif.drv_cb.penable <= 1'b1;
	    do @(vif.drv_cb); while (!vif.drv_cb.pready);
	    tr.data = vif.drv_cb.prdata;
	    vif.drv_cb.psel    <= 1'b0;
	    vif.drv_cb.penable <= 1'b0;
	endtask

	task drive(i3c_txn tr);
		@(vif.drv_cb);
		if(tr.op === WR)begin
			apb_write(tr);
		end else begin
			apb_read(tr);
		end
	endtask
endclass
