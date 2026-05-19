include $(DESIGN_DIR)/designs/$(DESIGN_NAME)/config.mk

OR_CMD  = openroad -exit
SCRIPTS = $(DESIGN_DIR)/scripts
RESULTS = $(DESIGN_DIR)/results

.PHONY: baseline qepc reports compare clean

baseline:
	mkdir -p $(RESULTS)/baseline
	cd $(ORFS_ROOT) && $(MAKE) -f flow/Makefile \
	    DESIGN_CONFIG=$(DESIGN_DIR)/designs/$(DESIGN_NAME)/config.mk \
	    RESULTS_DIR=$(RESULTS)/baseline finish

qepc:
	mkdir -p $(RESULTS)/qepc
	$(OR_CMD) $(SCRIPTS)/run_qe_flow.tcl 2>&1 | tee $(RESULTS)/qepc/run.log

reports:
	mkdir -p $(RESULTS)/comparison
	bash $(SCRIPTS)/harvest_reports.sh \
	    $(RESULTS)/baseline $(RESULTS)/qepc \
	    $(RESULTS)/comparison/qor_table.csv

compare:
	python3 $(SCRIPTS)/compare_qor.py \
	    --baseline $(RESULTS)/baseline \
	    --qepc     $(RESULTS)/qepc \
	    --out      $(RESULTS)/comparison

clean:
	rm -rf $(RESULTS)/qepc $(RESULTS)/baseline
