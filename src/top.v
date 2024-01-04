/** top.v
 *
 * QSPI => Parallel NOR bridge (top)
 *
 */

`include "cmd_defs.vh"
`include "busmap.vh"

`default_nettype none
`timescale 1ns/10ps

module top #(
    parameter ADDRBITS = 26,
    parameter DATABITS = 16
) (
    input reset_i, clk_i,

    // QSPI interface
    input               [3:0] pad_spi_io_i,
    output              [3:0] pad_spi_io_o,
    output                    pad_spi_io_oe,
    input                     pad_spi_sck_i,
    input                     pad_spi_sce_i,

    // NOR interface
    input                     nor_ry_i,
    input      [DATABITS-1:0] nor_data_i,
    output reg [DATABITS-1:0] nor_data_o,
    output reg [ADDRBITS-1:0] nor_addr_o,
    output reg                nor_ce_o,
    output                    nor_we_o,
    output reg                nor_oe_o,
    output reg                nor_data_oe, // 0 = input, 1 = output

    // debug
    output                    dbg_txndir, dbg_txndone,
    output              [1:0] dbg_txnmode,
    output              [5:0] dbg_txnbc,
    output             [31:0] dbg_txnmosi, dbg_txnmiso,
    output                    dbg_wb_ctrl_ack,
    output                    dbg_wb_nor_stb,
    output                    dbg_vt_mode
);

    // SPI IO <-> SPI PHY
    wire                [3:0] spi_io_i;
    wire                [3:0] spi_io_o;
    wire                      spi_io_oe;
    wire                      spi_sck;
    wire                      spi_sce;

    // wb connecting qspi and nor controller
    wire memwb_cyc, memwb_stb, memwb_we, memwb_err, memwb_ack, memwb_stall;
    wire [ADDRBITS-1:0] memwb_adr;
    wire [DATABITS-1:0] memwb_dat_i; // MOSI
    wire [DATABITS-1:0] memwb_dat_o; // MISO

    // configuration wb
    wire cfgwb_cyc, cfgwb_stb, cfgwb_we, cfgwb_err, cfgwb_ack, cfgwb_stall, cfgwb_rst;
    wire [`CFGWBADDRBITS-1:0] cfgwb_adr;
    wire [`CFGWBDATABITS-1:0] cfgwb_dat_i; // MOSI
    // each slave must have its own data bus
    wire [`CFGWBDATABITS-1:0] cfgwb_dat_nor_bus_o; // MISO from nor_bus
    wire [`CFGWBDATABITS-1:0] cfgwb_dat_o = cfgwb_dat_nor_bus_o; // MISO

    reg         txndir, txndone;
    reg   [7:0] txnbc;
    wire [31:0] txndata_mosi;
    reg  [31:0] txndata_miso;

    // WE override for VT mode control
    wire nor_we_int, vt_mode;
    assign nor_we_o = nor_we_int && !vt_mode;

    // debug output
    assign dbg_txnmode = 'b0; //txnmode;
    assign dbg_txndir  = 'b0; //txndir;
    //assign dbg_txndone = txndone;
    assign dbg_txnbc   = 'b0; //txnbc;
    assign dbg_txnmosi = 'b0; //txndata_mosi;
    assign dbg_txnmiso = txndata_miso;
    assign dbg_wb_ctrl_ack = 'b0; //wb_ctrl_ack;
    assign dbg_wb_nor_stb = 'b0; //wb_nor_stb;
    assign dbg_vt_mode = 'b0; //vt_mode;

    xspi_phy_io #(
        .IO_POL(1),
        .CE_POL(0)
    ) xspi_phy_io (
        .i_pad_sck(pad_spi_sck_i), .i_pad_sce(pad_spi_sce_i),
        .i_pad_sio(pad_spi_io_i), .o_pad_sio(pad_spi_io_o),
        .o_pad_sio_oe(pad_spi_io_oe),
        .o_sck(spi_sck), .o_sce(spi_sce), .o_sio(spi_io_i),
        .i_sio(spi_io_o), .i_sio_oe(spi_io_oe)
    );

    xspi_phy_slave #(
        .WORD_SIZE(32),
        .CYCLE_COUNT_BITS(8)
    ) xspi_slave (
        .sck_i(spi_sck), .sce_i(spi_sce), .sio_oe(spi_io_oe), .sio_i(spi_io_i), .sio_o(spi_io_o),
        .txnbc_i(txnbc), .txndir_i(txndir), .txndata_i(txndata_mosi),
        .txndata_o(txndata_miso), .txndone_o(txndone)
    );

    qspi_ctrl_fsm #(
        .MEMWBADDRBITS(`NORADDRBITS),
        .MEMWBDATABITS(`NORDATABITS),
        .CFGWBADDRBITS(`CFGWBADDRBITS),
        .CFGWBDATABITS(`CFGWBDATABITS),
        .SPICMDBITS(`SPI_CMD_BITS),
        .SPIADDRBITS(`SPI_ADDR_BITS),
        .SPIWAITCYCLES(`SPI_WAIT_CYC),
        .SPIDATABITS(`SPI_DATA_BITS),
        .IOREG_BITS(32)
    ) qspi_ctrl (
        // general
        .reset_i(reset_i), .clk_i(clk_i),
        // spi slave
        .txnbc_o(txnbc), .txndir_o(txndir), .txndone_i(txndone),
        .txndata_o(txndata_mosi), .txndata_i(txndata_miso), .txnreset_i(!spi_sce),
        // control
        .vt_mode(vt_mode), .d_wstb(dbg_txndone),
        // mem wb
        .memwb_cyc_o(memwb_cyc), .memwb_stb_o(memwb_stb), .memwb_we_o(memwb_we), .memwb_err_i(memwb_err),
        .memwb_adr_o(memwb_adr), .memwb_dat_o(memwb_dat_i), .memwb_ack_i(memwb_ack), .memwb_stall_i(memwb_stall),
        .memwb_dat_i(memwb_dat_o),
        // cfg wb
        .cfgwb_rst_o(cfgwb_rst),
        .cfgwb_adr_o(cfgwb_adr), .cfgwb_dat_o(cfgwb_dat_i),
        .cfgwb_we_o(cfgwb_we), .cfgwb_stb_o(cfgwb_stb), .cfgwb_cyc_o(cfgwb_cyc),
        .cfgwb_err_i(cfgwb_err),
        .cfgwb_ack_i(cfgwb_ack), .cfgwb_dat_i(cfgwb_dat_o), .cfgwb_stall_i(cfgwb_stall)
    );

    nor_bus #(
        .MEMWBADDRBITS(`NORADDRBITS), .MEMWBDATABITS(`NORDATABITS),
        .CFGWBADDRBITS(`CFGWBADDRBITS), .CFGWBDATABITS(`CFGWBDATABITS)
    ) norbus (
        // system
        .sys_rst_i(reset_i), .sys_clk_i(clk_i),
        // mem wb
        .memwb_rst_i(reset_i),
        .memwb_adr_i(memwb_adr), .memwb_dat_i(memwb_dat_i),
        .memwb_we_i(memwb_we), .memwb_stb_i(memwb_stb), .memwb_cyc_i(memwb_cyc),
        .memwb_err_o(memwb_err),
        .memwb_ack_o(memwb_ack), .memwb_dat_o(memwb_dat_o), .memwb_stall_o(memwb_stall),
        // cfg wb
        .cfgwb_rst_i(cfgwb_rst),
        .cfgwb_adr_i(cfgwb_adr), .cfgwb_dat_i(cfgwb_dat_i),
        .cfgwb_we_i(cfgwb_we), .cfgwb_stb_i(cfgwb_stb), .cfgwb_cyc_i(cfgwb_cyc),
        .cfgwb_err_o(cfgwb_err),
        .cfgwb_ack_o(cfgwb_ack), .cfgwb_dat_o(cfgwb_dat_nor_bus_o), .cfgwb_stall_o(cfgwb_stall),
        // nor
        .nor_ry_i(nor_ry_i), .nor_data_i(nor_data_i),
        .nor_data_o(nor_data_o), .nor_addr_o(nor_addr_o),
        .nor_ce_o(nor_ce_o), .nor_we_o(nor_we_int), .nor_oe_o(nor_oe_o),
        .nor_data_oe(nor_data_oe)
    );

endmodule
