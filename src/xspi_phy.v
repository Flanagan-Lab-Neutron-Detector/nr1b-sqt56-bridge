/** xspi_phy.v
 *
 * xSPI interface
 *
 * Single-, dual-, quad-, and octo-spi physical interface optimized (NOR flash)
 *
 */

`default_nettype none
`timescale 1ns/10ps

module xspi_phy_io #(
    parameter IO_POL = 1,
    parameter CE_POL = 1
) (
    // pad signals
    input        i_pad_sck, i_pad_sce,
    input  [3:0] i_pad_sio,
    output [3:0] o_pad_sio,
    output       o_pad_sio_oe,

    // module signals
    output       o_sck, o_sce,
    output [3:0] o_sio,
    input  [3:0] i_sio,
    input        i_sio_oe // 0 = input, 1 = output
);
    assign o_pad_sio_oe = i_sio_oe;

    // TODO: CPOL/CPHA?
    assign o_sck = i_pad_sck;

    generate
    if (CE_POL)
        assign o_sce =  i_pad_sce;
    else
        assign o_sce = ~i_pad_sce;
    endgenerate

    generate
    if (IO_POL) begin
        assign o_sio     =  i_pad_sio;
        assign o_pad_sio =  i_sio;
    end else begin
        assign o_sio     = ~i_pad_sio;
        assign o_pad_sio = ~i_sio;
    end
    endgenerate

endmodule

/* xspi_phy_slave
 * Single/dual/quad/octo-SPI slave block.
 *
 * This module is transaction-based. A transaction consists of the
 * transmission or receiption of txnbc_i bits across txnmode_i lanes, over
 * ceil(txnbc_i/(2**txnmode_i)) bus cycles. When txnbc_i bits have been
 * shifted in, txndone_o is asserted. txndata_o may be latched at the rising
 * edge of txndone_o or while txndone_o is high.
 *
 * Only supports SPI with CPOL = CPHA (data changes on falling edge, latched on rising).
 *
 * NOTE: !sce_i is the only reset
 * 
 * Parameters:
 *     WORD_SIZE         (default 32)    Number of bits in transaction data registers
 *     CYCLE_COUNT_BITS  (default 6)     Number of bits in cycle counter
 *                                       (max cycles = 2**CYCLE_COUNT_BITS)
 */
