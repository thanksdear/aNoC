`default_nettype none
`include "uvm_macros.svh"

// Pin-level assertions for the shared I3C bus model.
//
// These properties intentionally use only interface-visible signals.  They
// catch electrical/integration failures at the cycle where they occur and do
// not duplicate transaction-level payload checking in the scoreboard.
module i3c_protocol_sva (i3c_if vif);
  import uvm_pkg::*;

  logic sda_transition_seen_high;
  logic bus_active;
  logic prev_scl_in;
  logic prev_sda_in;

  wire controller_sda_low =
    vif.sda_oe && !vif.sda_out;
  wire expected_sda =
    !(controller_sda_low ||
      vif.target_drive_low ||
      vif.target_fault_drive_low);
  wire expected_scl =
    vif.scl_oe ? vif.scl_out : 1'b1;

  wire sampled_sda_transition_high =
    vif.scl_in && prev_scl_in &&
    (vif.sda_in != prev_sda_in);
  wire sampled_start =
    sampled_sda_transition_high &&
    prev_sda_in && !vif.sda_in;
  wire sampled_stop =
    sampled_sda_transition_high &&
    !prev_sda_in && vif.sda_in;

  // Track only protocol context needed by the pin-level assertions.  START
  // while active is a legal repeated START; STOP returns the bus to idle.
  always_ff @(posedge vif.clk or negedge vif.rst_n) begin
    if (!vif.rst_n) begin
      sda_transition_seen_high <= 1'b0;
      bus_active <= 1'b0;
      prev_scl_in <= 1'b1;
      prev_sda_in <= 1'b1;
    end
    else begin
      if (!vif.scl_in || sampled_stop)
        sda_transition_seen_high <= 1'b0;
      else if (sampled_sda_transition_high)
        sda_transition_seen_high <= 1'b1;

      if (sampled_start)
        bus_active <= 1'b1;
      else if (sampled_stop)
        bus_active <= 1'b0;

      prev_scl_in <= vif.scl_in;
      prev_sda_in <= vif.sda_in;
    end
  end

  property p_bus_signals_known;
    @(posedge vif.clk)
      disable iff (vif.rst_n !== 1'b1)
      !$isunknown({
        vif.scl_in, vif.scl_oe, vif.scl_out,
        vif.sda_in, vif.sda_oe, vif.sda_out,
        vif.target_drive_low, vif.target_fault_drive_low,
        vif.irq
      });
  endproperty

  property p_scl_resolver_consistent;
    @(posedge vif.clk)
      disable iff (vif.rst_n !== 1'b1)
      vif.scl_in === expected_scl;
  endproperty

  property p_sda_resolver_consistent;
    @(posedge vif.clk)
      disable iff (vif.rst_n !== 1'b1)
      vif.sda_in === expected_sda;
  endproperty

  // A legal target response is open-drain.  Pulling low while the controller
  // actively drives push-pull high is contention, except through the explicit
  // fault-injection contribution checked separately below.
  property p_no_target_push_pull_contention;
    @(posedge vif.clk)
      disable iff (vif.rst_n !== 1'b1)
      !(vif.sda_oe && vif.sda_out && vif.target_drive_low);
  endproperty

  // The current parity injector is wired-low, so it is useful only when the
  // controller is intentionally driving the correct T-bit high.  It must
  // never overlap a legal target ACK contribution.
  property p_parity_fault_drive_is_legal;
    @(posedge vif.clk)
      disable iff (vif.rst_n !== 1'b1)
      vif.target_fault_drive_low |->
        (vif.sda_oe && vif.sda_out &&
         !vif.target_drive_low && !vif.target_dbg_ack_phase);
  endproperty

  // Between an SCL-low phase (or a completed STOP) and the next boundary,
  // there may be at most one SDA transition while SCL stays high.  STOP resets
  // the guard because a later START is legal while the bus remains high.
  property p_at_most_one_sda_transition_per_scl_high;
    @(posedge vif.clk)
      disable iff (vif.rst_n !== 1'b1)
      sampled_sda_transition_high |-> !sda_transition_seen_high;
  endproperty

  property p_stop_only_when_bus_active;
    @(posedge vif.clk)
      disable iff (vif.rst_n !== 1'b1)
      sampled_stop |-> bus_active;
  endproperty

  property p_bus_released_after_reset;
    @(posedge vif.clk)
      $rose(vif.rst_n) |->
        (vif.scl_in && vif.sda_in &&
         !vif.target_drive_low && !vif.target_fault_drive_low);
  endproperty

  a_bus_signals_known:
    assert property (p_bus_signals_known)
    else `uvm_error("I3C_SVA", "SCL/SDA/IRQ contains X or Z after reset")

  a_scl_resolver_consistent:
    assert property (p_scl_resolver_consistent)
    else `uvm_error("I3C_SVA", "resolved SCL does not match its drive contribution")

  a_sda_resolver_consistent:
    assert property (p_sda_resolver_consistent)
    else `uvm_error("I3C_SVA", "resolved SDA does not match wired-low contributors")

  a_no_target_push_pull_contention:
    assert property (p_no_target_push_pull_contention)
    else `uvm_error("I3C_SVA", "target pulled SDA low while controller drove push-pull high")

  a_parity_fault_drive_is_legal:
    assert property (p_parity_fault_drive_is_legal)
    else `uvm_error("I3C_SVA", "parity fault injector was enabled outside a controller-high T-bit")

  a_at_most_one_sda_transition_per_scl_high:
    assert property (p_at_most_one_sda_transition_per_scl_high)
    else `uvm_error("I3C_SVA", "SDA changed more than once during one SCL-high interval")

  a_stop_only_when_bus_active:
    assert property (p_stop_only_when_bus_active)
    else `uvm_error("I3C_SVA", "STOP was observed while the bus model was idle")

  a_bus_released_after_reset:
    assert property (p_bus_released_after_reset)
    else `uvm_error("I3C_SVA", "SCL/SDA was not released when reset was deasserted")

  c_start:
    cover property (
      @(posedge vif.clk)
        disable iff (vif.rst_n !== 1'b1)
        sampled_start && !bus_active
    );

  c_repeated_start:
    cover property (
      @(posedge vif.clk)
        disable iff (vif.rst_n !== 1'b1)
        sampled_start && bus_active
    );

  c_stop:
    cover property (
      @(posedge vif.clk)
        disable iff (vif.rst_n !== 1'b1)
        sampled_stop
    );

  c_parity_fault:
    cover property (
      @(posedge vif.clk)
        disable iff (vif.rst_n !== 1'b1)
        vif.target_fault_drive_low
    );

endmodule

`default_nettype wire
