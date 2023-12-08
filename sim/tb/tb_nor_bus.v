/** tb_top.v
 *
 * Top-level testbench wrapper for cocotb
 *
 */

`default_nettype none
`timescale 1ns/100ps

module tb_nor_bus (
    input rst_i, clk_i,

    input  [25:0] wb_adr_i,
    input  [15:0] wb_dat_i,
    input         wb_we_i, wb_stb_i, wb_cyc_i,
    output        wb_ack_o,
    output [15:0] wb_dat_o,
    output        wb_stall_o,
    output        wb_err_o,

    input         nor_ry_i,
    input  [15:0] nor_data_i,
    output [15:0] nor_data_o,
    output [25:0] nor_addr_o,
    output        nor_ce_o, nor_we_o, nor_oe_o, nor_data_oe
);

`ifdef VERILATOR
    initial begin
        $dumpfile ("tb_nor_bus.vcd");
        //$dumpvars (0, tb_nor_bus);
    end
`else
    // dumps the trace to a vcd file that can be viewed with GTKWave
    //integer i;
    initial begin
        $dumpfile ("tb_nor_bus.vcd");
        $dumpvars (0, tb_nor_bus);
        //$dumpvars (1, norbus.req_data[95:48]);
        //$dumpvars (1, norbus.req_data[47:0]);
        //$dumpvars (1, norbus.req_dv[0]);
        //$dumpvars (1, norbus.req_dv[1]);
        //$dumpvars (1, norbus.request_fifo.mem[0]);
        //$dumpvars (1, norbus.request_fifo.mem[1]);
        //$dumpvars (1, norbus.request_fifo.mem[2]);
        //$dumpvars (1, norbus.request_fifo.mem[3]);
        //for (i = 0; i < 4; i = i + 1)
        //$dumpvars(1, tt2.cfg_buf[i]);
        #1;
    end
`endif // VERILATOR

    nor_bus #(.ADDRBITS(26), .DATABITS(16)) norbus (
        .wb_rst_i(rst_i), .wb_clk_i(clk_i),
        .wb_adr_i(wb_adr_i), .wb_dat_i(wb_dat_i),
        .wb_we_i(wb_we_i), .wb_stb_i(wb_stb_i), .wb_cyc_i(wb_cyc_i),
        .wb_err_o(wb_err_o),
        .wb_ack_o(wb_ack_o), .wb_dat_o(wb_dat_o), .wb_stall_o(wb_stall_o),

        .nor_ry_i(nor_ry_i), .nor_data_i(nor_data_i),
        .nor_data_o(nor_data_o), .nor_addr_o(nor_addr_o),
        .nor_ce_o(nor_ce_o), .nor_we_o(nor_we_o), .nor_oe_o(nor_oe_o),
        .nor_data_oe(nor_data_oe)
    );

endmodule
