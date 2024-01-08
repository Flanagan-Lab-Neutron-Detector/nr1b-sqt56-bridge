/** qspi_if.v
 *
 * QSPI interface
 *
 */

`include "cmd_defs.vh"
`include "busmap.vh"
`include "spi_state.vh"

`default_nettype none
`timescale 1ns/10ps

module qspi_if #(
    //parameter MEMWBADDRBITS = `NORADDRBITS,
    //parameter MEMWBDATABITS = `NORDATABITS,
    //parameter CFGWBADDRBITS = `CFGWBADDRBITS,
    //parameter CFGWBDATABITS = `CFGWBDATABITS,
    parameter SPICMDBITS    = `SPI_CMD_BITS,
    parameter SPIADDRBITS   = `SPI_ADDR_BITS,
    parameter SPIWAITCYCLES = `SPI_WAIT_CYC,
    parameter SPIDATABITS   = `SPI_DATA_BITS,
    parameter IOREG_BITS    = 32,
    parameter CYCLE_COUNT_BITS = 8
) (
    input i_clk, i_rst,

    // data inputs
    output     [CYCLE_COUNT_BITS-1:0] o_txnbc,   // transaction bit count
    output                            o_txndir,  // transaction direction, 0 = read, 1 = write
    output           [IOREG_BITS-1:0] o_txndata,
    input            [IOREG_BITS-1:0] i_txndata,
    input                             i_txndone, // high for one cycle when data has been received
    input                             i_txnreset, // transaction reset (CE high)

    // spi outputs
    output                            o_spirst,
    //output reg                        o_spistb,
    output reg                        o_spistbcmd,
    output reg                        o_spistbadr,
    output reg                        o_spistbrrq,
    output reg                        o_spistbwrq,
    output      [`SPI_STATE_BITS-1:0] o_spistate,
    output reg       [SPICMDBITS-1:0] o_spicmd,
    output reg      [SPIADDRBITS-1:0] o_spiaddr,
    output reg      [SPIDATABITS-1:0] o_spidata,
    input           [SPIDATABITS-1:0] i_spidata
);

    // NOTE: Most masters only operate on bytes for address and data, so
    // round up to byte boundaries
    localparam SPIADDRBITS_RND = 8 * ((SPIADDRBITS + 8 - 1)/8);
    localparam SPIDATABITS_RND = 8 * ((SPIDATABITS + 8 - 1)/8);

    // synchronize SPI -> sys
    wire wstb, wstb_pe;

    // spi reset
    wire spi_reset;
    assign spi_reset = i_rst || o_spirst;

    // SPI state
    reg [`SPI_STATE_BITS-1:0] spi_state_next;
    reg [`SPI_STATE_BITS-1:0] spi_state;
    assign o_spistate = spi_state;

    // { [CYCLE_COUNT_BITS+1-1:3]=bit_count, [0]=dir }
    reg [CYCLE_COUNT_BITS+1-1:0] txn_config_reg[8];
    assign { o_txnbc, o_txndir } = txn_config_reg[spi_state];
    // initialize config reg
    integer i;
    initial begin
        // pre-init to command
        for (i = 0; i < 8; i = i + 1) begin
            txn_config_reg[i] = { 8'h08, 1'b0 }; // COMMAND: quad-SPI, input, 8 bits
        end
        txn_config_reg[0] = { SPICMDBITS[7:0],      1'b0 }; // COMMAND:    quad-SPI, input, 8 cycles
        txn_config_reg[1] = { SPIADDRBITS_RND[7:0], 1'b0 }; // ADDR:       quad-SPI, input
        txn_config_reg[2] = { 8'd4*SPIWAITCYCLES[7:0],   1'b0 }; // STALL:      quad-SPI, input, 20 cycles
        txn_config_reg[3] = { SPIDATABITS_RND[7:0], 1'b1 }; // READ DATA:  quad-SPI, output
        txn_config_reg[4] = { SPIDATABITS_RND[7:0], 1'b0 }; // WRITE DATA: quad-SPI, input
    end

    // synchronize to txndone rising edge (word strobe)
    sync2pse sync_wstb (
        .clk(i_clk), .rst(i_rst),
        .d(i_txndone), .q(wstb),
        .pe(wstb_pe), .ne()
    );

    // sync txnreset (ce deassertion) to sys domain
    // reset value should be 1
    sync2ps #(.R(1)) sync_txnreset (.clk(i_clk), .rst(i_rst), .d(i_txnreset), .q(o_spirst));

    // delay SPI strobe by one cycle when latching data
    // so that the controller can access that data
    //reg wstb_pe_delay;
    //always @(posedge i_clk) wstb_pe_delay <= wstb_pe;
    //always @(*) o_spistb = wstb_pe;
    //always @(*) o_spistb = wstb_pe_delay;
    /*always @(*)
        case (spi_state)
            `SPI_STATE_CMD:        o_spistb = wstb_pe_delay;
            `SPI_STATE_ADDR:       o_spistb = wstb_pe_delay;
            `SPI_STATE_WRITE_DATA: o_spistb = wstb_pe_delay;
            default:               o_spistb = wstb_pe;
        endcase*/

    // cmd, addr, read req, write req strobes
    //reg addrstb;
    always @(posedge i_clk) begin
        o_spistbcmd <= wstb_pe && spi_state == `SPI_STATE_CMD;
        // delay o_spistbadr by one cycle to allow address to latch
        //addrstb     <= wstb_pe && spi_state == `SPI_STATE_ADDR;
        //o_spistbadr <= addrstb;
        o_spistbadr <= wstb_pe && spi_state == `SPI_STATE_ADDR;
        // read req on these transisions:
        //   ADDR -> STALL
        //   ADDR -> READ_DATA
        //   READ_DATA -> READ_DATA
        o_spistbrrq <= wstb_pe && (
            (spi_state_next == `SPI_STATE_STALL) ||
            (spi_state_next == `SPI_STATE_READ_DATA));
        // delay this too?
        o_spistbwrq <= wstb_pe && spi_state == `SPI_STATE_WRITE_DATA;
    end

    // QSPI state changes
    always @(*) begin
        case (spi_state)
            `SPI_STATE_CMD: case(o_spicmd)
                default:                 spi_state_next = `SPI_STATE_ADDR;
            endcase
            `SPI_STATE_ADDR: case (o_spicmd)
                `SPI_COMMAND_READ:       spi_state_next = `SPI_STATE_READ_DATA;
                `SPI_COMMAND_FAST_READ:  spi_state_next = `SPI_STATE_STALL;
                `SPI_COMMAND_WRITE_THRU: spi_state_next = `SPI_STATE_WRITE_DATA;
                default:                 spi_state_next = `SPI_STATE_CMD;
            endcase
            `SPI_STATE_STALL:            spi_state_next = `SPI_STATE_READ_DATA;
            `SPI_STATE_READ_DATA:        spi_state_next = `SPI_STATE_READ_DATA; // continuous reads
            `SPI_STATE_WRITE_DATA:       spi_state_next = `SPI_STATE_ADDR;      // continuous writes
            default:                     spi_state_next = 3'bxxx;
        endcase
    end
    always @(posedge i_clk) begin
        if (spi_reset)    spi_state <= `SPI_STATE_CMD;
        else if (wstb_pe) spi_state <= spi_state_next;
    end

    // latch command, address, and data
    always @(posedge i_clk)
        if (i_rst) begin
            o_spicmd  <= 'b0;
            o_spiaddr <= 'b0;
            o_spidata <= 'b0;
        end else if (wstb_pe) begin case (spi_state)
            `SPI_STATE_CMD:        o_spicmd  <= i_txndata[7:0];
            `SPI_STATE_ADDR:       o_spiaddr <= i_txndata[SPIADDRBITS-1:0];
            `SPI_STATE_WRITE_DATA: o_spidata <= i_txndata[SPIDATABITS-1:0];
            default:;
        endcase end

    assign o_txndata[IOREG_BITS-1:SPIDATABITS] = 'b0;
    assign o_txndata[SPIDATABITS-1:0]          = i_spidata;
    
endmodule
