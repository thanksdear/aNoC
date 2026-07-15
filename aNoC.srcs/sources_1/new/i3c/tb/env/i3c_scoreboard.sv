class i3c_sb extends uvm_scoreboard;
  `uvm_component_utils(i3c_sb)
  
  localparam bit [7:0] REG_BUS_TIMING_0 = 8'h00;
  localparam bit [7:0] REG_BUS_TIMING_1 = 8'h04;
  localparam bit [7:0] REG_CTRL         = 8'h08;

  uvm_analysis_imp #(i3c_txn,i3c_sb) ain;
  bit [31:0] ref_q[16];
  bit        written[16];
  int n_pass ,n_fail;
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ain = new("ain", this);    // imp 在构造里建好, 绑到 this(我来实现 write)
  endfunction

  function bit is_mirror_reg(bit [7:0] addr);
    return (addr == REG_BUS_TIMING_0) ||
           (addr == REG_BUS_TIMING_1) ||
           (addr == REG_CTRL);
  endfunction

  function bit [31:0] read_mask(bit [7:0] addr);
    case (addr)
      REG_BUS_TIMING_0: return 32'hffff_ffff;
      REG_BUS_TIMING_1: return 32'h0000_ffff;
      REG_CTRL:         return 32'h0000_001f;
      default:          return 32'h0000_0000;
    endcase
  endfunction
  
  function void write(i3c_txn tr);
    int idx = tr.addr[5:2];
    bit [31:0] mask;

    if (!is_mirror_reg(tr.addr))
      return;

    if(tr.op == WR) begin
      for(int i=0;i<4;i++)begin
        if(tr.strb[i]) begin
          ref_q[idx][i*8 +: 8] = tr.data[i*8 +: 8];
          `uvm_info("SB",$sformatf("WRITE 0x%08h to addr 0x%08h",tr.data[(i+1)*8-1 -: 8],tr.addr+i),UVM_MEDIUM)
        end
      end
      if (tr.addr == REG_CTRL)
        ref_q[idx][2] = 1'b0;
      written[idx] = 1;	
    end
    else begin
      if(!written[idx]) return;
      begin
        bit [31:0] exp = ref_q[idx];
        mask = read_mask(tr.addr);
        if((tr.data & mask) === (exp & mask)) begin
          `uvm_info("SB",$sformatf("addr 0x%02h: 0x%08h == 0x%08h mask 0x%08h match",
                                   tr.addr, tr.data, exp, mask),UVM_MEDIUM)
          n_pass++;
        end
        else begin
          `uvm_error("SB",$sformatf("addr 0x%02h: 0x%08h != 0x%08h mask 0x%08h",
                                    tr.addr, tr.data, exp, mask))
          n_fail++;
        end
      end
    end
  endfunction
  
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SB",$sformatf("finish: pass %0d, fail %0d",n_pass, n_fail),UVM_MEDIUM)
  endfunction
endclass    


