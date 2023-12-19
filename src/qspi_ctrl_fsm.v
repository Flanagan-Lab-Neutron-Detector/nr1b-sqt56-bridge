/** qspi.v
 *
 * QSPI interface
 *
 */

`include "cmd_defs.vh"
`include "busmap.vh"

`default_nettype none
`timescale 1ns/10ps

module qspi_ctrl_fsm #(
    parameter MEMWBADDRBITS = `NORADDRBITS,
    parameter MEMWBDATABITS = `NORDATABITS,
    parameter CFGWBADDRBITS = `CFGWBADDRBITS,
    parameter CFGWBDATABITS = `CFGWBDATABITS,
    parameter SPICMDBITS    = `SPI_CMD_BITS,
    parameter SPIADDRBITS   = `SPI_ADDR_BITS,
    parameter SPIWAITCYCLES = `SPI_WAIT_CYC,
    parameter SPIDATABITS   = `SPI_DATA_BITS,
    parameter IOREG_BITS    = 32
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

    // memory wishbone
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

    assign cfgwb_rst_o = 'b0;
    assign cfgwb_adr_o = 'b0;
    assign cfgwb_dat_o = 'b0;
    assign cfgwb_we_o  = 'b0;
    assign cfgwb_stb_o = 'b0;
    assign cfgwb_cyc_o = 'b0;

    // Currently all commands are 8-bit, 1-lane
    // All other phases are N-bit 4-lane (quad)
    localparam CYCLE_COUNT_BITS     = 8;

    // NOTE: Most masters only operate on bytes for address and data, so
    // round up to byte boundaries
    localparam SPIADDRBITS_RND = 8 * ((SPIADDRBITS + 8 - 1)/8);
    localparam SPIDATABITS_RND = 8 * ((SPIDATABITS + 8 - 1)/8);

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
    reg     [SPICMDBITS-1:0] cmd_q;
    wire [MEMWBADDRBITS-1:0] addr_q;
    reg  [MEMWBDATABITS-1:0] data_q;

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
        txn_config_reg[0] = { SPICMDBITS[7:0],      1'b0 }; // COMMAND:    quad-SPI, input, 8 cycles
        txn_config_reg[1] = { SPIADDRBITS_RND[7:0], 1'b0 }; // ADDR:       quad-SPI, input
        txn_config_reg[2] = { 8'd4*SPIWAITCYCLES[7:0],   1'b0 }; // STALL:      quad-SPI, input, 20 cycles
        txn_config_reg[3] = { SPIDATABITS_RND[7:0], 1'b1 }; // READ DATA:  quad-SPI, output
        txn_config_reg[5] = { SPIDATABITS_RND[7:0], 1'b0 }; // WRITE DATA: quad-SPI, input
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
            SPI_STATE_WRITE_DATA: data_q <= txndata_i[SPIDATABITS-1:0];
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
    reg memwb_write_req, memwb_read_req, memwb_req;
    always @(*) memwb_req = memwb_write_req || memwb_read_req;
    // write direction
    wire cmd_is_write;
    assign cmd_is_write = !((cmd_q == `SPI_COMMAND_READ) || (cmd_q == `SPI_COMMAND_FAST_READ));

    // pipeline management
    // Ack FIFO
    wire pipe_fifo_full, pipe_fifo_empty;
    wire [4:0] pipe_fifo_filled;
    reg  pipe_fifo_wr;
    wire pipe_fifo_rd;
    reg  [MEMWBDATABITS-1:0] pipe_fifo_wr_data;
    //wire [DATABITS-1:0] pipe_fifo_rd_data;
    fsfifo #(.WIDTH(MEMWBDATABITS), .DEPTH(16)) pipe_fifo (
        .clk_i(clk_i), .reset_i(spi_reset),
        .full_o(pipe_fifo_full), .empty_o(pipe_fifo_empty),
        .filled_o(pipe_fifo_filled),
        .wr_i(pipe_fifo_wr), .wr_data_i(pipe_fifo_wr_data),
        .rd_i(pipe_fifo_rd), .rd_data_o(txndata_o[MEMWBDATABITS-1:0])
    );

    assign pipe_fifo_rd = wstb_pe;

    // Read acks go to a 16-deep FIFO. FIFO filled + pending reqs must be <= 16 or data will be lost
    reg  [4:0] pipe_inflight;
    wire [4:0] pipe_total = pipe_fifo_filled + pipe_inflight + (pipe_fifo_wr?'b1:'b0);
    wire inflight_empty = pipe_inflight == 'b0;
    wire pipeline_full = pipe_total[4];
    wire pipeline_almost_full = &pipe_total[3:0];

    // track inflight requests
    wire pipe_valid_wr = memwb_stb_o;
    wire pipe_valid_rd = memwb_ack_i && !inflight_empty;
    always @(posedge clk_i) begin
        if (spi_reset) pipe_inflight <= 'b0;
        else case ({ pipe_valid_wr, pipe_valid_rd })
            2'b01: pipe_inflight <= inflight_empty ? 'x : pipe_inflight - 1;
            2'b10: pipe_inflight <= pipeline_full  ? 'x : pipe_inflight + 1;
            default: pipe_inflight <= pipe_inflight;
        endcase
    end

    // stb control
    reg stb, stb_d;
    always @(*)             stb_d     = !reset_i && !memwb_stall_i && memwb_req;
    always @(posedge clk_i) stb      <= stb_d;
    always @(*)             memwb_stb_o  = stb && !memwb_stall_i;

    // write request generation
    always @(posedge clk_i) memwb_write_req <= wstb_pe && (spi_state == SPI_STATE_WRITE_DATA);

    // read request generation
    always @(posedge clk_i) begin
        memwb_read_req <= 'b0;
        if (!pipeline_full && !(pipeline_almost_full && (stb_d || memwb_stb_o))) begin
            if (!cmd_is_write && ((spi_state == SPI_STATE_READ_DATA) || (spi_state == SPI_STATE_STALL)) && !txnreset_sync) begin
                memwb_read_req <= 'b1;
            end else if (wstb_pe)
                // true when address phase finishes -- this will be the first pipelined read request
                memwb_read_req <= !cmd_is_write && (spi_state == SPI_STATE_ADDR);
        end
    end

    // address counter
    reg  [MEMWBADDRBITS-1:0] addr_counter;
    wire [MEMWBADDRBITS-1:0] addr_reset = 'b0;
    wire [MEMWBADDRBITS-1:0] addr_latch_val = txndata_i[MEMWBADDRBITS-1:0];
    wire addr_latch = wstb_pe && (spi_state == SPI_STATE_ADDR);
    wire addr_inc   = memwb_stb_o;
    always @(posedge clk_i)
        if (reset_i)         addr_counter <= addr_reset;
        else if (addr_latch) addr_counter <= addr_latch_val;
        else if (addr_inc)   addr_counter <= addr_counter + 'b1;
    assign addr_q = addr_counter;

    // Wishbone control

    always @(*) memwb_adr_o = addr_q;
    always @(posedge clk_i) begin
        txndata_o[IOREG_BITS-1:MEMWBDATABITS] <= 'b0;
        pipe_fifo_wr      <= 'b0;
        pipe_fifo_wr_data <= 'b0;
        memwb_we_o           <= 'b0;
        if (reset_i) begin
            memwb_cyc_o <= 'b0;
            memwb_dat_o <= 'b0;
        end else begin
            if (memwb_cyc_o && memwb_ack_i) begin
                if (inflight_empty)
                    memwb_cyc_o <= 'b0;
                pipe_fifo_wr      <= 'b1;
                pipe_fifo_wr_data <= memwb_dat_i;
            end

            if (memwb_read_req && txnreset_sync) begin
                memwb_cyc_o <= 'b0;
                memwb_dat_o <= 'b0;
            end else if (memwb_req && !memwb_stall_i) begin
                memwb_cyc_o <= 'b1;
                memwb_we_o  <= cmd_is_write;
                memwb_dat_o <= data_q;
            end
        end
    end

endmodule
