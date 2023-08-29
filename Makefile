# Synth makefile

SRCDIR ?= $(PWD)/src
BUILDDIR ?= $(PWD)/build

PIN_DEF ?= $(SRCDIR)/pins.pcf
DEVICE ?= hx8k
PACKAGE ?= cb132
FREQ ?= 48
PLL ?= core

TOP ?= top_hx8k
V_SRC = \
	$(SRCDIR)/cmd_defs.v \
	$(SRCDIR)/pll_pad.v \
	$(SRCDIR)/pll_core.v \
	$(SRCDIR)/top_hx8k.v \
	$(SRCDIR)/top.v \
	$(SRCDIR)/nor_bus.v \
	$(SRCDIR)/qspi.v \
	$(SRCDIR)/wb_nor_controller.v \
	$(SRCDIR)/fifo.v

DESIGN_NAME ?= nisoc-bridge
OUT_BIN = $(BUILDDIR)/$(DESIGN_NAME).bin
OUT_RPT = $(BUILDDIR)/$(DESIGN_NAME).rpt
OUT_ASC = $(BUILDDIR)/$(DESIGN_NAME).asc
OUT_JSON = $(BUILDDIR)/$(DESIGN_NAME).json
OUT_SYN_V = $(BUILDDIR)/$(DESIGN_NAME)_syn.v
OUT_REPORT_JSON = $(BUILDDIR)/$(DESIGN_NAME)_report.json
OUT_PLACE_SVG = $(BUILDDIR)/$(DESIGN_NAME)_placement.svg
OUT_ROUTE_SVG = $(BUILDDIR)/$(DESIGN_NAME)_routing.svg

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
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --freq $(FREQ) --asc $(OUT_ASC) --pcf $(PIN_DEF) --json $(OUT_JSON) --report $(OUT_REPORT_JSON) $(NEXTPNR_EXPERIMENTAL) $(NEXTPNR_SEED)

$(OUT_JSON): $(V_SRC) $(BUILDDIR)
	yosys -q -e '' -p 'synth_ice40 -top $(TOP) -json $(OUT_JSON)' $(V_SRC)

$(OUT_RPT): $(OUT_ASC) $(BUILDDIR)
	icetime -d $(DEVICE) -mtr $(OUT_RPT) $(OUT_ASC)

$(OUT_SYN_V): $(OUT_JSON)
	yosys -q -p 'read_json $(OUT_JSON); write_verilog $(OUT_SYN_V)'
