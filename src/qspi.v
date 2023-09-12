/** qspi.v
 *
 * QSPI interface
 *
 */

`default_nettype none
`timescale 1ns/10ps

`include "cmd_defs.v"

module qspi_ctrl_fsm #(
    parameter ADDRBITS = 26,
    parameter DATABITS = 16,
    parameter IOREG_BITS = 32
) (
    input reset_i, // synchronous to local clock
    input clk_i, // local clock

    // data inputs
    output     [CYCLE_COUNT_BITS-1:0] txnbc_o,   // transaction bit count
    output                      [1:0] txnmode_o, // transaction mode, 00 = single SPI, 01 = dual SPI, 10 = quad SPI, 11 = octo SPI
    output                            txndir_o,  // transaction direction, 0 = read, 1 = write
    output           [IOREG_BITS-1:0] txndata_o,
    input            [IOREG_BITS-1:0] txndata_i,
    input                             txndone_i, // high for one cycle when data has been received
    input                             txnreset_i, // transaction reset (CE high)

    // controller requests
    output reg                        vt_mode,

    // wishbone
    output reg                        wb_cyc_o,
    output reg                        wb_stb_o,
    output reg                        wb_we_o,
    output reg                        wb_err_o,
    output reg                 [31:0] wb_adr_o,
    output reg         [DATABITS-1:0] wb_dat_o,
    input                             wb_ack_i,
    input                             wb_stall_i,
    input              [DATABITS-1:0] wb_dat_i
);

    // Currently all commands are 8-bit, 1-lane
    // All other phases are N-bit 4-lane (quad)
    localparam CYCLE_COUNT_BITS     = 6;

    // NOTE: Most masters only operate on bytes for address and data, so
    // round up to byte boundaries
    localparam ADDRBITS_RND = 8 * ((ADDRBITS + 8 - 1)/8);
    localparam DATABITS_RND = 8 * ((DATABITS + 8 - 1)/8);

    localparam [2:0] SPI_STATE_CMD             = 3'h0,
                     SPI_STATE_ADDR            = 3'h1,
                     SPI_STATE_FAST_READ_STALL = 3'h2,
                     SPI_STATE_READ_DATA       = 3'h3,
                     SPI_STATE_PROG_WORD_DATA  = 3'h4,
                     SPI_STATE_WRITE_THRU_DATA = 3'h5,
                     SPI_STATE_LOOPBACK_DATA   = 3'h6,
                     SPI_STATE_PAGE_PROG_DATA  = 3'h7;

    // spi reset
    wire spi_reset;
    assign spi_reset = reset_i || txnreset_i;

    // SPI state
    reg [2:0] spi_state_next;
    reg [2:0] spi_state;

    // latched command words
    reg          [7:0] cmd_in;
    reg [ADDRBITS-1:0] addr_q;
    reg [DATABITS-1:0] data_q;

    // wb control and sync
    reg wb_req_d; // wb sync signal
    // reduce data width (e.g. from 32bits to 24)
    // cmd is txndata_i[7:0] on command cycle since cmd_q has not been latched
    wire                      [7:0] cmd_q;
    assign cmd_q = (spi_state == SPI_STATE_CMD) ? txndata_i[7:0] : cmd_in[7:0];
    // NOR command is packed into the top 6 bits of address
    reg  [5:0] nor_cmd;
    wire [31:0] wb_adr_d;
    assign wb_adr_d = { nor_cmd, addr_q };
    // write direction
    wire wb_we_d;
    // WB out data
    reg [IOREG_BITS-1:0] txndata_wb;
    assign txndata_o = (cmd_in == `SPI_COMMAND_LOOPBACK) ? { {(IOREG_BITS-ADDRBITS){1'b0}}, addr_q } : txndata_wb;

    // { [CYCLE_COUNT_BITS+3-1:3]=bit_count, [2:1]=mode, [0]=dir }
    reg [CYCLE_COUNT_BITS+3-1:0] txn_config_reg[8];
    assign { txnbc_o, txnmode_o, txndir_o } = txn_config_reg[spi_state];
    // initialize config reg
    integer i;
    initial begin
        // pre-init to command
        for (i = 0; i < 8; i = i + 1) begin
            txn_config_reg[i] = { 6'h08, 2'b00, 1'b0 }; // COMMAND: single-SPI, input, 8 bits
        end
        txn_config_reg[0] = { 6'h08,             2'b00, 1'b0 }; // COMMAND:         single-SPI, input, 8 cycles
        txn_config_reg[1] = { ADDRBITS_RND[5:0], 2'b10, 1'b0 }; // ADDR:              quad-SPI, input
        txn_config_reg[2] = { 6'h14,             2'b00, 1'b0 }; // FAST READ STALL: single-SPI, input, 20 cycles
        txn_config_reg[3] = { DATABITS_RND[5:0], 2'b10, 1'b1 }; // READ DATA:         quad-SPI, output
        txn_config_reg[4] = { DATABITS_RND[5:0], 2'b10, 1'b0 }; // PROG WORD DATA:    quad-SPI, input
        txn_config_reg[5] = { DATABITS_RND[5:0], 2'b10, 1'b0 }; // WRITE THRU DATA:   quad-SPI, input
        txn_config_reg[6] = { DATABITS_RND[5:0], 2'b10, 1'b1 }; // LOOPBACK DATA:     quad-SPI, output
        txn_config_reg[7] = { DATABITS_RND[5:0], 2'b10, 1'b0 }; // PAGE PROG DATA:    quad-SPI, input
    end

    // QSPI state changes
    always @(posedge txndone_i or posedge spi_reset) begin
        if (spi_reset) begin
            spi_state <= SPI_STATE_CMD;
        end else case (spi_state)
            SPI_STATE_CMD:               spi_state <= SPI_STATE_ADDR;
            SPI_STATE_ADDR: case (cmd_q)
                `SPI_COMMAND_READ:       spi_state <= SPI_STATE_READ_DATA;
                `SPI_COMMAND_FAST_READ:  spi_state <= SPI_STATE_FAST_READ_STALL;
                `SPI_COMMAND_PROG_WORD:  spi_state <= SPI_STATE_PROG_WORD_DATA;
                `SPI_COMMAND_WRITE_THRU: spi_state <= SPI_STATE_WRITE_THRU_DATA;
                `SPI_COMMAND_LOOPBACK:   spi_state <= SPI_STATE_LOOPBACK_DATA;
                `SPI_COMMAND_PAGE_PROG:  spi_state <= SPI_STATE_PAGE_PROG_DATA;
                default:                 spi_state <= SPI_STATE_CMD;
            endcase
            SPI_STATE_FAST_READ_STALL:   spi_state <= SPI_STATE_READ_DATA;
            SPI_STATE_PAGE_PROG_DATA:    spi_state <= SPI_STATE_PAGE_PROG_DATA;
            default:                     spi_state <= SPI_STATE_CMD;
        endcase
    end

    // latch data
    always @(posedge txndone_i or posedge reset_i)
        if (reset_i) begin
            cmd_in <= 'b0;
            addr_q <= 'b0;
            data_q <= 'b0;
        end else case (spi_state)
            SPI_STATE_CMD:             cmd_in <= txndata_i[7:0];
            SPI_STATE_ADDR:            addr_q <= txndata_i[ADDRBITS-1:0];
            SPI_STATE_PROG_WORD_DATA,
            SPI_STATE_PAGE_PROG_DATA,
            SPI_STATE_WRITE_THRU_DATA: data_q <= txndata_i[DATABITS-1:0];
            default:;
        endcase

    // assign NOR command
    always @(*) case (cmd_in)
        `SPI_COMMAND_READ:       nor_cmd = `NOR_CYCLE_READ;
        `SPI_COMMAND_FAST_READ:  nor_cmd = `NOR_CYCLE_READ;
        `SPI_COMMAND_BULK_ERASE: nor_cmd = `NOR_CYCLE_ERASE_CHIP;
        `SPI_COMMAND_SECT_ERASE: nor_cmd = `NOR_CYCLE_ERASE_SECTOR;
        `SPI_COMMAND_PROG_WORD:  nor_cmd = `NOR_CYCLE_PROGRAM;
        `SPI_COMMAND_RESET:      nor_cmd = `NOR_CYCLE_RESET;
        `SPI_COMMAND_WRITE_THRU: nor_cmd = `NOR_CYCLE_WRITE;
        //`SPI_COMMAND_PAGE_PROG:  nor_cmd = `NOR_CYCLE_WRITE_BUF;
        default:                 nor_cmd = `NOR_CYCLE_RESET;
    endcase

    // request generation
    always @(posedge txndone_i or posedge reset_i)
        if (reset_i)
            wb_req_d <= 1'b0;
        else case (spi_state)
            SPI_STATE_CMD: case (cmd_q)
                `SPI_COMMAND_BULK_ERASE: wb_req_d <= 1'b1;
                `SPI_COMMAND_RESET:      wb_req_d <= 1'b1;
                `SPI_COMMAND_WRITE_THRU: wb_req_d <= 1'b1;
                default:                 wb_req_d <= 1'b0;
            endcase
            SPI_STATE_ADDR: case (cmd_q)
                `SPI_COMMAND_READ:       wb_req_d <= 1'b1;
                `SPI_COMMAND_FAST_READ:  wb_req_d <= 1'b1;
                `SPI_COMMAND_SECT_ERASE: wb_req_d <= 1'b1;
                default:                 wb_req_d <= 1'b0;
            endcase
            SPI_STATE_PROG_WORD_DATA:    wb_req_d <= 1'b1;
            SPI_STATE_WRITE_THRU_DATA:   wb_req_d <= 1'b1;
            default:                     wb_req_d <= 1'b0;
        endcase

    // request write status
    assign wb_we_d = !((cmd_q == `SPI_COMMAND_READ) || (cmd_q == `SPI_COMMAND_FAST_READ));

    // VT mode
    wire txnreset_sync;
    sync2ps sync_txnreset (.clk(clk_i), .rst(reset_i), .d(txnreset_i), .q(txnreset_sync));
    // VT override control
    always @(posedge clk_i or posedge reset_i)
        if (reset_i)
            vt_mode <= 1'b0;
        else if (txnreset_sync) begin
            if (cmd_in == `SPI_COMMAND_DET_VT)
                vt_mode <= 1'b1;
            else if (cmd_in == `SPI_COMMAND_RESET)
                vt_mode <= 1'b0;
        end

    // Wishbone control

    wire wb_req_q_posedge;
    sync2pse sync_wb_req (
        .clk(clk_i), .rst(reset_i),
        .d(wb_req_d && txndone_i), .q(),
        .pe(wb_req_q_posedge), .ne()
    );

    always @(posedge clk_i) begin
        wb_err_o <= 1'b0;
        if (reset_i) begin
            wb_cyc_o <= 'b0;
            wb_stb_o <= 'b0;
            wb_we_o  <= 'b0;
            wb_adr_o <= 'b0;
            wb_dat_o <= 'b0;
            txndata_wb <= 'b0;
        end else begin
            if (wb_req_q_posedge && !wb_cyc_o) begin
                wb_cyc_o <= 1'b1;
                wb_stb_o <= 1'b1;
                wb_adr_o <= wb_adr_d;
                wb_we_o  <= wb_we_d;
                wb_dat_o <= data_q;
            end else if (wb_cyc_o) begin
                if (wb_ack_i) begin
                    wb_cyc_o  <= 1'b0;
                    wb_stb_o  <= 1'b0;
                    //wb_data_q <= wb_dat_i;
                    txndata_wb[DATABITS-1:0] <= wb_dat_i;
                    // leftover bits set to zero
                    txndata_wb[IOREG_BITS-1:DATABITS] <= 'b0;
                end
            end else if (txnreset_i) begin
                wb_cyc_o <= 'b0;
                wb_stb_o <= 'b0;
                wb_we_o  <= 'b0;
                wb_adr_o <= 'b0;
                wb_dat_o <= 'b0;
            end
        end
    end

endmodule
