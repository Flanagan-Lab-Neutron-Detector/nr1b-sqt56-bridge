/** qspi.v
 *
 * QSPI interface
 *
 */

`default_nettype none
`timescale 1ns/10ps

`include "cmd_defs.vh"

module qspi_ctrl_fsm #(
    parameter ADDRBITS = 26,
    parameter DATABITS = 16,
    parameter IOREG_BITS = 32
) (
    input reset_i, // synchronous to local clock
    input clk_i, // local clock

    // data inputs
    output     [CYCLE_COUNT_BITS-1:0] txnbc_o,   // transaction bit count
    output                            txndir_o,  // transaction direction, 0 = read, 1 = write
    output reg       [IOREG_BITS-1:0] txndata_o,
    input            [IOREG_BITS-1:0] txndata_i,
    input                             txndone_i, // high for one cycle when data has been received
    input                             txnreset_i, // transaction reset (CE high)

    // controller requests
    output reg                        vt_mode,
    // debug
    output                            d_wstb,

    // wishbone
    output reg                        wb_cyc_o,
    output reg                        wb_stb_o,
    output reg                        wb_we_o,
    output reg         [ADDRBITS-1:0] wb_adr_o,
    output reg         [DATABITS-1:0] wb_dat_o,
    input                             wb_err_i,
    input                             wb_ack_i,
    input                             wb_stall_i,
    input              [DATABITS-1:0] wb_dat_i
);

    // Currently all commands are 8-bit, 1-lane
    // All other phases are N-bit 4-lane (quad)
    localparam CYCLE_COUNT_BITS     = 8;

    // NOTE: Most masters only operate on bytes for address and data, so
    // round up to byte boundaries
    localparam ADDRBITS_RND = 8 * ((ADDRBITS + 8 - 1)/8);
    localparam DATABITS_RND = 8 * ((DATABITS + 8 - 1)/8);

    localparam [2:0] SPI_STATE_CMD        = 3'h0,
                     SPI_STATE_ADDR       = 3'h1,
                     SPI_STATE_STALL      = 3'h2,
                     SPI_STATE_READ_DATA  = 3'h3,
                     SPI_STATE_WRITE_DATA = 3'h5;

    // synchronize SPI -> sys
    wire wstb, wstb_pe;
    wire txnreset_sync;

    // spi reset
    wire spi_reset;
    assign spi_reset = reset_i || txnreset_sync;

    // SPI state
    reg [2:0] spi_state_next;
    reg [2:0] spi_state;

    // latched command words
    reg           [7:0] cmd_q;
    wire [ADDRBITS-1:0] addr_q;
    reg  [DATABITS-1:0] data_q;

    // { [CYCLE_COUNT_BITS+1-1:3]=bit_count, [0]=dir }
    reg [CYCLE_COUNT_BITS+1-1:0] txn_config_reg[8];
    assign { txnbc_o, txndir_o } = txn_config_reg[spi_state];
    // initialize config reg
    integer i;
    initial begin
        // pre-init to command
        for (i = 0; i < 8; i = i + 1) begin
            txn_config_reg[i] = { 8'h08, 1'b0 }; // COMMAND: quad-SPI, input, 8 bits
        end
        txn_config_reg[0] = { 8'h08,             1'b0 }; // COMMAND:    quad-SPI, input, 8 cycles
        txn_config_reg[1] = { ADDRBITS_RND[7:0], 1'b0 }; // ADDR:       quad-SPI, input
        txn_config_reg[2] = { 8'h50,             1'b0 }; // STALL:      quad-SPI, input, 20 cycles
        txn_config_reg[3] = { DATABITS_RND[7:0], 1'b1 }; // READ DATA:  quad-SPI, output
        txn_config_reg[5] = { DATABITS_RND[7:0], 1'b0 }; // WRITE DATA: quad-SPI, input
    end

    // synchronize to txndone rising edge (word strobe)
    sync2pse sync_wstb (
        .clk(clk_i), .rst(reset_i),
        .d(txndone_i), .q(wstb),
        .pe(wstb_pe), .ne()
    );
    assign d_wstb = wstb_pe;

    // sync txnreset (ce deassertion) to sys domain
    // reset value should be 1
    sync2ps #(.R(1)) sync_txnreset (.clk(clk_i), .rst(reset_i), .d(txnreset_i), .q(txnreset_sync));

    // QSPI state changes
    always @(*) begin
        case (spi_state)
            SPI_STATE_CMD: case(cmd_q)
                default:                 spi_state_next = SPI_STATE_ADDR;
            endcase
            SPI_STATE_ADDR: case (cmd_q)
                `SPI_COMMAND_READ:       spi_state_next = SPI_STATE_READ_DATA;
                `SPI_COMMAND_FAST_READ:  spi_state_next = SPI_STATE_STALL;
                `SPI_COMMAND_WRITE_THRU: spi_state_next = SPI_STATE_WRITE_DATA;
                default:                 spi_state_next = SPI_STATE_CMD;
            endcase
            SPI_STATE_STALL:             spi_state_next = SPI_STATE_READ_DATA;
            SPI_STATE_READ_DATA:         spi_state_next = SPI_STATE_READ_DATA; // continuous reads
            SPI_STATE_WRITE_DATA:        spi_state_next = SPI_STATE_ADDR;      // continuous writes
            default:                     spi_state_next = 3'bxxx;
        endcase
    end
    always @(posedge clk_i) begin
        if (spi_reset)    spi_state <= SPI_STATE_CMD;
        else if (wstb_pe) spi_state <= spi_state_next;
    end

    // latch command and data (address latched by addr counter)
    always @(posedge clk_i)
        if (reset_i) begin
            cmd_q  <= 'b0;
            //addr_q <= 'b0;
            data_q <= 'b0;
        end else if (wstb_pe) begin case (spi_state)
            SPI_STATE_CMD:        cmd_q  <= txndata_i[7:0];
            //SPI_STATE_ADDR:       addr_q <= txndata_i[ADDRBITS-1:0];
            SPI_STATE_WRITE_DATA: data_q <= txndata_i[DATABITS-1:0];
            default:;
        endcase end

    // VT override control
    always @(posedge clk_i)
        if (reset_i)
            vt_mode <= 1'b0;
        else if (txnreset_sync) begin
            if (cmd_q == `SPI_COMMAND_DET_VT)
                vt_mode <= 1'b1;
            //else if (cmd_q == `SPI_COMMAND_RESET)
            else if (cmd_q == `SPI_COMMAND_WRITE_THRU && data_q == 16'h00F0)
                vt_mode <= 1'b0;
        end

    // (wb) read/write request generation

    // wb control
    reg wb_write_req, wb_read_req, wb_req;
    always @(*) wb_req = wb_write_req || wb_read_req;
    // write direction
    wire cmd_is_write;
    assign cmd_is_write = !((cmd_q == `SPI_COMMAND_READ) || (cmd_q == `SPI_COMMAND_FAST_READ));

    // pipeline management
    // Ack FIFO
    wire pipe_fifo_full, pipe_fifo_empty;
    wire [4:0] pipe_fifo_filled;
    reg  pipe_fifo_wr;
    wire pipe_fifo_rd;
    reg  [DATABITS-1:0] pipe_fifo_wr_data;
    //wire [DATABITS-1:0] pipe_fifo_rd_data;
    fsfifo #(.WIDTH(DATABITS), .DEPTH(16)) pipe_fifo (
        .clk_i(clk_i), .reset_i(spi_reset),
        .full_o(pipe_fifo_full), .empty_o(pipe_fifo_empty),
        .filled_o(pipe_fifo_filled),
        .wr_i(pipe_fifo_wr), .wr_data_i(pipe_fifo_wr_data),
        .rd_i(pipe_fifo_rd), .rd_data_o(txndata_o[DATABITS-1:0])
    );

    assign pipe_fifo_rd = wstb_pe;

    // Read acks go to a 16-deep FIFO. FIFO filled + pending reqs must be <= 16 or data will be lost
    reg  [4:0] pipe_inflight;
    wire [4:0] pipe_total = pipe_fifo_filled + pipe_inflight;
    wire inflight_empty = pipe_inflight == 'b0;
    wire pipeline_full = pipe_total[4];

    // track inflight requests
    wire pipe_valid_wr = wb_stb_o;
    wire pipe_valid_rd = wb_ack_i && !inflight_empty;
    always @(posedge clk_i) begin
        if (spi_reset) pipe_inflight <= 'b0;
        else case ({ pipe_valid_wr, pipe_valid_rd })
            2'b01: pipe_inflight <= inflight_empty ? 'x : pipe_inflight - 1;
            2'b10: pipe_inflight <= pipeline_full  ? 'x : pipe_inflight + 1;
            default: pipe_inflight <= pipe_inflight;
        endcase
    end

    // write request generation
    always @(posedge clk_i) wb_write_req <= wstb_pe && (spi_state == SPI_STATE_WRITE_DATA);

    // read request generation
    always @(posedge clk_i) begin
        wb_read_req <= 'b0;
        if (!pipeline_full) begin
            if (!cmd_is_write && ((spi_state == SPI_STATE_READ_DATA) || (spi_state == SPI_STATE_STALL)) && !txnreset_sync) begin
                wb_read_req <= 'b1;
            end else if (wstb_pe)
                // true when address phase finishes -- this will be the first pipelined read request
                wb_read_req <= !cmd_is_write && (spi_state == SPI_STATE_ADDR);
        end
    end

    // stb control
    reg stb_d;
    always @(posedge clk_i) stb_d <= !reset_i && !wb_stall_i && wb_req;
    always @(*)             wb_stb_o = stb_d && !wb_stall_i;

    // address counter
    reg  [ADDRBITS-1:0] addr_counter;
    wire [ADDRBITS-1:0] addr_reset = 'b0;
    wire [ADDRBITS-1:0] addr_latch_val = txndata_i[ADDRBITS-1:0];
    wire addr_latch = wstb_pe && (spi_state == SPI_STATE_ADDR);
    wire addr_inc   = wb_stb_o;
    always @(posedge clk_i)
        if (reset_i)         addr_counter <= addr_reset;
        else if (addr_latch) addr_counter <= addr_latch_val;
        else if (addr_inc)   addr_counter <= addr_counter + 'b1;
    assign addr_q = addr_counter;

    // Wishbone control

    always @(*) wb_adr_o = addr_q;
    always @(posedge clk_i) begin
        txndata_o[IOREG_BITS-1:DATABITS] <= 'b0;
        pipe_fifo_wr      <= 'b0;
        pipe_fifo_wr_data <= 'b0;
        wb_we_o           <= 'b0;
        if (reset_i) begin
            wb_cyc_o <= 'b0;
            wb_dat_o <= 'b0;
        end else begin
            if (wb_cyc_o && wb_ack_i) begin
                if (inflight_empty)
                    wb_cyc_o <= 'b0;
                pipe_fifo_wr      <= 'b1;
                pipe_fifo_wr_data <= wb_dat_i;
            end

            if (wb_read_req && txnreset_sync) begin
                wb_cyc_o <= 'b0;
                wb_dat_o <= 'b0;
            end else if (wb_req && !wb_stall_i) begin
                wb_cyc_o <= 'b1;
                wb_we_o  <= cmd_is_write;
                wb_dat_o <= data_q;
            end
        end
    end

endmodule
