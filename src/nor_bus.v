/** nor_bus.v
 *
 * Parallel NOR bus with wishbone interface.
 *
 */

`default_nettype none
`timescale 1ns/100ps

module nor_bus #(
    parameter ADDRBITS = 26,
    parameter DATABITS = 16
) (
    // wishbone interface
    input                     wb_rst_i,
    input                     wb_clk_i,
    input      [ADDRBITS-1:0] wb_adr_i,
    input      [DATABITS-1:0] wb_dat_i,
    input                     wb_we_i,
    input                     wb_stb_i,
    input                     wb_cyc_i,
    output                    wb_err_o,
    output reg                wb_ack_o,
    output reg [DATABITS-1:0] wb_dat_o,
    output                    wb_stall_o,

    // NOR interface
    input                     nor_ry_i,
    input      [DATABITS-1:0] nor_data_i,
    output reg [DATABITS-1:0] nor_data_o,
    output reg [ADDRBITS-1:0] nor_addr_o,
    output reg                nor_ce_o,
    output reg                nor_we_o,
    output reg                nor_oe_o,
    output reg                nor_data_oe // 0 = input, 1 = output
);

    localparam REQBITS = ADDRBITS + DATABITS + 1;

    reg cyc_read;
    always @(posedge wb_clk_i)
        if (wb_rst_i || !wb_cyc_i || wb_err_o) cyc_read <= 'b0;
        else if (wb_cyc_i && !wb_we_i)         cyc_read <= 'b1;

    // wb bus interface + NOR state machine
    wire mod_reset;
    assign mod_reset = wb_rst_i || (!wb_cyc_i && cyc_read) || wb_err_o;

    assign wb_err_o = 'b0;

    // input queue

    reg          [1:0] req_dv;
    reg  [REQBITS-1:0] req_data1;
    reg  [REQBITS-1:0] req_data0;

    wire               queue_wr = wb_cyc_i && wb_stb_i && !nor_stall;
    wire [REQBITS-1:0] queue_wr_data = { wb_we_i, wb_dat_i, wb_adr_i };
    wire               queue_full, queue_empty;
    queue2 #(.WIDTH(REQBITS)) inqueue (
        .i_clk(wb_clk_i), .i_rst(mod_reset),
        .o_full(queue_full), .o_empty(queue_empty), .o_vld(req_dv),
        .i_wr(queue_wr), .i_wr_data(queue_wr_data),
        .i_rd(wb_ack_o), .o_rd_data1(req_data1), .o_rd_data0(req_data0)
    );

    assign wb_stall_o = queue_full || wb_stb_i;
    wire nor_stall;

    nor_bus_driver #(.ADDRBITS(ADDRBITS), .DATABITS(DATABITS)) nor_bus_driver (
        // wb
        //.rst_i(mod_reset), .clk_i(wb_clk_i), .addr_i(req_adr), .data_i(req_dat), .req_i(nor_req),
        //.req_write_i(req_we), .ack_o(wb_ack_o), .data_o(wb_dat_o), .busy_o(nor_stall),
        .rst_i(mod_reset), .clk_i(wb_clk_i),
        .req_i(req_data0), .req_next_i(req_data1),
        .req_valid_i(req_dv),
        .ack_o(wb_ack_o), .data_o(wb_dat_o), .busy_o(nor_stall),
        // nor
        .nor_ry_i(nor_ry_i), .nor_data_i(nor_data_i), .nor_data_o(nor_data_o),
        .nor_addr_o(nor_addr_o), .nor_ce_o(nor_ce_o), .nor_we_o(nor_we_o),
        .nor_oe_o(nor_oe_o), .nor_data_oe(nor_data_oe)
    );
endmodule

