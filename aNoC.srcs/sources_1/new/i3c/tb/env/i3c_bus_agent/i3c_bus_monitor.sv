class i3c_bus_monitor extends uvm_monitor;
	`uvm_component_utils(i3c_bus_monitor)

	virtual i3c_if vif;
	uvm_analysis_port #(i3c_bus_txn) ap;

	function new(string name, uvm_component parent);
		super.new(name, parent);
		ap = new("ap", this);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if (!uvm_config_db#(virtual i3c_if)::get(this, "", "vif", vif))
		`uvm_fatal("I3C_MON", "cannot get vif")
	endfunction
	
//SCL 为高时SDA下降，表示START
	task wait_start();
		forever begin
			@(negedge vif.sda_in);
			if(vif.scl_in === 1'b1)
				return ;
		end
  	endtask

// SCL 为高时 SDA 上升，表示 STOP
	task wait_stop();
		forever begin
		@(posedge vif.sda_in);

		if (vif.scl_in === 1'b1)
			return;
		end
	endtask

	task sample_byte(output bit [7:0] value);
		for (int i = 7; i >= 0; i--) begin
			@(posedge vif.scl_in);
			value[i] = vif.sda_in;
		end
	endtask

	task sample_ninth_bit(output bit value);
		@(posedge vif.scl_in);
		value = vif.sda_in;
	endtask

	task sample_byte_with_ninth(output bit [7:0] value,
									 output bit ninth_bit);
		sample_byte(value);
		sample_ninth_bit(ninth_bit);
	endtask

	task collect_header(i3c_bus_txn tr);
		bit [7:0] header;
		bit       ninth_bit;

		sample_byte_with_ninth(header, ninth_bit);
		tr.addr = header[7:1];
		tr.direction = header[0] ? I3C_READ : I3C_WRITE;

		tr.addr_ack = (ninth_bit === 1'b0);
	// 接下来采集
	endtask

  task collect_payload_until_stop(i3c_bus_txn tr);
    bit       byte_completed;
    bit       stop_detected;
    bit [7:0] sampled_byte;
    bit       sampled_ninth_bit;

    forever begin
      byte_completed = 1'b0;
      stop_detected  = 1'b0;

      fork : BYTE_OR_STOP
        begin
          sample_byte_with_ninth(
            sampled_byte,
            sampled_ninth_bit
          );

          byte_completed = 1'b1;
        end

        begin
          wait_stop();

          stop_detected = 1'b1;
          tr.stop_seen  = 1'b1;
        end
      join_any

      disable BYTE_OR_STOP;

      if (stop_detected)
        return;

      if (byte_completed) begin
        tr.data.push_back(sampled_byte);
        tr.data_ninth_bits.push_back(sampled_ninth_bit);
      end
    end
  endtask

	task run_phase(uvm_phase phase);
		forever begin
			i3c_bus_txn tr;
			wait_start();// 等待起始位
			tr = i3c_bus_txn::type_id::create("tr");//申请句柄
			collect_header(tr);
			collect_payload_until_stop(tr);
			`uvm_info(
				"I3C_MON",$sformatf(
				"captured addr=0x%02h direction=%s ack=%0b data=%p stop=%0b",
				tr.addr,
				tr.direction.name(),
				tr.addr_ack,
				tr.data,
				tr.stop_seen
				),
				UVM_LOW
			)
			ap.write(tr);
		end
	endtask
endclass