FILELIST ?= filelist.f
TEST     ?= i3c_base_test
OUT      ?= out
RUN_ARGS ?=

COV_DB   := $(abspath $(OUT)/simv.vdb)
BUILD    := $(OUT)/build
SIMV     := $(BUILD)/simv
SIMV_ABS := $(abspath $(SIMV))
RUN_DIR  := $(OUT)/runs/$(TEST)
FSDB     ?= $(RUN_DIR)/i3c.fsdb

RAND_TESTS ?= \
	i3c_constrained_random_apb_test \
	i3c_constrained_random_private_test \
	i3c_constrained_random_ccc_test \
	i3c_constrained_random_management_test
RAND_SEEDS ?= 1 2 3 4 5
RAND_ITERS ?= 25

REGRESSION_TESTS ?= \
	i3c_base_test \
	i3c_apb_reg_access_test \
	i3c_ral_access_test \
	i3c_apb_strb_test \
	i3c_bus_timing_test \
	i3c_bus_timing_sweep_test \
	i3c_sdr_private_write_test \
	i3c_sdr_write_parity_error_test \
	i3c_sdr_private_write_len4_test \
	i3c_command_error_recovery_test \
	i3c_cmd_before_tx_test \
	i3c_private_nack_test \
	i3c_sdr_private_read_test \
	i3c_sdr_private_read_short_test \
	i3c_target_agent_smoke_test \
	i3c_i2c_private_write_test \
	i3c_i2c_private_write_data_nack_test \
	i3c_i2c_private_read_test \
	i3c_broadcast_ccc_test \
	i3c_broadcast_ccc_nack_test \
	i3c_broadcast_ccc_payload_test \
	i3c_direct_ccc_test \
	i3c_direct_ccc_read_len2_test \
	i3c_direct_ccc_read_short_test \
	i3c_direct_ccc_nack_test \
	i3c_direct_ccc_write_test \
	i3c_entdaa_test \
	i3c_entdaa_da_nack_test \
	i3c_entdaa_dynamic_addr_test \
	i3c_sw_reset_test \
	i3c_ibi_no_payload_test \
	i3c_ibi_payload_test \
	i3c_irq_access_test \
	i3c_polling_access_test \
	i3c_constrained_random_apb_test \
	i3c_constrained_random_private_test \
	i3c_constrained_random_ccc_test \
	i3c_constrained_random_management_test

CM_TYPES := line+cond+fsm+tgl+branch
CM       := -cm $(CM_TYPES) -cm_dir $(COV_DB)

.PHONY: all comp compile run regress random-regress cov verdi-cov verdi clean

all: comp run

# NOVAS PLI paths follow the server environment.  If LD_LIBRARY_PATH contains
# multiple colon-separated directories, pass NOVAS_TAB/NOVAS_PLI explicitly.
NOVAS_TAB ?= $(LD_LIBRARY_PATH)/novas.tab
NOVAS_PLI ?= $(LD_LIBRARY_PATH)/pli.a

comp:
	mkdir -p $(BUILD)
	vcs -full64 -sverilog -ntb_opts uvm-1.2 \
		-timescale=1ns/1ps \
		-debug_access+all -kdb \
		$(CM) \
		-P $(NOVAS_TAB) $(NOVAS_PLI) \
		-f $(FILELIST) \
		-o $(SIMV) \
		-l $(BUILD)/comp.log

# Keep the former target name so existing commands and documentation work.
compile: comp

run:
	mkdir -p $(RUN_DIR)
	cd $(RUN_DIR) && $(SIMV_ABS) +UVM_TESTNAME=$(TEST) $(RUN_ARGS) \
		$(CM) -cm_name $(TEST) -l sim.log

regress: comp
	@for test in $(REGRESSION_TESTS); do \
		echo "===== RUN $$test ====="; \
		run_dir="$(abspath $(OUT)/runs)/$$test"; \
		mkdir -p "$$run_dir"; \
		cd "$$run_dir" && $(SIMV_ABS) +UVM_TESTNAME=$$test \
			$(CM) -cm_name $$test -l sim.log || exit $$?; \
	done

random-regress: comp
	@for seed in $(RAND_SEEDS); do \
		for test in $(RAND_TESTS); do \
			echo "===== RANDOM RUN $$test SEED=$$seed ====="; \
			run_dir="$(abspath $(OUT)/runs)/$${test}_seed_$${seed}"; \
			mkdir -p "$$run_dir"; \
			cd "$$run_dir" && $(SIMV_ABS) \
				+UVM_TESTNAME=$$test +ntb_random_seed=$$seed \
				+RAND_ITERS=$(RAND_ITERS) \
				$(CM) -cm_name $${test}_seed_$${seed} -l sim.log || exit $$?; \
		done; \
	done

cov:
	mkdir -p $(OUT)/cov
	urg -dir $(COV_DB) -format both -report $(OUT)/cov/report

verdi-cov:
	verdi -cov -covdir $(COV_DB)

verdi:
	verdi -dbdir $(SIMV).daidir -ssf $(FSDB)

clean:
	rm -rf -- $(OUT)
	rm -rf -- csrc vc_hdrs.h ucli.key cm.log novas_dump.log tr_db.log *.fsdb
