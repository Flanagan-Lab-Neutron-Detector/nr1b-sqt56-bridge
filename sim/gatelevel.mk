# cocotb sim makefile

# Adapted from cocotb example makefiles

SRCDIR ?= $(PWD)/../src
SIMDIR ?= $(PWD)/../sim
TB_DIR ?= $(PWD)/tb
BUILDDIR ?= $(PWD)/../build

TOPLEVEL_LANG ?= verilog
SIM ?= icarus

ifeq ($(SIM),verilator)
EXTRA_ARGS += --trace --trace-structs
else ifeq ($(SIM),icarus)
COMPILE_ARGS += -gspecify
endif
COMPILE_ARGS += -D SIM=1 -I$(SRCDIR)
#COMPILE_ARGS += -DSDF_FILENAME="\"../build/nisoc-bridge.sdf\""

TEST ?= top

TOPLEVEL ?= tb_$(TEST)_gl
MODULE ?= test_$(TEST)
SIM_BUILD ?= $(SIMDIR)/sim_build/$(TEST)_gl
COCOTB_RESULTS_FILE ?= $(SIMDIR)/results.xml

#VERILOG_SOURCES = $(filter-out $(SRCDIR)/tb_%,$(wildcard $(SRCDIR)/*.v)) $(SRCDIR)/tb_$(TEST).v
VERILOG_SOURCES = $(BUILDDIR)/nisoc-bridge_syn.v $(shell yosys-config --datdir/ice40/cells_sim.v)
VERILOG_SOURCES += $(TB_DIR)/tb_$(TEST)_gl.v

include $(shell cocotb-config --makefiles)/Makefile.sim

