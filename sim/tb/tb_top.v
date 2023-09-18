/** tb_top.v
 *
 * Top-level testbench wrapper for cocotb
 *
 */

`default_nettype none
`timescale 1ns/10ps

module tb_top (
    input rst_i, clk_i,

    // QSPI interface
    input               [7:0] pad_spi_io_i,
    output              [7:0] pad_spi_io_o,
    output                    pad_spi_io_oe,
    input                     pad_spi_sck_i,
    input                     pad_spi_sce_i,

    // wishbone
    input  [31:0] wb_adr_i,
    input  [15:0] wb_dat_i,
    input         wb_we_i, wb_stb_i, wb_cyc_i,
    input         wb_err_i,
    output        wb_ack_o,
    output [15:0] wb_dat_o,
    output        wb_stall_o,

    input         nor_ry_i,
    input  [15:0] nor_data_i,
    output [15:0] nor_data_o,
    output [25:0] nor_addr_o,
    output        nor_ce_o, nor_we_o, nor_oe_o, nor_data_oe
);

`ifdef VERILATOR
    initial begin
        $dumpfile ("tb_top.vcd");
        //$dumpvars (0, tb_wb_nor_controller);
    end
`else
    // dumps the trace to a vcd file that can be viewed with GTKWave
    //integer i;
    initial begin
        $dumpfile ("tb_top.vcd");
        $dumpvars (0, tb_top);
        //for (i = 0; i < 4; i = i + 1)
        //$dumpvars(1, tt2.cfg_buf[i]);
        #1;
    end
`endif

    top top (
        .reset_i(rst_i), .clk_i(clk_i),
        // qspi
        .pad_spi_io_i(pad_spi_io_i), .pad_spi_io_o(pad_spi_io_o), .pad_spi_io_oe(pad_spi_io_oe),
        .pad_spi_sck_i(pad_spi_sck_i), .pad_spi_sce_i(pad_spi_sce_i),
        // nor
        .nor_ry_i(nor_ry_i), .nor_data_i(nor_data_i),
        .nor_data_o(nor_data_o), .nor_addr_o(nor_addr_o),
        .nor_ce_o(nor_ce_o), .nor_we_o(nor_we_o), .nor_oe_o(nor_oe_o),
        .nor_data_oe(nor_data_oe),
        // debug
        .dbg_txnmode(), .dbg_txndir(), .dbg_txndone(),
        .dbg_txnbc(), .dbg_txnmiso(), .dbg_txnmosi(),
        .dbg_wb_ctrl_ack(), .dbg_wb_nor_stb(), .dbg_vt_mode()
    );

endmodule
