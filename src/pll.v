/**
 * PLL configuration
 *
 * This Verilog module was generated automatically
 * using the icepll tool from the IceStorm project.
 * Use at your own risk.
 *
 * Given input frequency:        24.000 MHz
 * Requested output frequency:   75.000 MHz
 * Achieved output frequency:    75.000 MHz
 */

module pll (
	input  clock_in,
	output clock_out,
	output locked
);

    wire g_clock_int, g_lock_int;

    //SB_PLL40_CORE #(
    SB_PLL40_PAD #(
		.FEEDBACK_PATH("SIMPLE"),
		.DIVR(4'b0000),		// DIVR =  0
		.DIVF(7'b0011000),	// DIVF = 24
		.DIVQ(3'b011),		// DIVQ =  3
		.FILTER_RANGE(3'b010)	// FILTER_RANGE = 2
	) uut (
		.LOCK(g_lock_int),
		.RESETB(1'b1),
		.BYPASS(1'b0),
		//.REFERENCECLK(clock_in),
		.PACKAGEPIN(clock_in),
        .PLLOUTGLOBAL(g_clock_int)
		//.PLLOUTCORE(clock_out)
	);

	//assign clock_out = g_clock_int;
	//assign locked = g_lock_int;
    SB_GB clk_gb (
        .USER_SIGNAL_TO_GLOBAL_BUFFER(g_clock_int),
        .GLOBAL_BUFFER_OUTPUT(clock_out)
    );

    SB_GB lck_gb (
        .USER_SIGNAL_TO_GLOBAL_BUFFER(g_lock_int),
        .GLOBAL_BUFFER_OUTPUT(locked)
    );

endmodule
