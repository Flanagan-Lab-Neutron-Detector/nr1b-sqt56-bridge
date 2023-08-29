/** tb_qspi.v
 *
 * Top-level testbench wrapper for cocotb
 *
 */

`default_nettype none
`timescale 1ns/10ps

module tb_qspi #(
    parameter ADDRBITS = 26,
    parameter DATABITS = 16
)(
    input rst_i, clk_i,

    input                     sck_i, // synchronize to local clock
    input                     sce_i, // synchronize to local clock
    //inout               [3:0] sio,
    input               [3:0] sio_i, // synchronize to local clock
    output              [3:0] sio_o, // synchronized to local clock
    output                    sio_oe, // 0 = input, 1 = output

    // wishbone
    output reg                wb_cyc_o,
    output reg                wb_stb_o,
    output reg                wb_we_o,
    output reg                wb_err_o,
    output reg         [31:0] wb_adr_o,
    output reg [DATABITS-1:0] wb_dat_o,
    input                     wb_ack_i,
    input                     wb_stall_i,
    input      [DATABITS-1:0] wb_dat_i
);

`ifdef VERILATOR
    initial begin
        $dumpfile ("tb_qspi.vcd");
        //$dumpvars (0, tb_wb_nor_controller);
    end
`else
    // dumps the trace to a vcd file that can be viewed with GTKWave
    integer i;
    initial begin
        $dumpfile ("tb_qspi.vcd");
        $dumpvars (0, tb_qspi);
        for (i = 0; i < 16; i = i + 1)
            $dumpvars(1, qspi_ctrl.txn_config_reg[i]);
        #1;
    end
`endif

    reg [7:0] txncc;
    reg txnmode, txndir, txndone;
    reg [31:0] txndata_mosi;
    reg [31:0] txndata_miso;

    qspi_slave qspi_slave (
        .reset_i(rst_i), .clk_i(clk_i),
        .sck_i(sck_i), .sce_i(sce_i), .sio_i(sio_i), .sio_o(sio_o), .sio_oe(sio_oe),
        .txncc_i(txncc), .txnmode_i(txnmode), .txndir_i(txndir), .txndone_o(txndone),
        .txndata_i(txndata_mosi), .txndata_o(txndata_miso)
    );

    //qspi_ctrl qspi_ctrl (
    qspi_ctrl_fsm qspi_ctrl (
        // general
        .reset_i(rst_i), .clk_i(clk_i),
        // spi slave
        .txncc_o(txncc), .txnmode_o(txnmode), .txndir_o(txndir), .txndone_i(txndone),
        .txndata_o(txndata_mosi), .txndata_i(txndata_miso), .txnreset_i(sce_i),
        // wb
        .wb_cyc_o(wb_cyc_o), .wb_stb_o(wb_stb_o), .wb_we_o(wb_we_o), .wb_err_o(wb_err_o),
        .wb_adr_o(wb_adr_o), .wb_dat_o(wb_dat_o), .wb_ack_i(wb_ack_i), .wb_stall_i(wb_stall_i),
        .wb_dat_i(wb_dat_i)
    );

endmodule