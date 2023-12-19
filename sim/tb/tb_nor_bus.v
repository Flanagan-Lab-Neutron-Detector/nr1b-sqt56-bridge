/** tb_top.v
 *
 * Top-level testbench wrapper for cocotb
 *
 */

`default_nettype none
`timescale 1ns/100ps

module tb_nor_bus (
    input rst_i, clk_i,

    input      [25:0] memwb_adr_i,
    input      [15:0] memwb_dat_i,
    input             memwb_we_i, memwb_stb_i, memwb_cyc_i,
    output            memwb_ack_o,
    output     [15:0] memwb_dat_o,
    output            memwb_stall_o,
    output            memwb_err_o,

    // cfg wishbone interface
    input             cfgwb_rst_i,
    input      [15:0] cfgwb_adr_i,
    input      [15:0] cfgwb_dat_i,
    input             cfgwb_we_i,
    input             cfgwb_stb_i,
    input             cfgwb_cyc_i,
    output            cfgwb_err_o,
    output reg        cfgwb_ack_o,
    output reg [15:0] cfgwb_dat_o,
    output            cfgwb_stall_o,

    input             nor_ry_i,
    input      [15:0] nor_data_i,
    output     [15:0] nor_data_o,
    output     [25:0] nor_addr_o,
    output            nor_ce_o, nor_we_o, nor_oe_o, nor_data_oe
);

    // dumps the trace to a vcd file that can be viewed with GTKWave
    //integer i;
    initial begin
        $dumpfile ("tb_nor_bus.vcd");
`ifndef VERILATOR
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
`endif // !defined(VERILATOR)
    end

    nor_bus norbus (
        // system
        .sys_rst_i(rst_i), .sys_clk_i(clk_i),
        // mem wb
        .memwb_rst_i(rst_i),
        .memwb_adr_i(memwb_adr_i), .memwb_dat_i(memwb_dat_i),
        .memwb_we_i(memwb_we_i), .memwb_stb_i(memwb_stb_i), .memwb_cyc_i(memwb_cyc_i),
        .memwb_err_o(memwb_err_o),
        .memwb_ack_o(memwb_ack_o), .memwb_dat_o(memwb_dat_o), .memwb_stall_o(memwb_stall_o),
        // cfg wb
        .cfgwb_rst_i(cfgwb_rst_i),
        .cfgwb_adr_i(cfgwb_adr_i), .cfgwb_dat_i(cfgwb_dat_i),
        .cfgwb_we_i(cfgwb_we_i), .cfgwb_stb_i(cfgwb_stb_i), .cfgwb_cyc_i(cfgwb_cyc_i),
        .cfgwb_err_o(cfgwb_err_o),
        .cfgwb_ack_o(cfgwb_ack_o), .cfgwb_dat_o(cfgwb_dat_o), .cfgwb_stall_o(cfgwb_stall_o),
        // nor
        .nor_ry_i(nor_ry_i), .nor_data_i(nor_data_i),
        .nor_data_o(nor_data_o), .nor_addr_o(nor_addr_o),
        .nor_ce_o(nor_ce_o), .nor_we_o(nor_we_o), .nor_oe_o(nor_oe_o),
        .nor_data_oe(nor_data_oe)
    );

endmodule