module nor_bus_driver #(
    parameter ADDRBITS = 26,
    parameter DATABITS = 16,
    parameter COUNTERBITS = 8
) (
    // pseudo-wishbone interface
    input                     rst_i,
    input                     clk_i,
    input       [REQBITS-1:0] req_i,
    input       [REQBITS-1:0] req_next_i,
    input               [1:0] req_valid_i,
    output reg                ack_o,
    output reg [DATABITS-1:0] data_o,
    output reg                busy_o,

    // NOR interface
    input                     nor_ry_i,
    input      [DATABITS-1:0] nor_data_i,
    output reg [DATABITS-1:0] nor_data_o,
    output reg [ADDRBITS-1:0] nor_addr_o,
    output reg                nor_ce_o,
    output reg                nor_we_o,
    output reg                nor_oe_o,
    output reg                nor_data_oe // 0 = input, 1 = output
);

    localparam REQBITS = ADDRBITS + DATABITS + 1;

    // unpack reqs
    wire                req_we;
    wire [ADDRBITS-1:0] req_addr;
    wire [DATABITS-1:0] req_data;
    assign { req_we, req_data, req_addr } = req_i;
    wire                req_next_we;
    wire [ADDRBITS-1:0] req_next_addr;
    wire [DATABITS-1:0] req_next_data;
    assign { req_next_we, req_next_data, req_next_addr } = req_next_i;

    // local
    reg [2:0] state, next_state;

    localparam [2:0] NOR_IDLE    = 3'b000,
                     NOR_WRITE   = 3'b001,
                     NOR_READDLY = 3'b010,
                     NOR_READ    = 3'b011,
                     NOR_READPG  = 3'b100,
                     NOR_TXN_END = 3'b101;

    localparam [COUNTERBITS-1:0] WRITE_WAIT_COUNT   = 5,
                                 READDLY_WAIT_COUNT = 25,
                                 READ_WAIT_COUNT    = 15,
                                 READPG_WAIT_COUNT  = 6,
                                 END_WAIT_COUNT     = 0;

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
            NOR_WRITE:   counter_stb = counter == WRITE_WAIT_COUNT;
            NOR_READDLY: counter_stb = counter == READDLY_WAIT_COUNT;
            NOR_READ:    counter_stb = counter == READ_WAIT_COUNT;
            NOR_READPG:  counter_stb = counter == READPG_WAIT_COUNT;
            NOR_TXN_END: counter_stb = counter == END_WAIT_COUNT;
            default:     counter_stb = 'b1;
        endcase
    end

    always @(*) case(state)
        NOR_IDLE:    next_state = req_valid_i[0] ? (req_we ? NOR_WRITE : NOR_READDLY) : NOR_IDLE;
        NOR_WRITE:   next_state = NOR_TXN_END;
        NOR_READDLY: next_state = NOR_READ;
        NOR_READ:    next_state = NOR_TXN_END;
        NOR_READPG:  next_state = NOR_TXN_END;
        NOR_TXN_END: next_state = NOR_IDLE;
        default:     next_state = NOR_IDLE;
    endcase

    always @(posedge clk_i) begin
        if (rst_i)
            state <= NOR_IDLE;
        else if ((busy_o || req_valid_i[0]) && counter_stb)
            state <= next_state;
    end

    always @(*) begin
        nor_data_oe = !nor_we_o;
    end

    always @(posedge clk_i) begin
        ack_o <= 'b0;
        if (rst_i) begin // synchronous reset
            busy_o     <= 'b0;
            nor_data_o <= 'b0;
            nor_addr_o <= 'b0;
            nor_ce_o   <= 'b1;
            nor_we_o   <= 'b1;
            nor_oe_o   <= 'b1;
            data_o     <= 'b0;
        end else begin
            // if we are not busy, a transaction is requested, and it is a read or a write if ready
            if (req_valid_i[0] && !busy_o && (!req_we || nor_ry_i)) begin
                busy_o     <= 'b1;    // we are busy
                nor_data_o <= req_data; // write data
                nor_addr_o <= req_addr;
                //if (req_we) begin
                //    nor_we_o <= 1'b0;
                //    nor_oe_o <= 1'b1;
                //end else begin
                //    nor_we_o <= 1'b1;
                //    nor_oe_o <= 1'b0;
                //end
            end else if (busy_o) begin
                nor_ce_o <= 1'b0;
                nor_we_o <= !req_we;
                nor_oe_o <=  req_we;
                case(state)
                    NOR_WRITE: begin
                        if (counter_stb) begin
                            ack_o <= 1'b1;
                        end
                    end
                    NOR_READDLY: ;
                    NOR_READ, NOR_READPG: begin
                        if (counter_stb) begin
                            data_o <= nor_data_i;
                            ack_o <= 1'b1;
                        end
                    end
                    NOR_TXN_END: begin
                        if (counter_stb) begin
                            busy_o <= 1'b0;
                            nor_ce_o <= 'b1;
                            nor_we_o <= 'b1;
                            nor_oe_o <= 'b1;
                        end
                    end
                    default: begin
                        ack_o    <= 'b1;
                        busy_o   <= 'b0;
                        nor_ce_o <= 'b1;
                        nor_we_o <= 'b1;
                        nor_oe_o <= 'b1;
                    end
                endcase
            end
        end
    end

endmodule

