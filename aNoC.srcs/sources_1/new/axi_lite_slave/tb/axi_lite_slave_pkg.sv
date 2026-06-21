`include "uvm_macros.svh"
package axi_lite_slave_pkg;
   import uvm_pkg::*;
   `include "env/axi_lite_slave_txn.sv"
   `include "env/axi_lite_slave_seq.sv"
   `include "env/axi_lite_slave_driver.sv"
   `include "env/axi_lite_slave_monitor.sv"
   `include "env/axi_lite_slave_agent.sv"
   `include "env/axi_lite_slave_scoreboard.sv"
   `include "env/axi_lite_slave_coverage.sv"
   `include "env/axi_lite_slave_env.sv"
   `include "test/axi_lite_slave_base_test.sv"
endpackage
