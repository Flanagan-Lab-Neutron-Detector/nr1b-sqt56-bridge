/** xspi_os_phy.v
 *
 * xSPI interface with oversampling
 *
 * Single-, dual-, quad-, and octo-spi physical interface optimized for NOR flash
 *
 */

`default_nettype none
`timescale 1ns/10ps

/* xspi_phy_slave
 * Single/dual/quad/octo-SPI slave block.
 *
 * This module is transaction-based. A transaction consists of the
 * transmission or receiption of txnbc_i bits across txnmode_i lanes, over
 * ceil(txnbc_i/(2**txnmode_i)) bus cycles. When txnbc_i bits have been
 * shifted in, txndone_o is asserted for one clock cycle.
 *
 * Only supports SPI with CPOL = CPHA (data changes on falling edge, latched on rising).
 *
 * Parameters:
 *     WORD_SIZE         (default 32)    Number of bits in transaction data registers
 *     CYCLE_COUNT_BITS  (default 6)     Number of bits in cycle counter
 *                                       (max cycles = 2**CYCLE_COUNT_BITS)
 */
module xspi_os_phy_slave #(
    parameter WORD_SIZE        = 32, // bits in IO registers
    parameter CYCLE_COUNT_BITS = 6   // number of bits for cycle counter
) (
    // QSPI interface
    input                             sck_i,
    input                             sce_i,
    input                       [7:0] sio_i,
    output reg                  [7:0] sio_o,
    output                            sio_oe,    // 0 = input, 1 = output

    // transaction interface
    input                             tclk_i, trst_i,
    input      [CYCLE_COUNT_BITS-1:0] txnbc_i,   // transaction bit count
    input                       [1:0] txnmode_i, // transaction mode, 00 = single SPI, 01 = dual SPI, 10 = quad SPI, 11 = octo SPI
    input                             txndir_i,  // transaction direction, 0 = read, 1 = write
    input             [WORD_SIZE-1:0] txndata_i,
    output reg        [WORD_SIZE-1:0] txndata_o,
    output reg                        txndone_o, // high for one cycle when data has been received
    output                            txnreset_o // synchronized ~SCE
);

    localparam WORD_SIZE_BITS = $clog2(WORD_SIZE);

    reg  [CYCLE_COUNT_BITS-1:0] cycle_counter;
    wire [CYCLE_COUNT_BITS-1:0] txn_cycles; // calculated cycles for given txnbc_i
    wire [CYCLE_COUNT_BITS-1:0] outdata_index; // index of SPI word to present
    reg                   [2:0] bc_odd_mask; // mask low bits for extra cycle check
    wire                        cycle_stb; // high for one cycle when cycle_counter == txn_cycles

    // register sio_i on /SCK so it can be sampled after \SCK
    reg  [7:0] sio_i_q;
    always @(posedge sck_i)
        sio_i_q <= sio_i;

    assign outdata_index = txn_cycles - cycle_counter; // index of SPI word in data word
    assign cycle_stb = (cycle_counter == txn_cycles); // cycle is done

    assign sio_oe = sce_i && txndir_i;
    assign txnreset_o = !sce;

    // synchronize serial clock and chip enable to local clock
    wire sck, sck_pe, sck_ne;
    wire sce, sce_pe, sce_ne;
    sync2pse sync_sck (.clk(tclk_i), .rst(trst_i), .d(sck_i), .q(sck), .pe(sck_pe), .ne(sck_ne));
    sync2pse sync_sce (.clk(tclk_i), .rst(trst_i), .d(sce_i), .q(sce), .pe(sce_pe), .ne(sce_ne));

    // calculate SPI cycles from bit count
    // an extra cycle is added if txnbc_i does not fit evenly into the
    // configured cycle width (i.e. txnbc_i mod 2**txnmode_i != 0)
    always @(*) case(txnmode_i)
        2'b00: bc_odd_mask = 3'b000;
        2'b01: bc_odd_mask = 3'b001;
        2'b10: bc_odd_mask = 3'b011;
        2'b11: bc_odd_mask = 3'b111;
    endcase
    assign txn_cycles = (txnbc_i >> txnmode_i) + (|(bc_odd_mask & txnbc_i[2:0]) ? 'b1 : 'b0) - 'b1;

    // cycle counter
    // count up on rising edge of sck_i
    // reset on sce low or cycle_stb
    always @(posedge tclk_i)
        if (!sce) begin
            cycle_counter <= 'b0;
        end else if (sck_pe) begin
            if (cycle_stb) cycle_counter <= 'b0;
            else           cycle_counter <= cycle_counter + 'b1;
        end

    // signal done for one clock on cycle_stb and /SCK
    always @(posedge tclk_i) begin
        txndone_o <= 1'b0;
        if (sck_pe)
            txndone_o <= cycle_stb;
    end

    // SPI

    always @(posedge tclk_i) case(txnmode_i)
        2'b00: sio_o <= { 7'b0, txndata_i[1*outdata_index[WORD_SIZE_BITS-1:0]   ] };
        2'b01: sio_o <= { 6'b0, txndata_i[2*outdata_index[WORD_SIZE_BITS-1:0]+:2] };
        2'b10: sio_o <= { 4'b0, txndata_i[4*outdata_index[WORD_SIZE_BITS-1:0]+:4] };
        2'b11: sio_o <=         txndata_i[8*outdata_index[WORD_SIZE_BITS-1:0]+:8];
    endcase

    // shift in data on sck rising edge
    always @(posedge tclk_i) begin
        if (trst_i) txndata_o <= 'b0;
        else if (sck_pe) case (txnmode_i)
            2'b00: txndata_o <= { txndata_o[WORD_SIZE-2:0], sio_i_q[0:0] };
            2'b01: txndata_o <= { txndata_o[WORD_SIZE-3:0], sio_i_q[1:0] };
            2'b10: txndata_o <= { txndata_o[WORD_SIZE-5:0], sio_i_q[3:0] };
            2'b11: txndata_o <= { txndata_o[WORD_SIZE-9:0], sio_i_q[7:0] };
        endcase
    end

endmodule