module xspi_phy_slave #(
    parameter WORD_SIZE        = 32, // bits in IO registers
    parameter CYCLE_COUNT_BITS = 6   // number of bits for cycle counter
) (
    // QSPI interface
    input                             sck_i,
    input                             sce_i,
    input                       [3:0] sio_i,
    output reg                  [3:0] sio_o,
    output                            sio_oe,    // 0 = input, 1 = output

    // transaction interface
    input      [CYCLE_COUNT_BITS-1:0] txnbc_i,   // transaction bit count
    input                             txndir_i,  // transaction direction, 0 = read, 1 = write
    input             [WORD_SIZE-1:0] txndata_i,
    output reg        [WORD_SIZE-1:0] txndata_o,
    output reg                        txndone_o  // high for one cycle when data has been received
);

    localparam WORD_SIZE_BITS = $clog2(WORD_SIZE);

    reg  [CYCLE_COUNT_BITS-1:0] cycle_counter;
    reg  [CYCLE_COUNT_BITS-1:0] txn_cycles; // calculated cycles for given txnbc_i
    wire [CYCLE_COUNT_BITS-1:0] outdata_index; // index of SPI word to present
    //wire                  [2:0] bc_odd_mask; // mask low bits for extra cycle check
    wire                        sce_i_b; // negative sce so we can trigger on posedge for reset
    wire                        cycle_stb;

    assign sce_i_b = !sce_i;
    assign outdata_index = txn_cycles - cycle_counter; // index of SPI word in data word
    assign cycle_stb = (cycle_counter == txn_cycles);

    assign sio_oe = sce_i && txndir_i;

    // calculate SPI cycles from bit count
    // an extra cycle is added if txnbc_i does not fit evenly into the
    // configured cycle width (i.e. txnbc_i mod 2**txnmode_i != 0)
    //assign bc_odd_mask = 3'b011;
    //assign txn_cycles = (txnbc_i >> txnmode_i) + (|(bc_odd_mask & txnbc_i[2:0]) ? 'b1 : 'b0) - 'b1;
    //always @(*)
    //    txn_cycles = (txnbc_i >> txnmode_i) + (|(bc_odd_mask & txnbc_i[2:0]) ? 'b1 : 'b0) - 'b1;
    always @(*)
        txn_cycles = (txnbc_i >> 2'b10) + (|(txnbc_i[1:0]) ? 'b1 : 'b0) - 'b1;

    // cycle counter
    always @(negedge sck_i or negedge sce_i)
        if (!sce_i) begin
            cycle_counter <= 'b0;
        end else if (txndone_o) begin
            cycle_counter <= 'b0;
        end else begin
            cycle_counter <= cycle_counter + 'b1;
        end

    // signal done on POSITIVE edge
    always @(posedge sck_i or posedge sce_i_b)
        if (sce_i_b) txndone_o <= 1'b0;
        else         txndone_o <= cycle_stb;

    // SPI

    // set SPI outputs combinationally to avoid deciding when to latch
    always @(*) sio_o = txndata_i[4*outdata_index[WORD_SIZE_BITS-1:0]+:4];

    always @(posedge sck_i) begin
        txndata_o <= { txndata_o[WORD_SIZE-5:0], sio_i[3:0] };
    end

`ifdef FORMAL
    // SPI inputs are synchronous to sck_i.
    // txn inputs are ~synchronous to txndone_o.
    // We can use the global clock to enforce these changes
    (* gclk *) reg f_clk;
    // f_clk past valid
    reg f_g_past_valid;
    initial f_g_past_valid = 0;
    always @(posedge f_clk) f_g_past_valid = 1;

    // sck past valid
    reg f_sck_past_valid;
    initial f_sck_past_valid = 0;
    always @(negedge sck_i) f_sck_past_valid = 1;

    // reset assumptions
    initial assume(!sce_i);
    always @(*) if (!f_sck_past_valid) assume(!sce_i);
    // clock can be initially high or low, but specifically test low
    initial assume(!sck_i);

    // assume we're trying to do something useful
    always @(*) assume(txnbc_i > 0);
    // requesting more than a data word is undefined
    always @(*) assume(txnbc_i <= WORD_SIZE);

    reg [CYCLE_COUNT_BITS-1:0] f_txnbc;
    reg                        f_txndir;
    reg        [WORD_SIZE-1:0] f_txndata;

    // record parameters for this transaction
    always @(negedge sck_i)
        if (sce_i && f_sck_past_valid && (txndone_o || !$past(sce_i))) begin
            f_txnbc   <= txnbc_i;
            f_txndir  <= txndir_i;
            f_txndata <= txndata_i;
        end

    // count (completed) transactions
    integer f_txn_counter;
    initial f_txn_counter = 0;
    always @(negedge sck_i or negedge sce_i)
        if (!sce_i)         f_txn_counter <= 0;
        else if (txndone_o) f_txn_counter <= f_txn_counter + 1;

    wire txndone_cond; // when true, txndone_o will be set on next sck rising edge
    assign txndone_cond = sce_i && (cycle_counter == txn_cycles);

    // transaction configuration should only change on txndone_o rising edge
    // (or reset)
    always @(posedge f_clk) begin
        if (!sce_i || (f_g_past_valid && !$rose(txndone_o))) begin
            assume(txnbc_i   == f_txnbc);
            assume(txndir_i  == f_txndir);
            assume(txndata_i == f_txndata);
        end
    end

    // track transaction cycles
    reg [CYCLE_COUNT_BITS-1:0] f_cc;
    always @(negedge sck_i or negedge sce_i)
        if (!sce_i) begin
            f_cc <= 'b0;
        end else if (txndone_o) begin
            f_cc <= 'b0;
        end else begin
            f_cc <= f_cc + 'b1;
        end

    // mask for "extra" bits
    wire [2:0] f_bcmask;
    assign f_bcmask = 3'b011;

    // spi input words should be shifted into txndata_o
    // first spi word is MSW, last is LSW
    genvar txndi;
    generate
    // txnmode_i = 10
    for (txndi=0; txndi < (WORD_SIZE/4); txndi = txndi + 1) begin
        always @(negedge sck_i)
            if ((txndi < f_cc) /*&& f_txnmode == 2'b10*/ && !sce_i && f_sck_past_valid)
                    assert(txndata_o[4*txndi:+4] == $past(sio_i[3:0], txndi));
    end
    endgenerate

    // spi output words should be shifted from txndata_i
    // first spi word is MSW, last is LSW
    genvar sioi;
    generate
    // txnmode_i = 10
    for (sioi=0; sioi < (WORD_SIZE/4); sioi = sioi + 1) begin
        always @(negedge sck_i)
            if ((sioi < f_cc) /*&& f_txnmode == 2'b10*/ && !sce_i && f_sck_past_valid)
                    assert(f_txndata[4*sioi:+4] == $past(sio_o[3:0], sioi));
    end
    endgenerate

    // never assert output unless enabled
    // always assert output if sce_i and txndir_i
    always @(posedge f_clk) begin
        if (f_g_past_valid) begin
            if (sce_i) begin
                if ($fell(sck_i)) assert(sio_oe == ($past(sce_i) && $past(txndir_i)));
                else              assert($stable(sio_oe));
            end else begin
                assert(!sio_oe);
            end
        end
    end

    // covers
    always @(*) begin
        if (f_sck_past_valid && sce_i) begin
c_txn:      cover(txndone_o); // a transaction should complete
c_txnw:     cover(txndone_cond && !txndir_i); // a write transaction should complete
c_txnwnz:   cover(txndone_cond && !txndir_i && (txndata_o[txnbc_i-1:0] != 'b0)); // a nonzero write transaction should complete
c_txnr:     cover(txndone_cond &&  txndir_i); // a read transaction should complete
c_txnrnz:   cover(txndone_cond &&  txndir_i && (txndata_i[txnbc_i-1:0] != 'b0)); // a nonzero read transaction should complete
//c_txnm00:   cover(txndone_cond && (txnmode_i == 2'b00)); // a single-spi transaction should complete
//c_txnm01:   cover(txndone_cond && (txnmode_i == 2'b01)); // a dual-spi transaction should complete
c_txnm10:   cover(txndone_cond /*&& (txnmode_i == 2'b10)*/); // a quad-spi transaction should complete
//c_txnm11:   cover(txndone_cond && (txnmode_i == 2'b11)); // an octo-spi transaction should complete
c_txnce:    cover(txndone_cond && !|(f_bcmask & txnbc_i[2:0])); // a transaction should complete with an "even" number of cycles
c_txnco:    cover(txndone_cond &&  |(f_bcmask & txnbc_i[2:0])); // a transaction should complete with an "odd" number of cycles
//c_txnfwm00: cover(txndone_cond && (txnbc_i == WORD_SIZE) && (txnmode_i == 2'b00) && (txndata_i[txnbc_i-1:0] != 'b0) && (txndata_o[txnbc_i-1:0] != 'b0)); // full word mode 00
//c_txnfwm01: cover(txndone_cond && (txnbc_i == WORD_SIZE) && (txnmode_i == 2'b01) && (txndata_i[txnbc_i-1:0] != 'b0) && (txndata_o[txnbc_i-1:0] != 'b0)); // full word mode 01
c_txnfwm10: cover(txndone_cond && (txnbc_i == WORD_SIZE) /*&& (txnmode_i == 2'b10)*/ && (txndata_i[txnbc_i-1:0] != 'b0) && (txndata_o[txnbc_i-1:0] != 'b0)); // full word mode 10
//c_txnfwm11: cover(txndone_cond && (txnbc_i == WORD_SIZE) && (txnmode_i == 2'b11) && (txndata_i[txnbc_i-1:0] != 'b0) && (txndata_o[txnbc_i-1:0] != 'b0)); // full word mode 11
c_2t:       cover(f_txn_counter == 2);
c_3t:       cover(f_txn_counter == 3);
c_4t:       cover(f_txn_counter == 4);
        end
    end

`endif
endmodule

