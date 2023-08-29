# cocotb sim makefile

# Adapted from cocotb example makefiles

SRCDIR ?= $(PWD)/../src
SIMDIR ?= $(PWD)/../sim

TOPLEVEL_LANG ?= verilog
SIM ?= icarus #verilator

ifeq ($(SIM),verilator)
EXTRA_ARGS += --trace --trace-structs
endif
COMPILE_ARGS += -I$(SRCDIR)

TEST ?= top

TOPLEVEL ?= tb_$(TEST)
MODULE ?= test_$(TEST)
SIM_BUILD ?= $(SIMDIR)/sim_build/$(TEST)
COCOTB_RESULTS_FILE ?= $(SIMDIR)/results.xml

#VERILOG_SOURCES = $(filter-out $(SRCDIR)/tb_%,$(wildcard $(SRCDIR)/*.v)) $(SRCDIR)/tb_$(TEST).v
VERILOG_SOURCES = \
	$(SRCDIR)/cmd_defs.v \
	$(SRCDIR)/top.v \
	$(SRCDIR)/qspi.v \
	$(SRCDIR)/wb_nor_controller.v \
	$(SRCDIR)/nor_bus.v \
	$(SRCDIR)/fifo.v
VERILOG_SOURCES += $(SRCDIR)/tb_$(TEST).v

include $(shell cocotb-config --makefiles)/Makefile.sim

