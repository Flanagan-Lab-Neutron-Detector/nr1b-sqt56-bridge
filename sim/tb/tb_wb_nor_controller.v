/** tb_wb_nor_controller.v
 *
 * Top-level testbench wrapper for cocotb
 *
 */

`default_nettype none
`timescale 1ns/100ps

module tb_wb_nor_controller (
    input rst_i, clk_i,

    // to controller
    input  [31:0] wbs_adr_i,
    input  [15:0] wbs_dat_i,
    input         wbs_we_i, wbs_stb_i, wbs_cyc_i,
    output        wbs_ack_o,
    output [15:0] wbs_dat_o,
    output        wbs_stall_o,

    // from controller
    output  [25:0] wbm_adr_o,
    output  [15:0] wbm_dat_o,
    output         wbm_we_o,
    output         wbm_stb_o,
    output         wbm_cyc_o,
    output         wbm_err_o,
    input          wbm_ack_i,
    input   [15:0] wbm_dat_i,
    input          wbm_stall_i
);
    
`ifdef VERILATOR
    initial begin
        $dumpfile ("tb_wb_nor_controller.vcd");
        //$dumpvars (0, tb_wb_nor_controller);
    end
`else
    // dumps the trace to a vcd file that can be viewed with GTKWave
    //integer i;
    initial begin
        $dumpfile ("tb_wb_nor_controller.vcd");
        $dumpvars (0, tb_wb_nor_controller);
        //for (i = 0; i < 4; i = i + 1)
        //$dumpvars(1, tt2.cfg_buf[i]);
        #1;
    end
`endif

    wb_nor_controller #(.ADDRBITS(26), .DATABITS(16)) nor_ctrl (
        .wb_rst_i(rst_i), .wb_clk_i(clk_i),

        .wbs_adr_i(wbs_adr_i), .wbs_dat_i(wbs_dat_i),
        .wbs_we_i(wbs_we_i), .wbs_stb_i(wbs_stb_i), .wbs_cyc_i(wbs_cyc_i),
        .wbs_err_i(1'b0), .wbs_ack_o(wbs_ack_o),
        .wbs_dat_o(wbs_dat_o), .wbs_stall_o(wbs_stall_o),

        .wbm_adr_o(wbm_adr_o), .wbm_dat_o(wbm_dat_o),
        .wbm_we_o(wbm_we_o), .wbm_cyc_o(wbm_cyc_o), .wbm_stb_o(wbm_stb_o),
        .wbm_err_o(wbm_err_o), .wbm_ack_i(wbm_ack_i),
        .wbm_dat_i(wbm_dat_i), .wbm_stall_i(wbm_stall_i)
    );

endmodule
