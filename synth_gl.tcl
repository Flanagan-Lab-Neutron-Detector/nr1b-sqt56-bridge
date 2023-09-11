# yosys -import
yosys read_verilog $::env(V_DEFS) {*}$::env(V_SRC)
yosys synth_ice40 -top $::env(SYN_TOP) -json $::env(OUT_SYN_JSON)
