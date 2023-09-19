/** wb_nor_controller.v
 *
 * NOR control and sequencing logic. Wishbone master and slave.
 *
 */

`default_nettype none
`timescale 1ns/100ps

`include "cmd_defs.vh"

// TODO: ROM -> FSM
// The ROM-based implementation below is inefficient and inflexible.
// Instead, use many states that are specific to commands.

module wb_nor_controller #(
    parameter CMDBITS  = 6,
    parameter ADDRBITS = 26,
    parameter DATABITS = 16
) (
    // wishbone global
    input                     wb_rst_i,
    input                     wb_clk_i,

    // wishbone slave
    input      [ADDRBITS+CMDBITS-1:0] wbs_adr_i,
    input      [DATABITS-1:0] wbs_dat_i,
    input                     wbs_we_i,
    input                     wbs_stb_i,
    input                     wbs_cyc_i,
    output                    wbs_err_o,
    output reg                wbs_ack_o,
    output reg [DATABITS-1:0] wbs_dat_o,
    output                    wbs_stall_o,

    // wishbone master
    output     [ADDRBITS-1:0] wbm_adr_o,
    output     [DATABITS-1:0] wbm_dat_o,
    output reg                wbm_we_o,
    output reg                wbm_stb_o,
    output reg                wbm_cyc_o,
    input                     wbm_err_i,
    input                     wbm_ack_i,
    input      [DATABITS-1:0] wbm_dat_i,
    input                     wbm_stall_i
);

    localparam [1:0] NOR_CMD_IDLE    = 2'b00,
                     NOR_CMD_CYCLE_0 = 2'b01,
                     NOR_CMD_CYCLE_1 = 2'b10;

    reg  [1:0] state;
    reg  [2:0] cycle;
    wire [2:0] cycle_next;
    reg  [ADDRBITS+CMDBITS-1:0] cmd_latch;
    reg  [DATABITS-1:0] data_latch;
    wire [ADDRBITS-1:0] cmd_addr;
    wire  [CMDBITS-1:0] cmd_cmd;
    assign cycle_next = cycle + 3'b1;

    // decode command vs. address bits
    assign { cmd_cmd, cmd_addr } = { cmd_latch[ADDRBITS+CMDBITS-1:ADDRBITS], cmd_latch[ADDRBITS-1:0] };

    // command rom signals
    wire          [2:0] cycle_cnt;
    wire          [7:0] cycle_addr_sel; // 0 = use rom value, 1 = use supplied
    wire          [7:0] cycle_data_sel; // 0 = use rom value, 1 = use supplied
    wire [ADDRBITS-1:0] cycle_addr;
    wire [DATABITS-1:0] cycle_data;
    wire                cycle_err;      // 1 = invalid cycle
    assign cycle_addr[ADDRBITS-1:12] = '0;

    nor_cmd_rom cmd_rom (
        .cmd_i(cmd_cmd), .cycle_i(cycle), .cycle_err_o(cycle_err),
        .cycle_addr_o(cycle_addr[11:0]), .cycle_data_o(cycle_data),
        .cycle_addr_sel_o(cycle_addr_sel),
        .cycle_data_sel_o(cycle_data_sel),
        .cycle_cnt_o(cycle_cnt)
    );

    assign wbm_adr_o = cycle_addr_sel[cycle] ? cmd_addr   : cycle_addr;
    assign wbm_dat_o = cycle_data_sel[cycle] ? data_latch : cycle_data;

    reg busy;
    assign wbs_stall_o = busy;

    wire mod_reset;
    assign mod_reset = wb_rst_i || !wbs_cyc_i || wbs_err_o;

    assign wbs_err_o = wbm_err_i || cycle_err;

    always @(posedge wb_clk_i) begin
        if (mod_reset) begin
            busy       <= 1'b0;
            wbs_ack_o  <= 1'b0;
            state      <= NOR_CMD_IDLE;
            cycle      <= 3'b0;
            cmd_latch  <=  'b0;
            data_latch <=  'b0;
            wbm_cyc_o  <= 1'b0;
            wbm_stb_o  <= 1'b0;
        end else if (wbs_stb_i && !wbs_stall_o) begin
            // latch inputs
            cmd_latch  <= wbs_adr_i;
            data_latch <= wbs_dat_i;
            // decode cmd to load cycle info
            // kick off state machine
            busy       <= 1'b1;
            wbs_ack_o  <= 1'b0;
            cycle      <= 3'b0;
            state      <= NOR_CMD_CYCLE_0;
        end else case (state)
            NOR_CMD_CYCLE_0: begin
                if (!wbm_stall_i) begin
                    wbm_cyc_o <= 1'b1;
                    wbm_stb_o <= 1'b1;
                    // wbm_adr_o and wbm_dat_o set above
                    if (cmd_cmd == 6'b0) // cmd == 0 => read
                        wbm_we_o <= 1'b0;
                    else
                        wbm_we_o <= 1'b1;
                    state     <= NOR_CMD_CYCLE_1;
                end
            end
            NOR_CMD_CYCLE_1: begin
                wbm_stb_o <= 1'b0;
                wbm_we_o  <= 1'b0;
                if (wbm_ack_i) begin
                    wbm_cyc_o <= 1'b0;
                    if (cmd_cmd == 6'b0)
                        wbs_dat_o <= wbm_dat_i;
                    if (cycle_next == cycle_cnt) begin
                        wbs_ack_o <= 1'b1;
                        cycle     <= 3'b0;
                        state     <= NOR_CMD_IDLE;
                    end else begin
                        cycle     <= cycle_next;
                        state     <= NOR_CMD_CYCLE_0;
                    end
                end
            end
            default: begin
                busy      <= 1'b0;
                cycle     <= 3'b0;
                wbs_ack_o <= 1'b0;
                state     <= NOR_CMD_IDLE;
            end
        endcase
    end

    // Formal verification
`ifdef FORMAL

    // past valid and reset
    reg f_past_valid;
    initial f_past_valid <= 1'b0;
    always @(posedge wb_clk_i)
        f_past_valid <= 1'b1;
    always @(*)
        if (!f_past_valid) assert(wb_rst_i);

    // collected reset conditions

    initial assume(wb_rst_i);
    //initial assume(!wbs_err_i);
    // the master is correct
    initial assume(!wbs_cyc_i);
    initial assume(!wbs_stb_i);
    // and we reset correctly
    //initial assert(!wbs_ack_o);
    //initial assert(!wbs_err_i);

    always @(posedge wb_clk_i) begin
        if (!f_past_valid || $past(wb_rst_i)) begin
            // reset condition
            //assume(!wbs_err_i);
            assume(!wbs_cyc_i);
            assume(!wbs_stb_i);
            assume(!wbs_ack_o);
        end
	end

    always @(*)
        if (!f_past_valid) assert(!wbs_cyc_i);

    // Requests

    // after a bus error master shold deassert cyc
    always @(posedge wb_clk_i)
        if (f_past_valid && $past(wbs_err_o) && $past(wbs_cyc_i))
            assume(!wbs_cyc_i);

    // stb should only be asserted if cyc
    always @(*) if (wbs_stb_i) assume(wbs_cyc_i);

    // if there is a request on the bus and the bus is stalled, the request remains
    always @(posedge wb_clk_i) begin
        if (f_past_valid && !$past(wb_rst_i) && $past(wbs_stb_i) && $past(wbs_stall_o) && wbs_cyc_i) begin
            assume(wbs_stb_i);
            assume(wbs_we_i  == $past(wbs_we_i));
            assume(wbs_adr_i == $past(wbs_adr_i));
            //assume(wb_sel_i  == $past(wb_sel_i));
            if (wbs_we_i)
                assume(wbs_dat_i == $past(wbs_dat_i));
        end
    end

    // within a strobe the direction does not change
	always @(posedge wb_clk_i)
        if (f_past_valid && $past(wbs_stb_i) && wbs_stb_i)
            assume(wbs_we_i == $past(wbs_we_i));

    // Responses

    // if cyc was low, then ack and err should be low
	always @(posedge wb_clk_i) begin
        if (f_past_valid && !$past(wbs_cyc_i) && !wbs_cyc_i) begin
            assert(!wbs_ack_o);
            //assert(!wbs_err_i);
        end
    end

    // should not assert both ack and err
    always @(posedge wb_clk_i) begin
        if (f_past_valid && $past(wbs_err_o)) assert(!wbs_ack_o);
    end

    // if cyc and stb, and ack was high, then we shold not start anything
    /*
    always @(posedge wb_clk_i) begin
        if (f_past_valid && wbs_cyc_i && wbs_stb_i && $past(wbs_ack_o))
            assert(!wbs_stall_o);
    end
    */

    // wb master formal properties

    // reset conditions
    // initial reset assumption in slave properties
    initial assume(!wbm_cyc_o);
    initial assume(!wbm_stb_o);
    initial assume(!wbm_err_i);
    initial assume(!wbm_ack_i);

    // we start transactions
    always @(posedge wb_clk_i) begin
	    if (f_past_valid && !mod_reset && $past(wbs_stb_i) && !$past(wbs_stall_o)) begin
            assert(state == NOR_CMD_CYCLE_0);
		    assume(!wbm_ack_i);
        end
	    if (f_past_valid && !mod_reset && $past(wbs_stb_i) && $past(state) == NOR_CMD_CYCLE_0 && !$past(wbm_stall_i)) begin
		    assert(wbm_cyc_o);
		    assert(wbm_stb_o);
		    assume(!wbm_ack_i);
	    end
    end

    // requests

    // following a downstream error we shold abort
    always @(posedge wb_clk_i) begin
        if (f_past_valid && $past(wbm_err_i) && $past(wbm_cyc_o))
            assert(!wbm_cyc_o);
    end

    // only assert stb if cyc
    always @(*) if (wbm_stb_o) assert(wbm_cyc_o);

    // if there is a request on the bus and the bus is stalled, the request remains
    always @(posedge wb_clk_i) begin
        if (f_past_valid && !$past(mod_reset) && $past(wbm_stb_o) && $past(wbm_stall_i) && wbm_cyc_o) begin
            assert(wbm_stb_o);
            assert(wbm_we_o  == $past(wbm_we_o));
            assume(wbm_adr_o == $past(wbm_adr_o));
            if (wbm_we_o)
                assume(wbm_dat_o == $past(wbm_dat_o));
        end
    end

    // within a strobe the direction does not change
	always @(posedge wb_clk_i)
        if (f_past_valid && $past(wbm_stb_o) && wbm_stb_o)
            assume(wbm_we_o == $past(wbm_we_o));

    // Responses (slave guarantees)

    always @(posedge wb_clk_i) begin
        if (f_past_valid && $past(wbm_cyc_o) && !wbm_cyc_o) begin
            assume(!wbm_ack_i);
        end
    end

    always @(*) assume (!wbm_ack_i || !wbs_err_o);

    // state machine formal properties

    always @(posedge wb_clk_i) begin
        // if (state == NOR_CMD_IDLE)
        //     assert(!busy);
        // else
        //     assert(busy);

        // we always advance
        assert(mod_reset || cycle < cycle_cnt);
        if (f_past_valid)
            assert($past(mod_reset) || mod_reset || state == NOR_CMD_IDLE || cycle >= $past(cycle));
    end

    always @(posedge wb_clk_i) begin
        cover(state == NOR_CMD_IDLE);
        cover(state == NOR_CMD_CYCLE_0);
        cover(state == NOR_CMD_CYCLE_1);
        cover(f_past_valid && !(mod_reset || $past(mod_reset)) && state == NOR_CMD_CYCLE_0 && cmd_cmd == 6'h00);
        cover(f_past_valid && !(mod_reset || $past(mod_reset)) && state == NOR_CMD_CYCLE_0 && cmd_cmd == 6'h01);
        cover(f_past_valid && !(mod_reset || $past(mod_reset)) && state == NOR_CMD_CYCLE_0 && cmd_cmd == 6'h02);
        cover(f_past_valid && !(mod_reset || $past(mod_reset)) && state == NOR_CMD_CYCLE_0 && cmd_cmd == 6'h03);
        cover(f_past_valid && !(mod_reset || $past(mod_reset)) && state == NOR_CMD_CYCLE_0 && cmd_cmd == 6'h04);
        cover(f_past_valid && !(mod_reset || $past(mod_reset)) && state == NOR_CMD_CYCLE_0 && cmd_cmd == 6'h05);
        cover(f_past_valid && !(mod_reset || $past(mod_reset)) && state == NOR_CMD_CYCLE_0 && cmd_cmd == 6'h06);
        cover(f_past_valid && !(mod_reset || $past(mod_reset)) && state == NOR_CMD_CYCLE_0 && cmd_cmd == 6'h07);
        cover(f_past_valid && !(mod_reset || $past(mod_reset)) && state == NOR_CMD_CYCLE_0 && cmd_cmd == 6'h08);
        cover(f_past_valid && state == NOR_CMD_IDLE && $past(state == NOR_CMD_CYCLE_1) && !(mod_reset || $past(mod_reset)));
    end

`endif // FORMAL

endmodule

module nor_cmd_rom (
    input   [5:0] cmd_i,
    input   [2:0] cycle_i,
    output            cycle_err_o,
    output reg [11:0] cycle_addr_o,
    output reg [15:0] cycle_data_o,
    output reg  [2:0] cycle_cnt_o,
    output reg  [7:0] cycle_addr_sel_o, // 0 = use rom value, 1 = use supplied
    output reg  [7:0] cycle_data_sel_o  // 0 = use rom value, 1 = use supplied
);

    assign cycle_err_o = cmd_i > `NOR_CYCLE_MAX_;

    // cycle count
    always @(*)
        case (cmd_i)
            `NOR_CYCLE_READ:         cycle_cnt_o = 3'd1;
            `NOR_CYCLE_CFI_ENTER:    cycle_cnt_o = 3'd1;
            `NOR_CYCLE_PROGRAM:      cycle_cnt_o = 3'd4;
            `NOR_CYCLE_ERASE_SECTOR: cycle_cnt_o = 3'd6;
            `NOR_CYCLE_ERASE_CHIP:   cycle_cnt_o = 3'd6;
            `NOR_CYCLE_RESET:        cycle_cnt_o = 3'd1;
            `NOR_CYCLE_WRITE_BUF:    cycle_cnt_o = 3'd4;
            `NOR_CYCLE_PROG_BUF:     cycle_cnt_o = 3'd1;
            `NOR_CYCLE_WRITE:        cycle_cnt_o = 3'd1;
            default:                 cycle_cnt_o = 3'd1; // default = reset
        endcase

    // addr, data select
    always @(*)
        case (cmd_i)
            `NOR_CYCLE_READ:         { cycle_addr_sel_o, cycle_data_sel_o } = { 8'h01, 8'h01 };
            `NOR_CYCLE_CFI_ENTER:    { cycle_addr_sel_o, cycle_data_sel_o } = { 8'h00, 8'h00 };
            `NOR_CYCLE_PROGRAM:      { cycle_addr_sel_o, cycle_data_sel_o } = { 8'h08, 8'h08 };
            `NOR_CYCLE_ERASE_SECTOR: { cycle_addr_sel_o, cycle_data_sel_o } = { 8'h20, 8'h00 };
            `NOR_CYCLE_ERASE_CHIP:   { cycle_addr_sel_o, cycle_data_sel_o } = { 8'h00, 8'h00 };
            `NOR_CYCLE_RESET:        { cycle_addr_sel_o, cycle_data_sel_o } = { 8'h00, 8'h00 };
            `NOR_CYCLE_WRITE_BUF:    { cycle_addr_sel_o, cycle_data_sel_o } = { 8'h0C, 8'h0C };
            `NOR_CYCLE_PROG_BUF:     { cycle_addr_sel_o, cycle_data_sel_o } = { 8'h01, 8'h00 };
            `NOR_CYCLE_WRITE:        { cycle_addr_sel_o, cycle_data_sel_o } = { 8'h01, 8'h01 };
            default:                 { cycle_addr_sel_o, cycle_data_sel_o } = { 8'h00, 8'h00 };
        endcase

    always @(*) begin
        cycle_addr_o = cycle_addr_mem[cmd_i][cycle_i];
        cycle_data_o = cycle_data_mem[cmd_i][cycle_i];
    end

    reg [11:0] cycle_addr_mem[64][6];
    reg [15:0] cycle_data_mem[64][6];

    integer i, j;
    initial begin
        /*
        cycle_addr_mem[`NOR_CYCLE_READ]         = {  12'h000,  12'h000,  12'h000,  12'h000,  12'h000,  12'h000 };
        cycle_data_mem[`NOR_CYCLE_READ]         = { 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000 };

        cycle_addr_mem[`NOR_CYCLE_CFI_ENTER]    = {  12'h055,  12'h000,  12'h000,  12'h000,  12'h000,  12'h000 };
        cycle_data_mem[`NOR_CYCLE_CFI_ENTER]    = { 16'h0098, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000 };

        cycle_addr_mem[`NOR_CYCLE_PROGRAM]      = {  12'h555,  12'h2AA,  12'h555,  12'h000,  12'h000,  12'h000 };
        cycle_data_mem[`NOR_CYCLE_PROGRAM]      = { 16'h00AA, 16'h0055, 16'h00A0, 16'h0000, 16'h0000, 16'h0000 };

        cycle_addr_mem[`NOR_CYCLE_ERASE_SECTOR] = {  12'h555,  12'h2AA,  12'h555,  12'h555,  12'h2AA,  12'h000 };
        cycle_data_mem[`NOR_CYCLE_ERASE_SECTOR] = { 16'h00AA, 16'h0055, 16'h0080, 16'h00AA, 16'h0055, 16'h0030 };

        cycle_addr_mem[`NOR_CYCLE_ERASE_CHIP]   = {  12'h555,  12'h2AA,  12'h555,  12'h555,  12'h2AA,  12'h555 };
        cycle_data_mem[`NOR_CYCLE_ERASE_CHIP]   = { 16'h00AA, 16'h0055, 16'h0080, 16'h00AA, 16'h0055, 16'h0010 };

        cycle_addr_mem[`NOR_CYCLE_RESET]        = {  12'h000,  12'h000,  12'h000,  12'h000,  12'h000,  12'h000 };
        cycle_data_mem[`NOR_CYCLE_RESET]        = { 16'h00F0, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000 };

        cycle_addr_mem[`NOR_CYCLE_WRITE_BUF]    = {  12'h555,  12'h2AA,  12'h000,  12'h000,  12'h000,  12'h000 };
        cycle_data_mem[`NOR_CYCLE_WRITE_BUF]    = { 16'h00AA, 16'h0055, 16'h0025, 16'h0000, 16'h0000, 16'h0000 };

        cycle_addr_mem[`NOR_CYCLE_PROG_BUF]     = {  12'h000,  12'h000,  12'h000,  12'h000,  12'h000,  12'h000 };
        cycle_data_mem[`NOR_CYCLE_PROG_BUF]     = { 16'h0029, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000 };

        cycle_addr_mem[`NOR_CYCLE_WRITE]        = {  12'h000,  12'h000,  12'h000,  12'h000,  12'h000,  12'h000 };
        cycle_data_mem[`NOR_CYCLE_WRITE]        = { 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000 };

        for (i = 9; i < 64; i = i + 1) begin
            cycle_addr_mem[i] = { 12'h000, 12'h000, 12'h000, 12'h000, 12'h000, 12'h000 };
            cycle_data_mem[i] = { 16'h00F0, 16'h0000, 16'h0000, 16'h0000, 16'h0000, 16'h0000 };
        end
        */

        for (i = 0; i < 64; i = i + 1) begin
            for (j = 0; j < 6; j = j + 1) begin
                cycle_addr_mem[i][j] = 12'h000;
                cycle_data_mem[i][j] = 16'h0000;
            end
            cycle_data_mem[i][0] = 16'h00F0;
        end

        cycle_addr_mem[`NOR_CYCLE_CFI_ENTER][0]    =  12'h055; cycle_data_mem[`NOR_CYCLE_CFI_ENTER][0]    = 16'h0098;

        cycle_addr_mem[`NOR_CYCLE_PROGRAM][0]      =  12'h555; cycle_data_mem[`NOR_CYCLE_PROGRAM][0]      = 16'h00AA;
        cycle_addr_mem[`NOR_CYCLE_PROGRAM][1]      =  12'h2AA; cycle_data_mem[`NOR_CYCLE_PROGRAM][1]      = 16'h0055;
        cycle_addr_mem[`NOR_CYCLE_PROGRAM][2]      =  12'h555; cycle_data_mem[`NOR_CYCLE_PROGRAM][2]      = 16'h00A0;

        cycle_addr_mem[`NOR_CYCLE_ERASE_SECTOR][0] =  12'h555; cycle_data_mem[`NOR_CYCLE_ERASE_SECTOR][0] = 16'h00AA;
        cycle_addr_mem[`NOR_CYCLE_ERASE_SECTOR][1] =  12'h2AA; cycle_data_mem[`NOR_CYCLE_ERASE_SECTOR][1] = 16'h0055;
        cycle_addr_mem[`NOR_CYCLE_ERASE_SECTOR][2] =  12'h555; cycle_data_mem[`NOR_CYCLE_ERASE_SECTOR][2] = 16'h0080;
        cycle_addr_mem[`NOR_CYCLE_ERASE_SECTOR][3] =  12'h555; cycle_data_mem[`NOR_CYCLE_ERASE_SECTOR][3] = 16'h00AA;
        cycle_addr_mem[`NOR_CYCLE_ERASE_SECTOR][4] =  12'h2AA; cycle_data_mem[`NOR_CYCLE_ERASE_SECTOR][4] = 16'h0055;
        cycle_addr_mem[`NOR_CYCLE_ERASE_SECTOR][5] =  12'h000; cycle_data_mem[`NOR_CYCLE_ERASE_SECTOR][5] = 16'h0030;

        cycle_addr_mem[`NOR_CYCLE_ERASE_CHIP][0]   =  12'h555; cycle_data_mem[`NOR_CYCLE_ERASE_CHIP][0]   = 16'h00AA;
        cycle_addr_mem[`NOR_CYCLE_ERASE_CHIP][1]   =  12'h2AA; cycle_data_mem[`NOR_CYCLE_ERASE_CHIP][1]   = 16'h0055;
        cycle_addr_mem[`NOR_CYCLE_ERASE_CHIP][2]   =  12'h555; cycle_data_mem[`NOR_CYCLE_ERASE_CHIP][2]   = 16'h0080;
        cycle_addr_mem[`NOR_CYCLE_ERASE_CHIP][3]   =  12'h555; cycle_data_mem[`NOR_CYCLE_ERASE_CHIP][3]   = 16'h00AA;
        cycle_addr_mem[`NOR_CYCLE_ERASE_CHIP][4]   =  12'h2AA; cycle_data_mem[`NOR_CYCLE_ERASE_CHIP][4]   = 16'h0055;
        cycle_addr_mem[`NOR_CYCLE_ERASE_CHIP][5]   =  12'h555; cycle_data_mem[`NOR_CYCLE_ERASE_CHIP][5]   = 16'h0010;

        cycle_addr_mem[`NOR_CYCLE_RESET][0]        =  12'h000; cycle_data_mem[`NOR_CYCLE_RESET][0]        = 16'h00F0;

        cycle_addr_mem[`NOR_CYCLE_WRITE_BUF][0]    =  12'h555; cycle_data_mem[`NOR_CYCLE_WRITE_BUF][0]    = 16'h00AA;
        cycle_addr_mem[`NOR_CYCLE_WRITE_BUF][1]    =  12'h2AA; cycle_data_mem[`NOR_CYCLE_WRITE_BUF][1]    = 16'h0055;
        cycle_addr_mem[`NOR_CYCLE_WRITE_BUF][2]    =  12'h000; cycle_data_mem[`NOR_CYCLE_WRITE_BUF][2]    = 16'h0025;

        cycle_addr_mem[`NOR_CYCLE_PROG_BUF][0]     =  12'h000; cycle_data_mem[`NOR_CYCLE_PROG_BUF][0]     = 16'h0029;

    end

endmodule

