# Synth makefile

# files / directories
SRCDIR ?= $(PWD)/src
BUILDDIR ?= $(PWD)/build

# source
TOP ?= top_hx8k
V_SRC = \
	$(SRCDIR)/cmd_defs.vh \
	$(SRCDIR)/pll.v \
	$(SRCDIR)/top_hx8k.v \
	$(SRCDIR)/top.v \
	$(SRCDIR)/nor_bus.v \
	$(SRCDIR)/xspi_phy.v \
	$(SRCDIR)/qspi.v \
	$(SRCDIR)/wb_nor_controller.v \
	$(SRCDIR)/fifo.v \
	$(SRCDIR)/sync2.v
export TOP   # expose to synth.tcl
export V_SRC # expose to synth.tcl

SYN_TOP ?= top
export SYN_TOP # expose to synth_gl.tcl

# nextpnr
PIN_DEF ?= $(SRCDIR)/pins.pcf
DEVICE ?= hx8k
PACKAGE ?= cb132
FREQ ?= 66

# yosys
V_DEFS ?= -DSYNTH_ICE40
export V_DEFS # expose to synth.tcl

# outputs (yosys and nextpnr)
DESIGN_NAME ?= nisoc-bridge
OUT_BIN = $(BUILDDIR)/$(DESIGN_NAME).bin
OUT_RPT = $(BUILDDIR)/$(DESIGN_NAME).rpt
OUT_ASC = $(BUILDDIR)/$(DESIGN_NAME).asc
OUT_JSON = $(BUILDDIR)/$(DESIGN_NAME).json
OUT_SDF = $(BUILDDIR)/$(DESIGN_NAME).sdf
OUT_SYN_JSON = $(BUILDDIR)/$(DESIGN_NAME)_syn.json
OUT_SYN_V = $(BUILDDIR)/$(DESIGN_NAME)_syn.v
OUT_REPORT_JSON = $(BUILDDIR)/$(DESIGN_NAME)_report.json
OUT_PLACE_SVG = $(BUILDDIR)/$(DESIGN_NAME)_placement.svg
OUT_ROUTE_SVG = $(BUILDDIR)/$(DESIGN_NAME)_routing.svg
export OUT_JSON # expose to synth.tcl
export OUT_SYN_JSON # expose to synth_gl.tcl

# seed nonsense
NEXTPNR_EXPERIMENTAL ?= --tmg-ripup #--opt-timing # 56.6 145.8
# some seeds that have worked well: 4, 1779, 2052, 33946, 94452
SEED ?= 1779
NEXTPNR_SEED ?= --seed $(SEED)

.PHONY: all clean prog postsynth
all: $(OUT_RPT) $(OUT_BIN) $(OUT_SYN_V)

clean:
	-rm -r $(BUILDDIR)

prog: $(OUT_BIN)
	iceprog $(OUT_BIN)

postsynth: $(OUT_SYN_V)

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(OUT_BIN): $(OUT_ASC) $(BUILDDIR)
	icepack $(OUT_ASC) $(OUT_BIN)

$(OUT_ASC): $(PIN_DEF) $(OUT_JSON) $(BUILDDIR)
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --freq $(FREQ) --asc $(OUT_ASC) --pcf $(PIN_DEF) --json $(OUT_JSON) --report $(OUT_REPORT_JSON) --sdf $(OUT_SDF) $(NEXTPNR_EXPERIMENTAL) $(NEXTPNR_SEED)

$(OUT_JSON): $(V_SRC) $(BUILDDIR)
	yosys -q -e '' -c synth.tcl

$(OUT_SYN_JSON): $(V_SRC) $(BUILDDIR)
	yosys -q -e '' -c synth_gl.tcl

$(OUT_RPT): $(OUT_ASC) $(BUILDDIR)
	icetime -d $(DEVICE) -m -c $(FREQ) -r $(OUT_RPT) $(OUT_ASC)

$(OUT_SYN_V): $(OUT_SYN_JSON)
	yosys -q -p 'read_json $(OUT_SYN_JSON); write_verilog $(OUT_SYN_V)'
