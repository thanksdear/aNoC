UVM_HOME ?= ../../../uvm-1.2
FILELIST ?= filelist.f
IMAGE    ?= image
TOP      ?= top
TEST     ?= i3c_base_test
COV_DB   ?= verisim.zdb
LOG_DIR  ?= log
REGRESSION_TESTS ?= \
	i3c_base_test \
	i3c_apb_reg_access_test \
	i3c_apb_strb_test \
	i3c_bus_timing_test \
	i3c_bus_timing_sweep_test \
	i3c_sdr_private_write_test \
	i3c_sdr_private_write_len4_test \
	i3c_cmd_before_tx_test \
	i3c_private_nack_test \
	i3c_sdr_private_read_test \
	i3c_sdr_private_read_short_test \
	i3c_i2c_private_write_test \
	i3c_i2c_private_write_data_nack_test \
	i3c_i2c_private_read_test \
	i3c_broadcast_ccc_test \
	i3c_direct_ccc_test \
	i3c_direct_ccc_write_test \
	i3c_entdaa_test \
	i3c_sw_reset_test \
	i3c_ibi_no_payload_test \
	i3c_ibi_payload_test \
	i3c_irq_access_test \
	i3c_polling_access_test

UVM_PKG := $(UVM_HOME)/src/uvm_pkg.sv
UVM_DPI := $(UVM_HOME)/src/dpi/libuvm_dpi.so

VERISIM_FLAGS := -j 8 -linebuf -all-class-spec +acc+b -code-cov all +incdir+$(UVM_HOME)/src
RUN_FLAGS     ?= -write-sql
VERICOV_FLAGS := -report -text -out $(LOG_DIR)/cov.txt $(COV_DB)

.PHONY: all compile run regress cov clean

all: compile run

compile:
	mkdir -p $(LOG_DIR)
	rm -rf $(IMAGE) $(COV_DB)
	verisim -genimage $(IMAGE) $(VERISIM_FLAGS) $(UVM_PKG) -f $(FILELIST) -l $(LOG_DIR)/compile.log

run:
	mkdir -p $(LOG_DIR)
	verisim -image $(IMAGE) -sv_lib $(UVM_DPI) $(RUN_FLAGS) +UVM_TESTNAME=$(TEST) -l $(LOG_DIR)/$(TEST).log

regress: compile
	@mkdir -p $(LOG_DIR)
	@for test in $(REGRESSION_TESTS); do \
		echo "===== RUN $$test ====="; \
		verisim -image $(IMAGE) -sv_lib $(UVM_DPI) $(RUN_FLAGS) +UVM_TESTNAME=$$test -l $(LOG_DIR)/$$test.log || exit $$?; \
	done

cov:
	mkdir -p $(LOG_DIR)
	rm -rf vericov_work
	test -s $(COV_DB)
	vericov $(VERICOV_FLAGS) -l $(LOG_DIR)/cov.log
	vericov -report -lcov -out log/lcov verisim.zdb -l log/lcov.log
clean:
	rm -rf verisim* $(IMAGE) $(LOG_DIR)
