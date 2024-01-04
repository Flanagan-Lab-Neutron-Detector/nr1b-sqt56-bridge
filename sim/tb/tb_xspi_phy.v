/** tb_xspi_phy.v
 *
 * Top-level testbench wrapper for cocotb
 *
 */

`default_nettype none
`timescale 1ns/10ps

module tb_xspi_phy #(
    parameter MEMWBADDRBITS = 26,
    parameter MEMWBDATABITS = 16,
    parameter CFGWBADDRBITS = 16,
    parameter CFGWBDATABITS = 16
)(
    input t_dumpb, // 1 = stop dump, 0 = dump

    input rst_i, clk_i,

    input                     sck_i,
    input                     sce_i,
    input               [3:0] sio_i,
    output              [3:0] sio_o,
    output                    sio_oe, // 0 = input, 1 = output

    // controller
    output reg                        vt_mode_o,

    // mem wishbone
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
    output        [CFGWBADDRBITS-1:0] cfgwb_adr_o,
    output        [CFGWBDATABITS-1:0] cfgwb_dat_o,
    output                            cfgwb_we_o,
    output                            cfgwb_stb_o,
    output                            cfgwb_cyc_o,
    input                             cfgwb_err_i,
    input                             cfgwb_ack_i,
    input         [CFGWBDATABITS-1:0] cfgwb_dat_i,
    input                             cfgwb_stall_i
);

    // dumps the trace to a vcd file that can be viewed with GTKWave
    //integer i;
    initial begin
        $dumpfile ("tb_xspi_phy.vcd");
`ifndef VERILATOR
        $dumpvars (0, tb_xspi_phy);
        //for (i = 0; i < 16; i = i + 1)
            //$dumpvars(1, qspi_ctrl.txn_config_reg[i]);
        #1;
`endif // !defined(VERILATOR)
    end

    // dump control
    reg [1:0] r_dumpb;
    initial r_dumpb = 2'b00;
    always @(posedge clk_i) begin
        r_dumpb <= { r_dumpb[0], t_dumpb };
        if ( r_dumpb[1] && !r_dumpb[0]) $dumpon;  // falling edge
        if (!r_dumpb[1] &&  r_dumpb[0]) $dumpoff; // rising edge
    end

    reg  [7:0] txnbc;
    reg        txndir, txndone;
    reg [31:0] txndata_mosi;
    reg [31:0] txndata_miso;

    wire spi_ce_nrst;
    assign spi_ce_nrst = sce_i && !rst_i;

    xspi_phy_slave #(
        .CYCLE_COUNT_BITS(8)
    ) xspi_phy_slave (
        .sck_i(sck_i), .sce_i(spi_ce_nrst), .sio_i(sio_i), .sio_o(sio_o), .sio_oe(sio_oe),
        .txnbc_i(txnbc), .txndir_i(txndir), .txndone_o(txndone),
        .txndata_i(txndata_mosi), .txndata_o(txndata_miso)
    );

    //qspi_ctrl qspi_ctrl (
    qspi_ctrl_fsm qspi_ctrl (
        // general
        .reset_i(rst_i), .clk_i(clk_i),
        // spi slave
        .txnbc_o(txnbc), .txndir_o(txndir), .txndone_i(txndone),
        .txndata_o(txndata_mosi), .txndata_i(txndata_miso), .txnreset_i(!sce_i),
        // control
        .vt_mode(vt_mode_o),
        // debug
        .d_wstb(),
        // wb
        .memwb_cyc_o(memwb_cyc_o), .memwb_stb_o(memwb_stb_o), .memwb_we_o(memwb_we_o), .memwb_err_i(memwb_err_i),
        .memwb_adr_o(memwb_adr_o), .memwb_dat_o(memwb_dat_o), .memwb_ack_i(memwb_ack_i), .memwb_stall_i(memwb_stall_i),
        .memwb_dat_i(memwb_dat_i),
        // cfg wb
        .cfgwb_rst_o(cfgwb_rst_o),
        .cfgwb_adr_o(cfgwb_adr_o), .cfgwb_dat_o(cfgwb_dat_o),
        .cfgwb_we_o(cfgwb_we_o), .cfgwb_stb_o(cfgwb_stb_o), .cfgwb_cyc_o(cfgwb_cyc_o),
        .cfgwb_err_i(cfgwb_err_i),
        .cfgwb_ack_i(cfgwb_ack_i), .cfgwb_dat_i(cfgwb_dat_i), .cfgwb_stall_i(cfgwb_stall_i)
    );

endmodule
