/** wbdbgmon.v
 *
 * Wishbone debug monitor
 *
 */

`default_nettype none
`timescale 1ns/100ps

module wbdbgmon #(
    parameter ADDRBITS = 26,
    parameter DATABITS = 16,
    parameter TIDBITS  = 13,
    parameter FIFOBITS = TIDBITS + 1 + ADDRBITS + DATABITS,           // 56b = 7B
    parameter BUSBITS  = TIDBITS + 1 + ADDRBITS + DATABITS + DATABITS // 72b = 9B
) (
    // debug interface
    input                     i_dbg_rst,
    input                     i_dbg_en,
    output reg                o_dbg_stb,
    output reg  [BUSBITS-1:0] o_dbg_txn,

    // wishbone interface
    input                     i_wb_rst,
    input                     i_wb_clk,
    input      [ADDRBITS-1:0] i_wb_adr,
    input      [DATABITS-1:0] i_wb_dat_m, // data from master
    input                     i_wb_we,
    input                     i_wb_stb,
    input                     i_wb_cyc,
    input                     i_wb_err,
    input                     i_wb_ack,
    input      [DATABITS-1:0] i_wb_dat_s, // data from slave
    input                     i_wb_stall
);

    // pending request fifo
    wire fifo_full, fifo_empty;
    reg  fifo_wr, fifo_rd;
    reg  [FIFOBITS-1:0] fifo_wr_data;
    wire [FIFOBITS-1:0] fifo_rd_data;
    fsfifo #(.WIDTH(FIFOBITS), .DEPTH(32)) pendfifo (
        .clk_i(i_wb_clk), .reset_i(i_wb_rst || i_dbg_rst),
        .full_o(fifo_full), .empty_o(fifo_empty), .filled_o(),
        .wr_i(fifo_wr), .wr_data_i(fifo_wr_data),
        .rd_i(fifo_rd), .rd_data_o(fifo_rd_data)
    );

    wire stb_valid = i_wb_cyc && i_wb_stb && !i_wb_stall && !i_wb_rst && !i_wb_err;
    wire ack_valid = i_wb_cyc && i_wb_ack && !i_wb_rst && !i_wb_err;
    // capture a request
    wire capture = i_dbg_en && stb_valid && !fifo_full;

    // increment tid on capture
    reg  [TIDBITS-1:0] tid;
    always @(posedge i_wb_clk) begin
        if (i_dbg_rst)      tid <= 'b0;
        else if (capture) tid <= tid + 'b1;
    end

    // capture request on stb
    always @(*) begin
        fifo_wr_data = 'b0;
        fifo_wr      = 'b0;
        // do not capture request if it's instantaneously acknowledged
        if (capture && !(i_wb_ack && fifo_empty)) begin
            fifo_wr_data = { tid, i_wb_we, i_wb_adr, i_wb_dat_m };
            fifo_wr      = 'b1;
        end
    end

    // load request from fifo on ack, assemble complete transaction, and send
    always @(*) begin
        fifo_rd = ack_valid && !fifo_empty;
    end
    always @(posedge i_wb_clk) begin
        if (i_dbg_rst) begin
            o_dbg_stb <= 'b0;
            o_dbg_txn <= 'b0;
        end else if (capture && i_wb_ack && fifo_empty) begin
            // capture request directly if instantaneously acknowledged, otherwise read from FIFO
            o_dbg_stb <= 'b1;
            o_dbg_txn <= { tid, i_wb_we, i_wb_adr, i_wb_dat_m, i_wb_dat_s };
        end else begin
            o_dbg_stb <= fifo_rd;
            o_dbg_txn <= { fifo_rd_data, i_wb_dat_s };
        end
    end

`ifdef FORMAL
    // past valid
    reg f_past_valid;
    initial f_past_valid <= 'b0;
    always @(posedge i_wb_clk) f_past_valid <= 'b1;

    // initial assumptions
    `ifdef FORMAL_WBDGMON_TOP
    initial assume(i_dbg_rst);
    initial assume(i_wb_rst);
    `endif

    // count debug strobes
    integer dbg_stb_count;
    initial dbg_stb_count = 'b0;
    always @(posedge i_wb_clk) begin
        if (o_dbg_stb) dbg_stb_count <= dbg_stb_count + 'b1;
    end

    // basic assertions

    always @(posedge i_wb_clk) begin
        if (f_past_valid) begin
            if ($past(i_dbg_rst) || $past(i_wb_rst))
                assert(!o_dbg_stb);
            if (!$past(i_wb_cyc))
                assert(!o_dbg_stb);
            if ($past(i_wb_err))
                assert(!o_dbg_stb);
        end
    end

    // covers
    `define COVER_VALID (f_past_valid && !i_dbg_rst && !$past(i_dbg_rst) && !i_wb_rst && !$past(i_wb_rst))
    always @(posedge i_wb_clk) begin
        cover(`COVER_VALID && !fifo_empty);
        cover(`COVER_VALID && o_dbg_stb && fifo_empty);
        cover(`COVER_VALID && o_dbg_stb && !fifo_empty);
        //cover(`COVER_VALID && o_dbg_stb && tid == 'd0);
        cover(`COVER_VALID && o_dbg_stb && dbg_stb_count == 'd1);
        cover(`COVER_VALID && o_dbg_stb && dbg_stb_count == 'd2);
        cover(`COVER_VALID && o_dbg_stb && dbg_stb_count == 'd3 && fifo_empty);
        cover(`COVER_VALID && o_dbg_stb && dbg_stb_count == 'd3 && !fifo_empty);
    end
`endif

endmodule
