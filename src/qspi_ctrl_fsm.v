/** qspi.v
 *
 * QSPI interface
 *
 */

`include "cmd_defs.vh"
`include "busmap.vh"
`include "spi_state.vh"

`default_nettype none
`timescale 1ns/10ps

module qspi_ctrl_fsm #(
    parameter MEMWBADDRBITS = `NORADDRBITS,
    parameter MEMWBDATABITS = `NORDATABITS,
    parameter CFGWBADDRBITS = `CFGWBADDRBITS,
    parameter CFGWBDATABITS = `CFGWBDATABITS,
    parameter SPICMDBITS    = `SPI_CMD_BITS,
    parameter SPIADDRBITS   = `SPI_ADDR_BITS,
    parameter SPIWAITCYCLES = `SPI_WAIT_CYC,
    parameter SPIDATABITS   = `SPI_DATA_BITS,
    parameter IOREG_BITS    = 32
) (
    input reset_i, // synchronous to local clock
    input clk_i, // local clock

    // data inputs
    output     [CYCLE_COUNT_BITS-1:0] txnbc_o,   // transaction bit count
    output                            txndir_o,  // transaction direction, 0 = read, 1 = write
    output           [IOREG_BITS-1:0] txndata_o,
    input            [IOREG_BITS-1:0] txndata_i,
    input                             txndone_i, // high for one cycle when data has been received
    input                             txnreset_i, // transaction reset (CE high)

    // controller requests
    output reg                        vt_mode,
    // debug
    output                            d_wstb,

    // memory wishbone
    output reg                        memwb_cyc_o,
    output reg                        memwb_stb_o,
    output reg                        memwb_we_o,
    output reg    [MEMWBADDRBITS-1:0] memwb_adr_o,
    output reg    [MEMWBDATABITS-1:0] memwb_dat_o,
    input                             memwb_err_i,
    input                             memwb_ack_i,
    input                             memwb_stall_i,
    input         [MEMWBDATABITS-1:0] memwb_dat_i,

    // cfg wishbone
    output                            cfgwb_rst_o,
    output reg    [CFGWBADDRBITS-1:0] cfgwb_adr_o,
    output reg    [CFGWBDATABITS-1:0] cfgwb_dat_o,
    output reg                        cfgwb_we_o,
    output reg                        cfgwb_stb_o, // TODO: one stb per peripheral
    output reg                        cfgwb_cyc_o,
    input                             cfgwb_err_i,
    input                             cfgwb_ack_i,
    input         [CFGWBDATABITS-1:0] cfgwb_dat_i,
    input                             cfgwb_stall_i
);

    // Currently all commands are 8-bit, 1-lane
    // All other phases are N-bit 4-lane (quad)
    localparam CYCLE_COUNT_BITS     = 8;

    reg                       spirst;
    reg                       spistbcmd, spistbadr, spistbrrq, spistbwrq;
    reg [`SPI_STATE_BITS-1:0] spistate;
    reg      [SPICMDBITS-1:0] spicmd;
    reg     [SPIADDRBITS-1:0] spiaddr;
    reg     [SPIDATABITS-1:0] spidata_if;
    reg     [SPIDATABITS-1:0] spidata_ctrl;

    assign d_wstb = spistbcmd | spistbadr | spistbrrq | spistbwrq;

    qspi_if qspi_if (
        .i_clk(clk_i), .i_rst(reset_i),
        // spi phy
        .o_txnbc(txnbc_o), .o_txndir(txndir_o), .o_txndata(txndata_o),
        .i_txndata(txndata_i), .i_txndone(txndone_i), .i_txnreset(txnreset_i),
        // controller
        .o_spirst(spirst), .o_spistbcmd(spistbcmd), .o_spistbadr(spistbadr),
        .o_spistbrrq(spistbrrq), .o_spistbwrq(spistbwrq), .o_spistate(spistate),
        .o_spicmd(spicmd), .o_spiaddr(spiaddr), .o_spidata(spidata_if),
        .i_spidata(spidata_ctrl)
    );

    ctrl ctrl (
        .i_clk(clk_i), .i_sysrst(reset_i),
        // spi
        .i_spirst(spirst), .i_spistbcmd(spistbcmd), .i_spistbadr(spistbadr),
        .i_spistbrrq(spistbrrq), .i_spistbwrq(spistbwrq), .i_spistate(spistate),
        .i_spicmd(spicmd), .i_spiaddr(spiaddr), .i_spidata(spidata_if),
        .o_spidata(spidata_ctrl),
        // memory wishbone
        .o_memwb_cyc(memwb_cyc_o), .o_memwb_stb(memwb_stb_o), .o_memwb_we(memwb_we_o),
        .o_memwb_adr(memwb_adr_o), .o_memwb_dat(memwb_dat_o),
        .i_memwb_err(memwb_err_i), .i_memwb_ack(memwb_ack_i), .i_memwb_stall(memwb_stall_i),
        .i_memwb_dat(memwb_dat_i),
        // cfg wishbone
        .o_cfgwb_rst(cfgwb_rst_o),
        .o_cfgwb_cyc(cfgwb_cyc_o), .o_cfgwb_stb(cfgwb_stb_o), .o_cfgwb_we(cfgwb_we_o),
        .o_cfgwb_adr(cfgwb_adr_o), .o_cfgwb_dat(cfgwb_dat_o),
        .i_cfgwb_err(cfgwb_err_i), .i_cfgwb_ack(cfgwb_ack_i), .i_cfgwb_stall(cfgwb_stall_i),
        .i_cfgwb_dat(cfgwb_dat_i),
        // other
        .o_vtmode(vt_mode)
    );

endmodule
