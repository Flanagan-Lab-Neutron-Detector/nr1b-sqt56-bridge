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

    // wb bus interface + NOR state machine
    wire mod_reset;
    assign mod_reset = wb_rst_i || !wb_cyc_i || wb_err_o;

    assign wb_err_o = 'b0;

    wire fifo_full, fifo_empty, fifo_write;
    reg  fifo_read;
    wire [47:0] fifo_data_in;
    reg  [47:0] fifo_data_out;

    assign fifo_write = wb_cyc_i && wb_stb_i && !wb_stall_o;
    assign fifo_data_in = { {(48-ADDRBITS-DATABITS-1){1'b0}}, wb_we_i, wb_dat_i, wb_adr_i };

    fsfifo #(.WIDTH(48), .DEPTH(32)) request_fifo (
        .clk_i(wb_clk_i), .reset_i(mod_reset),
        .full_o(fifo_full), .empty_o(fifo_empty),
        .wr_i(fifo_write), .wr_data_i(fifo_data_in),
        .rd_i(fifo_read), .rd_data_o(fifo_data_out)
    );

    //assign fifo_read = !nor_stall && !fifo_empty;
    wire [ADDRBITS-1:0] req_adr;
    wire [DATABITS-1:0] req_dat;
    wire                req_we;
    reg                 nor_req;
    assign { req_we, req_dat, req_adr } = fifo_data_out[(ADDRBITS+DATABITS+1)-1:0];

    localparam [1:0] REQ_IDLE = 2'b00,
                     REQ_READ = 2'b01,
                     REQ_HOLD = 2'b10;
    reg [1:0] req_state, req_state_next;

    always @(*) case(req_state)
        REQ_IDLE: req_state_next = !fifo_empty                          ? REQ_READ : REQ_IDLE;
        REQ_READ: req_state_next = (nor_stall || (!nor_ry_i && req_we)) ? REQ_HOLD : REQ_IDLE;
        REQ_HOLD: req_state_next = (nor_stall || (!nor_ry_i && req_we)) ? REQ_HOLD : REQ_IDLE;
        default:  req_state_next = REQ_IDLE;
    endcase

    always @(*) begin
        nor_req = 'b0;
        fifo_read = 'b0;
        case(req_state)
            REQ_IDLE: fifo_read = !fifo_empty;
            REQ_READ: nor_req = !(nor_stall || (!nor_ry_i && req_we));
            REQ_HOLD: nor_req = !(nor_stall || (!nor_ry_i && req_we));
            default: ;
        endcase
    end

    always @(posedge wb_clk_i)
        if (mod_reset)
            req_state <= REQ_IDLE;
        else
            req_state <= req_state_next;

    /*
    always @(posedge wb_clk_i) begin
        nor_req   <= 'b0;
        fifo_read <= 'b0;
        if (fifo_read) begin
            nor_req   <= 'b1;
            fifo_read <= 'b0;
        end else if (!fifo_empty && !nor_stall) begin
            nor_req   <= 'b0;
            fifo_read <= 'b1;
        end
    end
    */

    assign wb_stall_o = fifo_full;

    wire nor_stall;
    //assign wb_stall_o = nor_stall;
    //assign wb_stall_o = mod_reset ? 1'b0 : nor_stall; //!wb_ack_o && !(!nor_stall && !txn_req);

    nor_bus_driver #(.ADDRBITS(ADDRBITS), .DATABITS(DATABITS)) nor_bus_driver (
        // wb
        .rst_i(mod_reset), .clk_i(wb_clk_i), .addr_i(req_adr), .data_i(req_dat), .req_i(nor_req),
        .req_write_i(req_we), .ack_o(wb_ack_o), .data_o(wb_dat_o), .busy_o(nor_stall),
        // nor
        .nor_ry_i(nor_ry_i), .nor_data_i(nor_data_i), .nor_data_o(nor_data_o),
        .nor_addr_o(nor_addr_o), .nor_ce_o(nor_ce_o), .nor_we_o(nor_we_o),
        .nor_oe_o(nor_oe_o), .nor_data_oe(nor_data_oe)
    );

    // Formal verification
`ifdef FORMAL

    // past valid and reset
    reg f_past_valid;
    initial f_past_valid <= 1'b0;
    always @(posedge wb_clk_i)
        f_past_valid <= 1'b1;
    always @(*)
        if (!f_past_valid) assert(wb_rst_i);
    always @(posedge wb_clk_i)
        cover(f_past_valid);

    // collected reset conditions

    initial assume(wb_rst_i);
    //initial assume(!wb_err_i);
    // the master is correct
    initial assume(!wb_cyc_i);
    initial assume(!wb_stb_i);
    // and we reset correctly
    //initial assert(!wb_ack_o);
    //initial assert(!wb_err_i);

    always @(posedge wb_clk_i) begin
        if (!f_past_valid || $past(wb_rst_i)) begin
            // reset condition
            assume(!wb_err_o);
            assume(!wb_cyc_i);
            assume(!wb_stb_i);
            assume(!wb_ack_o);
        end
	end

    always @(*)
        if (!f_past_valid) assert(!wb_cyc_i);

    // Requests

    // after a bus error master should deassert cyc
    always @(posedge wb_clk_i)
        if (f_past_valid && $past(wb_err_o) && $past(wb_cyc_i))
            assume(!wb_cyc_i);

    // stb should only be asserted if cyc
    always @(*) if (wb_stb_i) assume(wb_cyc_i);

    // if there is a request on the bus and the bus is stalled, the request remains
    always @(posedge wb_clk_i) begin
        if (f_past_valid && !$past(wb_rst_i) && $past(wb_stb_i) && $past(wb_stall_o) && wb_cyc_i) begin
            assume(wb_stb_i);
            assume(wb_we_i  == $past(wb_we_i));
            assume(wb_adr_i == $past(wb_adr_i));
            //assume(wb_sel_i  == $past(wb_sel_i));
            if (wb_we_i)
                assume(wb_dat_i == $past(wb_dat_i));
        end
    end

    // within a strobe the direction does not change
	always @(posedge wb_clk_i)
        if (f_past_valid && $past(wb_stb_i) && wb_stb_i)
            assume(wb_we_i == $past(wb_we_i));

    // Responses

    // if cyc was low, then ack and err should be low
	always @(posedge wb_clk_i) begin
        if (f_past_valid && !$past(wb_cyc_i) && !wb_cyc_i) begin
            assert(!wb_ack_o);
            //assert(!wb_err_i);
        end
    end

    // should not assert both ack and err
    always @(posedge wb_clk_i) begin
        if (f_past_valid && $past(wb_err_o)) assert(!wb_ack_o);
    end

    // if cyc and stb, and ack was high, then we shold not start anything
    /*
    always @(posedge wb_clk_i) begin
        if (f_past_valid && wb_cyc_i && wb_stb_i && $past(wb_ack_o))
            assert(!wb_stall_o);
    end
    */

    always @(posedge wb_clk_i) begin
        if (f_past_valid && !wb_rst_i && !$past(wb_rst_i)) begin
            // we should receive a read
            cover(wb_stb_i && !wb_we_i);
            // we should acknowledge a read
            //wb_nor_read:  cover(!$past(txn_we) && wb_ack_o);
            wb_nor_read:  cover(!wb_we_i && wb_ack_o);

            // we should receive a write
            cover(wb_stb_i && wb_we_i);
            // we should acknowledge a write
            wb_nor_write: cover(wb_we_i && wb_ack_o);
        end
    end

`endif // FORMAL

endmodule

module nor_bus_driver #(
    parameter ADDRBITS = 26,
    parameter DATABITS = 16,
    parameter COUNTERBITS = 8
) (
    // pseudo-wishbone interface
    input                     rst_i,
    input                     clk_i,
    input      [ADDRBITS-1:0] addr_i,
    input      [DATABITS-1:0] data_i,
    input                     req_i,
    input                     req_write_i,
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

    // This is a transparent NOR bus <-> Wishbone adapter,
    // i.e. a wb read/write is translated to a flash read/write.
    // To read the flash:
    //        (set data to input)
    //     1. set up addresses
    //     2. assert ce and oe
    //     3. wait
    //     4. read data
    //     5. deassert oe and ce
    // To write to the flash:
    //        (set data to output)
    //     1. set up address
    //     2. assert ce and we
    //     3. set up data*
    //     4. wait
    //     5. deassert we and ce
    //        (set data to input)
    //        * Can probably set up data with address
    // Then we have five phases:
    //     1. SETUP        data to output if write else input, set addr, set data
    //     2. TXN_BEGIN    assert ce, assert we if write else oe
    //     3. WAIT         wait N cycles
    //     4. READ         read data
    //     5. TXN_END      deassert ce, oe, oe; set data to input
    // TODO:
    //     - more wait states
    //     - configuration registers (e.g. wait cycles)
    //     - separate nor bus widths from wb?

    // local
    reg [1:0]          state;

    localparam [1:0] NOR_TXN_BEGIN     = 2'b00,
                     NOR_WAIT          = 2'b01,
                     NOR_READ          = 2'b10,
                     NOR_TXN_END       = 2'b11;

    // wait counter
    reg [COUNTERBITS-1:0] counter;
    reg                   counter_rst;
    always @(posedge clk_i)
        if (rst_i || counter_rst)
            counter <= 'b0;
        else
            counter <= counter + 1'b1;

    localparam [COUNTERBITS-1:0] BEGIN_WAIT_COUNT = 0,
                                 WAIT_COUNT       = 12,
                                 READ_WAIT_COUNT  = 0,
                                 END_WAIT_COUNT   = 4;

    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= NOR_TXN_BEGIN;
        end else if (busy_o) begin
            counter_rst <= 'b0;
            case(state)
                NOR_TXN_BEGIN:
                    if (counter == BEGIN_WAIT_COUNT) begin
                        counter_rst <= 1'b1;
                        state       <= NOR_WAIT;
                    end
                NOR_WAIT:
                    if (counter == WAIT_COUNT) begin
                        counter_rst <= 1'b1;
                        state       <= NOR_READ;
                    end
                NOR_READ:
                    if (counter == READ_WAIT_COUNT) begin
                        counter_rst <= 1'b1;
                        state       <= NOR_TXN_END;
                    end
                NOR_TXN_END:
                    if (counter == END_WAIT_COUNT) begin
                        counter_rst <= 1'b1;
                        state       <= NOR_TXN_BEGIN;
                    end
            endcase
        end else
            counter_rst <= 'b1;
    end

    always @(*) begin
        // CE low during transaction only
        //nor_ce_o = !(busy_o && (state < NOR_TXN_END));
        // WE low during transaction only if req_write_i
        //nor_we_o = nor_ce_o || !req_write_i;
        // OE low during transaction unless req_write_i
        //nor_oe_o = nor_ce_o ||  req_write_i;
        // data to output only during a write
        nor_data_oe = !nor_we_o;
    end

    always @(posedge clk_i) begin
        if (rst_i) begin // synchronous reset
            busy_o      <= 1'b0;
            nor_data_o  <=  'b0;
            nor_addr_o  <=  'b0;
            ack_o       <= 1'b0;
            nor_ce_o <= 1'b1;
            nor_we_o <= 1'b1;
            nor_oe_o <= 1'b1;
        end else begin
            // if we are not busy, a transaction is requested, and it is a read or a write if ready
            if (req_i && !busy_o && (!req_write_i || (req_write_i && nor_ry_i))) begin
                busy_o     <= 1'b1;       // we are busy
                ack_o      <= 1'b0;
                if (req_write_i)
                    nor_data_o <= data_i; // write data
                nor_addr_o <= addr_i;
                if (req_write_i) begin
                    nor_we_o <= 1'b0;
                    nor_oe_o <= 1'b1;
                end else begin
                    nor_we_o <= 1'b1;
                    nor_oe_o <= 1'b0;
                end
            end else if (!busy_o) begin
                ack_o <= 1'b0;
            end else case(state)
                NOR_TXN_BEGIN: begin
                    nor_ce_o <= 1'b0;
                end
                NOR_READ: begin
                    if (!req_write_i)
                        data_o <= nor_data_i;
                end
                NOR_TXN_END: begin
                    nor_ce_o <= 1'b1;
                    nor_we_o <= 1'b1;
                    nor_oe_o <= 1'b1;

                    if (counter == END_WAIT_COUNT) begin
                        ack_o  <= 1'b1;
                        busy_o <= 1'b0;
                    end
                end
                default: begin
                end
            endcase
        end
    end

    // formal properties
`ifdef FORMAL

    // past valid and reset
    reg f_past_valid;
    initial f_past_valid <= 1'b0;
    always @(posedge clk_i)
        f_past_valid <= 1'b1;
    always @(*)
        if (!f_past_valid) assert(rst_i);

    // collected reset conditions

    initial assume(rst_i);
    // the master is correct
    initial assume(!req_i);

    always @(posedge clk_i) begin
        if (!f_past_valid || $past(rst_i)) begin
            // reset condition
            assume(!req_i);
            assume(!ack_o);
        end
	end

    always @(*) begin
        if (req_write_i) assume(req_i);
    end

    // NOR properties

    // reset
    always @(posedge clk_i) begin
        if (f_past_valid && $past(rst_i)) begin
            assert(nor_ce_o == 1'b1);
            assert(nor_oe_o == 1'b1);
            assert(nor_we_o == 1'b1);
            assert(nor_data_oe == 1'b0); // input
        end
    end

    // if !nor_ry_i, state should not change except to SETUP or IDLE unless after or during a reset
    //always @(posedge clk_i) begin
    //    if (f_past_valid && !$past(nor_ry_i) && !nor_ry_i)
    //        assert(rst_i || ($past(rst_i) && !rst_i) || (state == $past(state)) || state == NOR_SETUP || state == NOR_IDLE);
    //end

    // if !nor_ry_i, we shold not begin a write
    always @(posedge clk_i) begin
        if (f_past_valid && !$past(nor_ry_i) && $past(req_write_i) && $past(!busy_o)) begin
            assert(!busy_o);
        end
    end

    // never assert oe and we at the same time (active low!)
    always @(*) if (!rst_i) assert(nor_oe_o || nor_we_o);

    // read: never assert nor_data_oe
    // write: assert nor_data_oe
    always @(posedge clk_i) begin
        if (f_past_valid && !$past(rst_i) && !rst_i) begin
            if (req_i && req_write_i && busy_o && !nor_ce_o)
                assert(nor_data_oe);
            else if (req_i && busy_o && !nor_ce_o)
                assert(!nor_data_oe);
        end
    end

    always @(posedge clk_i) begin
        // we should reach each state
        if (f_past_valid && !rst_i && !$past(rst_i)) begin
            nor_bus_state_txn_begin: cover(busy_o && state == NOR_TXN_BEGIN);
            nor_bus_state_wait:      cover(busy_o && state == NOR_WAIT);
            nor_bus_state_read:      cover(busy_o && state == NOR_READ);
            nor_bus_state_txn_end:   cover(busy_o && state == NOR_TXN_END);

            // we should receive requests
            cover(!req_i && !busy_o);
            // we should assert nor_data_oe
            nor_bus_oe:   cover(!nor_data_oe);
            // we should be done at some point
            nor_bus_ack:  cover(ack_o);
            // we should be busy
            nor_bus_busy: cover(busy_o);
        end
    end
`endif

endmodule

