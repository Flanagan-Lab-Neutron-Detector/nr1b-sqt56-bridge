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
    reg          [7:0] cmd_q;
    reg [ADDRBITS-1:0] addr_q;
    reg [DATABITS-1:0] data_q;

    // wb control
    reg wb_req;
    // write direction
    wire cmd_is_write;

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

    // latch data
    always @(posedge clk_i)
        if (reset_i) begin
            cmd_q  <= 'b0;
            addr_q <= 'b0;
            data_q <= 'b0;
        end else if (wstb_pe) case (spi_state)
            SPI_STATE_CMD:        cmd_q  <= txndata_i[7:0];
            SPI_STATE_ADDR:       addr_q <= txndata_i[ADDRBITS-1:0];
            SPI_STATE_WRITE_DATA: data_q <= txndata_i[DATABITS-1:0];
            default:;
        endcase

    // request generation
    always @(posedge clk_i) begin
        wb_req <= 'b0;
        if (!cmd_is_write && ((spi_state == SPI_STATE_READ_DATA) || (spi_state == SPI_STATE_STALL)) && !txnreset_sync) begin
            wb_req <= 'b1;
        end else if (wstb_pe) case (spi_state)
            SPI_STATE_ADDR: case (cmd_q)
                `SPI_COMMAND_READ:       wb_req <= 1'b1;
                `SPI_COMMAND_FAST_READ:  wb_req <= 1'b1;
                default:                 wb_req <= 1'b0;
            endcase
            SPI_STATE_WRITE_DATA:        wb_req <= 1'b1;
            default:                     wb_req <= 1'b0;
        endcase
    end

    // request write status
    assign cmd_is_write = !((cmd_q == `SPI_COMMAND_READ) || (cmd_q == `SPI_COMMAND_FAST_READ));

    // VT override control
    always @(posedge clk_i)
        if (reset_i)
            vt_mode <= 1'b0;
        else if (txnreset_sync) begin
            if (cmd_q == `SPI_COMMAND_DET_VT)
                vt_mode <= 1'b1;
            else if (cmd_q == `SPI_COMMAND_RESET)
                vt_mode <= 1'b0;
        end

    // Wishbone control

    reg wb_done;
    always @(posedge clk_i) begin
        wb_stb_o <= 'b0;
        if (reset_i) begin
            wb_cyc_o  <= 'b0;
            wb_we_o   <= 'b0;
            wb_adr_o  <= 'b0;
            wb_dat_o  <= 'b0;
            //txndata_o <= 'b0;
            wb_done   <= 'b0;
        end else begin
            if (wb_cyc_o && wb_ack_i) begin
                wb_done   <= 'b1;
                wb_cyc_o  <= 'b0;
                if (!wb_we_o) begin
                    txndata_o[DATABITS-1:0] <= wb_dat_i;
                    // leftover bits set to zero
                    txndata_o[IOREG_BITS-1:DATABITS] <= 'b0;
                end
            end

            if (wb_req && !wb_done && !wb_stall_i) begin
                wb_cyc_o <= 'b1;
                wb_stb_o <= 'b1;
                wb_adr_o <= addr_q;
                wb_we_o  <= cmd_is_write;
                wb_dat_o <= data_q;
            //end else if (wb_cyc_o) begin
            end else if (txnreset_sync) begin
                wb_cyc_o <= 'b0;
                wb_we_o  <= 'b0;
                wb_adr_o <= 'b0;
                wb_dat_o <= 'b0;
                wb_done  <= 'b0;
            end
        end
    end

endmodule
