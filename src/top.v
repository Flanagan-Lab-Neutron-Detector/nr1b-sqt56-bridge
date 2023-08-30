/** top.v
 *
 * QSPI => Parallel NOR bridge (top)
 *
 */

`include "cmd_defs.v"

`default_nettype none
`timescale 1ns/10ps

module top #(
    parameter ADDRBITS = 26,
    parameter DATABITS = 16
) (
    input reset_i, clk_i,

    // QSPI interface
    //inout               [3:0] qspi_io,
    input               [3:0] qspi_io_i,
    output              [3:0] qspi_io_o,
    output                    qspi_io_oe,
    input                     qspi_sck,
    input                     qspi_sce,

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
    output                    dbg_txnmode, dbg_txndir, dbg_txndone,
    output              [7:0] dbg_txncc,
    output             [31:0] dbg_txnmosi, dbg_txnmiso,
    output                    dbg_wb_ctrl_stb,
    output                    dbg_wb_nor_stb,
    output                    dbg_vt_mode
);

    // wb connecting qspi and nor controller
    wire wb_ctrl_cyc, wb_ctrl_stb, wb_ctrl_we, wb_ctrl_err, wb_ctrl_ack, wb_ctrl_stall;
    wire         [31:0] wb_ctrl_adr;
    wire [DATABITS-1:0] wb_ctrl_dat_i;
    wire [DATABITS-1:0] wb_ctrl_dat_o;

    // wb connecting nor controller and nor driver
    wire wb_nor_cyc, wb_nor_stb, wb_nor_we, wb_nor_err, wb_nor_ack, wb_nor_stall;
    wire [ADDRBITS-1:0] wb_nor_adr;
    wire [DATABITS-1:0] wb_nor_dat_i;
    wire [DATABITS-1:0] wb_nor_dat_o;

    reg txnmode, txndir, txndone;
    reg   [7:0] txncc;
    wire [31:0] txndata_mosi;
    reg  [31:0] txndata_miso;

    // WE override for VT mode control
    wire nor_we_int, vt_mode;
    assign nor_we_o = nor_we_int && !vt_mode;

    // debug output
    assign dbg_txnmode = txnmode;
    assign dbg_txndir  = txndir;
    assign dbg_txndone = txndone;
    assign dbg_txncc   = txncc;
    assign dbg_txnmosi = txndata_mosi;
    assign dbg_txnmiso = txndata_miso;
    assign dbg_wb_ctrl_stb = wb_ctrl_stb;
    assign dbg_wb_nor_stb = wb_nor_stb;
    assign dbg_vt_mode = vt_mode;

    qspi_slave qspi_slave (
        .reset_i(reset_i), .clk_i(clk_i),
        .sck_i(qspi_sck), .sce_i(qspi_sce), .sio_i(qspi_io_i), .sio_o(qspi_io_o), .sio_oe(qspi_io_oe),
        .txncc_i(txncc), .txnmode_i(txnmode), .txndir_i(txndir), .txndone_o(txndone),
        .txndata_i(txndata_mosi), .txndata_o(txndata_miso)
    );

    qspi_ctrl_fsm qspi_ctrl (
        // general
        .reset_i(reset_i), .clk_i(clk_i),
        // spi slave
        .txncc_o(txncc), .txnmode_o(txnmode), .txndir_o(txndir), .txndone_i(txndone),
        .txndata_o(txndata_mosi), .txndata_i(txndata_miso), .txnreset_i(qspi_sce),
        // control
        .vt_mode(vt_mode),
        // wb
        .wb_cyc_o(wb_ctrl_cyc), .wb_stb_o(wb_ctrl_stb), .wb_we_o(wb_ctrl_we), .wb_err_o(wb_ctrl_err),
        .wb_adr_o(wb_ctrl_adr), .wb_dat_o(wb_ctrl_dat_i), .wb_ack_i(wb_ctrl_ack), .wb_stall_i(wb_ctrl_stall),
        .wb_dat_i(wb_ctrl_dat_o)
    );

    wb_nor_controller #(.ADDRBITS(26), .DATABITS(16)) nor_ctrl (
        .wb_rst_i(reset_i), .wb_clk_i(clk_i),

        .wbs_adr_i(wb_ctrl_adr), .wbs_dat_i(wb_ctrl_dat_i),
        .wbs_we_i(wb_ctrl_we), .wbs_stb_i(wb_ctrl_stb), .wbs_cyc_i(wb_ctrl_cyc),
        .wbs_err_i(wb_ctrl_err), .wbs_ack_o(wb_ctrl_ack),
        .wbs_dat_o(wb_ctrl_dat_o), .wbs_stall_o(wb_ctrl_stall),

        .wbm_adr_o(wb_nor_adr), .wbm_dat_o(wb_nor_dat_o),
        .wbm_we_o(wb_nor_we), .wbm_cyc_o(wb_nor_cyc), .wbm_stb_o(wb_nor_stb),
        .wbm_err_o(wb_nor_err), .wbm_ack_i(wb_nor_ack),
        .wbm_dat_i(wb_nor_dat_i), .wbm_stall_i(wb_nor_stall)
    );

    nor_bus #(.ADDRBITS(26), .DATABITS(16)) norbus (
        .wb_rst_i(reset_i), .wb_clk_i(clk_i),
        .wb_adr_i(wb_nor_adr), .wb_dat_i(wb_nor_dat_o),
        .wb_we_i(wb_nor_we), .wb_stb_i(wb_nor_stb), .wb_cyc_i(wb_nor_cyc),
        .wb_err_i(wb_nor_err),
        .wb_ack_o(wb_nor_ack), .wb_dat_o(wb_nor_dat_i), .wb_stall_o(wb_nor_stall),

        .nor_ry_i(nor_ry_i), .nor_data_i(nor_data_i),
        .nor_data_o(nor_data_o), .nor_addr_o(nor_addr_o),
        .nor_ce_o(nor_ce_o), .nor_we_o(nor_we_int), .nor_oe_o(nor_oe_o),
        .nor_data_oe(nor_data_oe)
    );

endmodule
