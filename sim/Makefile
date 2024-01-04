# cocotb sim makefile

# Adapted from cocotb example makefiles

SRCDIR ?= $(PWD)/../src
SIMDIR ?= $(PWD)/../sim
TB_DIR ?= $(PWD)/tb

TOPLEVEL_LANG ?= verilog
SIM ?= icarus #verilator

ifeq ($(SIM),verilator)
EXTRA_ARGS += --trace --trace-structs
endif
COMPILE_ARGS += -D SIM=1 -I$(SRCDIR)

TEST ?= top

TOPLEVEL ?= tb_$(TEST)
MODULE ?= test_$(TEST)
SIM_BUILD ?= $(SIMDIR)/sim_build/$(TEST)
COCOTB_RESULTS_FILE ?= $(SIMDIR)/results.xml

#VERILOG_SOURCES = $(filter-out $(SRCDIR)/tb_%,$(wildcard $(SRCDIR)/*.v)) $(SRCDIR)/tb_$(TEST).v
VERILOG_SOURCES = \
	$(SRCDIR)/cmd_defs.vh \
	$(SRCDIR)/busmap.vh \
	$(SRCDIR)/top.v \
	$(SRCDIR)/qspi_ctrl_fsm.v \
	$(SRCDIR)/xspi_phy.v \
	$(SRCDIR)/nor_bus.v \
	$(SRCDIR)/fsfifo.v \
	$(SRCDIR)/sync2.v \
	$(SRCDIR)/queue2.v
VERILOG_SOURCES += $(TB_DIR)/tb_$(TEST).v

include $(shell cocotb-config --makefiles)/Makefile.sim

