# Synth makefile

# files / directories
SRCDIR ?= $(PWD)/src
PTSRCDIR ?= $(PWD)/src/qspi_passthrough
BUILDDIR ?= $(PWD)/build
PTBUILDDIR ?= $(PWD)/build/qspi_passthrough

# source
TOP ?= top_hx8k
V_SRC = \
	$(SRCDIR)/cmd_defs.vh \
	$(SRCDIR)/busmap.vh \
	$(SRCDIR)/pll.v \
	$(SRCDIR)/top_hx8k.v \
	$(SRCDIR)/top.v \
	$(SRCDIR)/nor_bus.v \
	$(SRCDIR)/xspi_phy.v \
	$(SRCDIR)/qspi_ctrl_fsm.v \
	$(SRCDIR)/fsfifo.v \
	$(SRCDIR)/sync2.v \
	$(SRCDIR)/queue2.v \
	$(SRCDIR)/upcounter.v \
	$(SRCDIR)/spi_state.vh \
	$(SRCDIR)/qspi_if.v \
	$(SRCDIR)/ctrl.v
V_SRC_PT = $(PTSRCDIR)/top_hx8k.v
export TOP   # expose to synth.tcl
export V_SRC # expose to synth.tcl

SYN_TOP ?= top
export SYN_TOP # expose to synth_gl.tcl

# nextpnr
PIN_DEF ?= $(SRCDIR)/pins.pcf
PT_PIN_DEF ?= $(PTSRCDIR)/pins.pcf
DEVICE ?= hx8k
PACKAGE ?= cb132
FREQ ?= 84

# yosys
V_DEFS ?= -DSYNTH_ICE40
export V_DEFS # expose to synth.tcl

# combined output
COMB_NAME ?= combined
COMB_OUT_BIN = $(BUILDDIR)/$(COMB_NAME).bin

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

# qspi-passthrough outputs
DESIGN_NAME_PT ?= qspi-passthrough
PT_OUT_BIN = $(PTBUILDDIR)/$(DESIGN_NAME_PT).bin
PT_OUT_RPT = $(PTBUILDDIR)/$(DESIGN_NAME_PT).rpt
PT_OUT_ASC = $(PTBUILDDIR)/$(DESIGN_NAME_PT).asc
PT_OUT_JSON = $(PTBUILDDIR)/$(DESIGN_NAME_PT).json
PT_OUT_SDF = $(PTBUILDDIR)/$(DESIGN_NAME_PT).sdf
PT_OUT_REPORT_JSON = $(PTBUILDDIR)/$(DESIGN_NAME_PT)_report.json

# seed nonsense
NEXTPNR_EXPERIMENTAL ?= --tmg-ripup #--opt-timing # 56.6 145.8
# some seeds that have worked well: 4, 1779, 2052, 33946, 94452
SEED ?= 1779
NEXTPNR_SEED ?= --seed $(SEED)

.PHONY: all
all: $(COMB_OUT_BIN) $(OUT_SYN_V)

.PHONY: clean
clean:
	-rm -r $(BUILDDIR)

.PHONY: prog
prog: $(COMB_OUT_BIN)
	iceprog $(COMB_OUT_BIN)

.PHONY: postsynth
postsynth: $(OUT_SYN_V)

.PHONY: qspi-passthrough
qspi-passthrough: $(PT_OUT_BIN)

# combined

$(COMB_OUT_BIN): $(OUT_BIN) $(PT_OUT_BIN)
	icemulti -p0 -o $(COMB_OUT_BIN) $(OUT_BIN) $(PT_OUT_PIN) -v

# main application

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(PTBUILDDIR):
	mkdir -p $(PTBUILDDIR)

$(OUT_BIN): $(OUT_RPT)
	icepack $(OUT_ASC) $(OUT_BIN)

$(OUT_ASC): $(PIN_DEF) $(OUT_JSON)
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --freq $(FREQ) --asc $(OUT_ASC) --pcf $(PIN_DEF) --json $(OUT_JSON) --report $(OUT_REPORT_JSON) --sdf $(OUT_SDF) $(NEXTPNR_EXPERIMENTAL) $(NEXTPNR_SEED)

$(OUT_JSON): $(V_SRC) | $(BUILDDIR)
	yosys -q -e '' -c synth.tcl

$(OUT_SYN_JSON): $(V_SRC) | $(BUILDDIR)
	yosys -q -e '' -c synth_gl.tcl

$(OUT_RPT): $(OUT_ASC)
	icetime -d $(DEVICE) -m -r $(OUT_RPT) $(OUT_ASC)
#icetime -d $(DEVICE) -m -c $(FREQ) -r $(OUT_RPT) $(OUT_ASC)

$(OUT_SYN_V): $(OUT_SYN_JSON)
	yosys -q -p 'read_json $(OUT_SYN_JSON); write_verilog $(OUT_SYN_V)'

# qspi-passthrough

$(PT_OUT_BIN): $(PT_OUT_RPT)
	icepack $(PT_OUT_ASC) $(PT_OUT_BIN)

$(PT_OUT_ASC): $(PT_PIN_DEF) $(PT_OUT_JSON)
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) --freq $(FREQ) --asc $(PT_OUT_ASC) --pcf $(PT_PIN_DEF) --json $(PT_OUT_JSON) --report $(PT_OUT_REPORT_JSON) --sdf $(PT_OUT_SDF) $(NEXTPNR_EXPERIMENTAL) $(NEXTPNR_SEED)

$(PT_OUT_JSON): $(V_SRC_PT) | $(PTBUILDDIR)
	yosys -q -e '' -p 'read_verilog $(V_SRC_PT); synth_ice40 -top $(TOP) -json $(PT_OUT_JSON)'

$(PT_OUT_RPT): $(PT_OUT_ASC)
	icetime -d $(DEVICE) -m -r $(PT_OUT_RPT) $(PT_OUT_ASC)
