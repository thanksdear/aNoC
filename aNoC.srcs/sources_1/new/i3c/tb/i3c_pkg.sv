`include "uvm_macros.svh"
package i3c_pkg;
   import uvm_pkg::*;
     // APB agent
   `include "env/i3c_agent/i3c_txn.sv"
   `include "env/i3c_agent/i3c_seq.sv"
   `include "env/i3c_agent/i3c_driver.sv"
   `include "env/i3c_agent/i3c_monitor.sv"
   `include "env/i3c_agent/i3c_agent.sv"

  // I3C bus passive agent
   `include "env/i3c_bus_agent/i3c_bus_txn.sv"
   `include "env/i3c_bus_agent/i3c_bus_monitor.sv"
   `include "env/i3c_bus_agent/i3c_bus_agent.sv"
   
   // Environment components
   `include "env/i3c_target_model.sv"
   `include "env/i3c_scoreboard.sv"
   `include "env/i3c_coverage.sv"
   `include "env/i3c_env.sv"

   //Tests
   `include "test/i3c_base_test.sv"
   `include "test/i3c_feature_tests.sv"
endpackage
