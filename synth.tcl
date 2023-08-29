# yosys -import
yosys read_verilog $::env(V_DEFS) {*}$::env(V_SRC)
yosys synth_ice40 -top $::env(TOP) -json $::env(OUT_JSON)
