/** nor_bus.v
 *
 * Parallel NOR bus with wishbone interface.
 *
 */

`include "busmap.vh"

`default_nettype none
`timescale 1ns/100ps

module nor_bus #(
    parameter MEMWBADDRBITS = `NORADDRBITS,
    parameter MEMWBDATABITS = `NORDATABITS,
    parameter CFGWBADDRBITS = `CFGWBADDRBITS,
    parameter CFGWBDATABITS = `CFGWBDATABITS
) (
    // system
    input                          sys_rst_i,
    input                          sys_clk_i,

    // memory wishbone interface
    input                          memwb_rst_i,
    input      [MEMWBADDRBITS-1:0] memwb_adr_i,
    input      [MEMWBDATABITS-1:0] memwb_dat_i,
    input                          memwb_we_i,
    input                          memwb_stb_i,
    input                          memwb_cyc_i,
    output                         memwb_err_o,
    output reg                     memwb_ack_o,
    output reg [MEMWBDATABITS-1:0] memwb_dat_o,
    output                         memwb_stall_o,

    // cfg wishbone interface
    input                          cfgwb_rst_i,
    input      [CFGWBADDRBITS-1:0] cfgwb_adr_i,
    input      [CFGWBDATABITS-1:0] cfgwb_dat_i,
    input                          cfgwb_we_i,
    input                          cfgwb_stb_i,
    input                          cfgwb_cyc_i,
    output                         cfgwb_err_o,
    output reg                     cfgwb_ack_o,
    output reg [CFGWBDATABITS-1:0] cfgwb_dat_o,
    output                         cfgwb_stall_o,

    // NOR interface
    input                          nor_ry_i,
    input      [MEMWBDATABITS-1:0] nor_data_i,
    output reg [MEMWBDATABITS-1:0] nor_data_o,
    output reg [MEMWBADDRBITS-1:0] nor_addr_o,
    output reg                     nor_ce_o,
    output reg                     nor_we_o,
    output reg                     nor_oe_o,
    output reg                     nor_data_oe // 0 = input, 1 = output
);

    localparam REQBITS = MEMWBADDRBITS + MEMWBDATABITS + 1;

    reg cyc_read;
    always @(posedge sys_clk_i)
        if (memwb_rst_i || !memwb_cyc_i || memwb_err_o) cyc_read <= 'b0;
        else if (memwb_cyc_i && !memwb_we_i)            cyc_read <= 'b1;

    // wb bus interface + NOR state machine
    wire mod_reset;
    assign mod_reset = memwb_rst_i || (!memwb_cyc_i && cyc_read) || memwb_err_o;

    assign memwb_err_o = 'b0;

    // input queue

    reg          [1:0] req_dv;
    reg  [REQBITS-1:0] req_data1;
    reg  [REQBITS-1:0] req_data0;

    wire               queue_wr = memwb_cyc_i && memwb_stb_i;
    wire [REQBITS-1:0] queue_wr_data = { memwb_we_i, memwb_dat_i, memwb_adr_i };
    wire               queue_full, queue_empty;
    queue2 #(.WIDTH(REQBITS)) inqueue (
        .i_clk(sys_clk_i), .i_rst(mod_reset),
        .o_full(queue_full), .o_empty(queue_empty), .o_vld(req_dv),
        .i_wr(queue_wr), .i_wr_data(queue_wr_data),
        .i_rd(memwb_ack_o), .o_rd_data1(req_data1), .o_rd_data0(req_data0)
    );

    assign memwb_stall_o = queue_full;
    wire nor_stall;

    nor_bus_driver #(
        .MEMWBADDRBITS(MEMWBADDRBITS), .MEMWBDATABITS(MEMWBDATABITS),
        .CFGWBADDRBITS(CFGWBADDRBITS), .CFGWBDATABITS(CFGWBDATABITS)
    ) nor_bus_driver (
        // wb
        //.rst_i(mod_reset), .clk_i(wb_clk_i), .addr_i(req_adr), .data_i(req_dat), .req_i(nor_req),
        //.req_write_i(req_we), .ack_o(wb_ack_o), .data_o(wb_dat_o), .busy_o(nor_stall),
        .rst_i(mod_reset), .clk_i(sys_clk_i),
        .req_i(req_data0), .req_next_i(req_data1),
        .req_valid_i(req_dv),
        .ack_o(memwb_ack_o), .data_o(memwb_dat_o), .busy_o(nor_stall),
        // cfg wb
        .cfgwb_rst_i(cfgwb_rst_i),
        .cfgwb_adr_i(cfgwb_adr_i), .cfgwb_dat_i(cfgwb_dat_i),
        .cfgwb_we_i(cfgwb_we_i), .cfgwb_stb_i(cfgwb_stb_i), .cfgwb_cyc_i(cfgwb_cyc_i),
        .cfgwb_err_o(cfgwb_err_o), .cfgwb_ack_o(cfgwb_ack_o), .cfgwb_stall_o(cfgwb_stall_o),
        .cfgwb_dat_o(cfgwb_dat_o),
        // nor
        .nor_ry_i(nor_ry_i), .nor_data_i(nor_data_i), .nor_data_o(nor_data_o),
        .nor_addr_o(nor_addr_o), .nor_ce_o(nor_ce_o), .nor_we_o(nor_we_o),
        .nor_oe_o(nor_oe_o), .nor_data_oe(nor_data_oe)
    );
endmodule

module nor_bus_driver #(
    parameter MEMWBADDRBITS = `NORADDRBITS,
    parameter MEMWBDATABITS = `NORDATABITS,
    parameter CFGWBADDRBITS = `CFGWBADDRBITS,
    parameter CFGWBDATABITS = `CFGWBDATABITS,
    parameter COUNTERBITS   = 8
) (
    // pseudo-wishbone interface
    input                          rst_i,
    input                          clk_i,
    input            [REQBITS-1:0] req_i,
    input            [REQBITS-1:0] req_next_i,
    input                    [1:0] req_valid_i,
    output reg                     ack_o,
    output reg [MEMWBDATABITS-1:0] data_o,
    output reg                     busy_o,

    // cfg wishbone interface
    input                          cfgwb_rst_i,
    input      [CFGWBADDRBITS-1:0] cfgwb_adr_i,
    input      [CFGWBDATABITS-1:0] cfgwb_dat_i,
    input                          cfgwb_we_i,
    input                          cfgwb_stb_i,
    input                          cfgwb_cyc_i,
    output reg                     cfgwb_err_o,
    output reg                     cfgwb_ack_o,
    output reg [CFGWBDATABITS-1:0] cfgwb_dat_o,
    output reg                     cfgwb_stall_o,

    // NOR interface
    input                          nor_ry_i,
    input      [MEMWBDATABITS-1:0] nor_data_i,
    output reg [MEMWBDATABITS-1:0] nor_data_o,
    output reg [MEMWBADDRBITS-1:0] nor_addr_o,
    output reg                     nor_ce_o,
    output reg                     nor_we_o,
    output reg                     nor_oe_o,
    output reg                     nor_data_oe // 0 = input, 1 = output
);

    // registers
    reg [`CFGWBDATABITS-1:0] r_nbusctrl;
    reg [`CFGWBDATABITS-1:0] r_nbuswait0;
    reg [`CFGWBDATABITS-1:0] r_nbuswait1;
    // register bits
    wire       r_nbusctrl_pgen          = (r_nbusctrl  & `R_NBUSCTRL_PGEN_MASK)          >> `R_NBUSCTRL_PGEN_SHIFT;
    wire [7:0] r_nbuswait0_write_wait   = (r_nbuswait0 & `R_NBUSWAIT0_WRITE_WAIT_MASK)   >> `R_NBUSWAIT0_WRITE_WAIT_SHIFT;
    wire [7:0] r_nbuswait0_readdly_wait = (r_nbuswait0 & `R_NBUSWAIT0_READDLY_WAIT_MASK) >> `R_NBUSWAIT0_READDLY_WAIT_SHIFT;
    wire [7:0] r_nbuswait1_read_wait    = (r_nbuswait1 & `R_NBUSWAIT1_READ_WAIT_MASK)    >> `R_NBUSWAIT1_READ_WAIT_SHIFT;
    wire [7:0] r_nbuswait1_readpg_wait  = (r_nbuswait1 & `R_NBUSWAIT1_READPG_WAIT_MASK)  >> `R_NBUSWAIT1_READPG_WAIT_SHIFT;
    // cfg read/write
    wire [`CFGWBADDRBITS-1:0] cfgwb_adr_mod = cfgwb_adr_i & `CFGWBMODMASK;
    always @(posedge clk_i) begin
        cfgwb_ack_o   <= 'b0;
        cfgwb_dat_o   <= 'b0;
        cfgwb_stall_o <= 'b0;
        if (cfgwb_rst_i) begin
            // regs
            r_nbusctrl  <= `R_NBUSCTRL_RST_VAL;
            r_nbuswait0 <= `R_NBUSWAIT0_RST_VAL;
            r_nbuswait1 <= `R_NBUSWAIT1_RST_VAL;
            // wb
            cfgwb_err_o <= 'b0;
        end if (cfgwb_cyc_i && cfgwb_stb_i) begin
            if (cfgwb_adr_mod == `NBUSADDRBASE) begin
                cfgwb_ack_o <= 'b1;
                if (cfgwb_we_i) begin
                    case (cfgwb_adr_i)
                        `R_NBUSCTRL:  r_nbusctrl  <= cfgwb_dat_i;
                        `R_NBUSWAIT0: r_nbuswait0 <= cfgwb_dat_i;
                        `R_NBUSWAIT1: r_nbuswait1 <= cfgwb_dat_i;
                        default:      cfgwb_err_o <= 'b1;
                    endcase
                end else begin
                    case (cfgwb_adr_i)
                        `R_NBUSCTRL:  cfgwb_dat_o <= r_nbusctrl;
                        `R_NBUSWAIT0: cfgwb_dat_o <= r_nbuswait0;
                        `R_NBUSWAIT1: cfgwb_dat_o <= r_nbuswait1;
                        default:      cfgwb_err_o <= 'b1;
                    endcase
                end
            end else begin
                cfgwb_err_o <= 'b1;
            end
        end
    end

    // unpack reqs
    localparam REQBITS = MEMWBADDRBITS + MEMWBDATABITS + 1;
    wire                     req_we;
    wire [MEMWBADDRBITS-1:0] req_addr;
    wire [MEMWBDATABITS-1:0] req_data;
    assign { req_we, req_data, req_addr } = req_i;
    wire                     req_next_we;
    wire [MEMWBADDRBITS-1:0] req_next_addr;
    wire [MEMWBDATABITS-1:0] req_next_data;
    assign { req_next_we, req_next_data, req_next_addr } = req_next_i;

    // transaction chaining logic
    // Reads may be chained. CE and OE are asserted throughout, only address changes.
    // Writes are never chained. Reads and writes are never chained.
    wire [MEMWBADDRBITS-1:0] req_addr_pg      = req_addr      >> 3;
    wire [MEMWBADDRBITS-1:0] req_next_addr_pg = req_next_addr >> 3;
    wire next_read = req_valid_i[1] && !req_next_we && !req_we;
    wire next_read_page = next_read && (req_addr_pg == req_next_addr_pg);

    // local
    reg [2:0] state, next_state;

    localparam [2:0] NOR_IDLE    = 3'b000,
                     NOR_WRITE   = 3'b001,
                     NOR_READDLY = 3'b010,
                     NOR_READ    = 3'b011,
                     NOR_READPG  = 3'b100,
                     NOR_TXN_END = 3'b101;

    localparam [COUNTERBITS-1:0] END_WAIT_COUNT   = 0;

    // wait counter
    reg [COUNTERBITS-1:0] counter;
    reg                   counter_rst;
    reg                   counter_stb;
    // counter
    always @(posedge clk_i)
        if (rst_i || counter_rst)
            counter <= 'b0;
        else
            counter <= counter + 1'b1;
    always @(posedge clk_i) counter_rst <= counter_stb;
    // counter strobe
    always @(*) begin
        counter_stb = 'b1;
        if (busy_o) case(state)
            NOR_WRITE:   counter_stb = counter == r_nbuswait0_write_wait;
            NOR_READDLY: counter_stb = counter == r_nbuswait0_readdly_wait;
            NOR_READ:    counter_stb = counter == r_nbuswait1_read_wait;
            NOR_READPG:  counter_stb = counter == r_nbuswait1_readpg_wait;
            NOR_TXN_END: counter_stb = counter == END_WAIT_COUNT;
            default:     counter_stb = 'b1;
        endcase
    end

    always @(*) case(state)
        NOR_IDLE:    next_state = req_valid_i[0] ? (req_we         ? NOR_WRITE  : NOR_READDLY) : NOR_IDLE;
        NOR_WRITE:   next_state = NOR_TXN_END;
        NOR_READDLY: next_state = NOR_READ;
        NOR_READ:    next_state = next_read      ? (next_read_page ? NOR_READPG : NOR_READ)    : NOR_TXN_END;
        NOR_READPG:  next_state = next_read      ? (next_read_page ? NOR_READPG : NOR_READ)    : NOR_TXN_END;
        NOR_TXN_END: next_state = NOR_IDLE;
        default:     next_state = NOR_IDLE;
    endcase

    always @(posedge clk_i) begin
        if (rst_i)
            state <= NOR_IDLE;
        else if ((busy_o || req_valid_i[0]) && counter_stb)
            state <= next_state;
    end

    reg                      nor_data_oe_d, nor_ce_d, nor_we_d, nor_oe_d;
    reg                      ack_d;
    reg  [MEMWBDATABITS-1:0] data_d;
    reg  [MEMWBDATABITS-1:0] nor_data_d;
    reg  [MEMWBADDRBITS-1:0] nor_addr_d;

    always @(*) nor_data_oe_d = !nor_we_d;
    always @(*) busy_o      = state != NOR_IDLE;
    always @(*) ack_d       = counter_stb && ( (state == NOR_WRITE) || (state == NOR_READ) || (state == NOR_READPG) );
    always @(*) data_d      = nor_data_i;

    always @(*) begin
        nor_data_d = req_valid_i[0] ? req_data : 'b0;
        nor_addr_d = req_valid_i[0] ? req_addr : 'b0;
    end

    always @(*) begin
        nor_ce_d = !( (state != NOR_IDLE) && (state != NOR_TXN_END) );
        nor_we_d = !(state == NOR_WRITE);
        nor_oe_d = !( (state == NOR_READDLY) || (state == NOR_READ) || (state == NOR_READPG) );
    end

    always @(posedge clk_i) begin
        nor_data_oe <= nor_data_oe_d;
        //busy_o <= busy_d;
        ack_o <= ack_d;
        data_o <= data_d;
        nor_data_o <= nor_data_d;
        nor_addr_o <= nor_addr_d;
        nor_ce_o <= nor_ce_d;
        nor_we_o <= nor_we_d;
        nor_oe_o <= nor_oe_d;
    end

endmodule