class i3c_bus_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(i3c_bus_scoreboard)
  localparam bit [7:0] CMD_PORT = 8'h20;
  localparam bit [7:0] TX_PORT  = 8'h28;
  localparam bit [7:0] RX_PORT  = 8'h2c;

  uvm_tlm_analysis_fifo #(i3c_txn)     apb_fifo;
  uvm_tlm_analysis_fifo #(i3c_bus_txn) bus_fifo;
  bit [7:0] tx_data_q[$];
  bit [7:0] observed_read_data_q[$];

  virtual i3c_if vif;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual i3c_if)::get(this, "", "vif", vif))
      `uvm_fatal("I3C_SB", "cannot get vif")
  endfunction
  typedef struct {
    bit [6:0] addr;
    bit       rw;
    bit [7:0] length;
    bit       expect_addr_ack;
  } expected_cmd_t;

  expected_cmd_t expected_cmd_q[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    apb_fifo = new("apb_fifo", this);
    bus_fifo = new("bus_fifo", this);
  endfunction

  task run_phase(uvm_phase phase);
    fork
      process_apb();
      process_i3c_bus();
    join
  endtask

  task process_apb();
    i3c_txn apb_tr;
    expected_cmd_t cmd;

    forever begin
      apb_fifo.get(apb_tr);

      if (apb_tr.op == WR && apb_tr.addr == TX_PORT) begin
        tx_data_q.push_back(apb_tr.data[7:0]);
      end

      else if (apb_tr.op == WR && apb_tr.addr == CMD_PORT) begin
        // 第一版只处理 private transfer
        if (apb_tr.data[1] == 1'b0) begin
          cmd.addr   = apb_tr.data[23:17];
          cmd.rw     = apb_tr.data[16];
          cmd.length = apb_tr.data[31:24];
          cmd.expect_addr_ack = vif.slave_ack_addr;
          expected_cmd_q.push_back(cmd);
        end
      end

      else if (apb_tr.op == RD && apb_tr.addr == RX_PORT) begin
        check_rx_port(apb_tr.data[7:0]);
      end
    end
  endtask

  task process_i3c_bus();
    i3c_bus_txn actual;
    expected_cmd_t expected;

    forever begin
      bus_fifo.get(actual);

      if (expected_cmd_q.size() == 0) begin
        `uvm_error(
          "I3C_SB",
          "Observed I3C transaction without corresponding APB command"
        )
        continue;
      end

      expected = expected_cmd_q.pop_front();

      check_common(actual, expected);

      if (expected.rw == 1'b0)
        check_private_write(actual, expected);
      else
        save_private_read(actual, expected);
    end
  endtask

  task check_common(
    i3c_bus_txn actual,
    expected_cmd_t expected
  );
    i3c_direction_e expected_direction;

    expected_direction =
      expected.rw ? I3C_READ : I3C_WRITE;

    if (actual.addr !== expected.addr)
      `uvm_error(
        "I3C_SB",
        $sformatf(
          "Address mismatch: actual=0x%02h expected=0x%02h",
          actual.addr,
          expected.addr
        )
      )

    if (actual.direction != expected_direction)
      `uvm_error(
        "I3C_SB",
        $sformatf(
          "Direction mismatch: actual=%s expected=%s",
          actual.direction.name(),
          expected_direction.name()
        )
      )

    if (actual.addr_ack !== expected.expect_addr_ack)
      `uvm_error(
        "I3C_SB",
        $sformatf(
          "Address ACK mismatch: actual=%0b expected=%0b",
          actual.addr_ack,
          expected.expect_addr_ack
        )
      )

    if (!actual.stop_seen)
      `uvm_error("I3C_SB", "I3C transaction has no STOP")

    if (actual.data.size() != expected.length)
      `uvm_error(
        "I3C_SB",
        $sformatf(
          "Length mismatch: actual=%0d expected=%0d",
          actual.data.size(),
          expected.length
        )
      )
  endtask

  task check_private_write(
      i3c_bus_txn actual,
      expected_cmd_t expected
    );
    bit [7:0] expected_byte;

    for (int i = 0; i < expected.length; i++) begin
      if (tx_data_q.size() == 0) begin
        `uvm_error(
          "I3C_SB",
          $sformatf("TX data queue empty at byte %0d", i)
        )
        return;
      end

      expected_byte = tx_data_q.pop_front();

      if (i >= actual.data.size())
        continue;

      if (actual.data[i] !== expected_byte)
        `uvm_error(
          "I3C_SB",
          $sformatf(
            "Write data[%0d] mismatch: actual=0x%02h expected=0x%02h",
            i,
            actual.data[i],
            expected_byte
          )
        )
    end
  endtask

    task save_private_read(
    i3c_bus_txn actual,
    expected_cmd_t expected
  );
    foreach (actual.data[i])
      observed_read_data_q.push_back(actual.data[i]);
  endtask

    task check_rx_port(bit [7:0] apb_rx_data);
    bit [7:0] expected_byte;

    if (observed_read_data_q.size() == 0) begin
      `uvm_error(
        "I3C_SB",
        $sformatf(
          "RX_PORT returned 0x%02h but no I3C read data was observed",
          apb_rx_data
        )
      )
      return;
    end

    expected_byte = observed_read_data_q.pop_front();

    if (apb_rx_data !== expected_byte)
      `uvm_error(
        "I3C_SB",
        $sformatf(
          "RX data mismatch: APB=0x%02h I3C=0x%02h",
          apb_rx_data,
          expected_byte
        )
      )
    endtask
endclass



