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
    output                      [1:0] txnmode_o, // transaction mode, 00 = single SPI, 01 = dual SPI, 10 = quad SPI, 11 = octo SPI
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
    output reg                 [31:0] wb_adr_o,
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

    localparam [2:0] SPI_STATE_CMD             = 3'h0,
                     SPI_STATE_ADDR            = 3'h1,
                     SPI_STATE_FAST_READ_STALL = 3'h2,
                     SPI_STATE_READ_DATA       = 3'h3,
                     SPI_STATE_PROG_WORD_DATA  = 3'h4,
                     SPI_STATE_WRITE_THRU_DATA = 3'h5,
                     SPI_STATE_RFU_0           = 3'h6,
                     SPI_STATE_PAGE_PROG_DATA  = 3'h7;

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
    // NOR command is packed into the top 6 bits of address
    reg  [5:0] nor_cmd;
    // write direction
    wire cmd_is_write;

    // { [CYCLE_COUNT_BITS+3-1:3]=bit_count, [2:1]=mode, [0]=dir }
    reg [CYCLE_COUNT_BITS+3-1:0] txn_config_reg[8];
    assign { txnbc_o, txnmode_o, txndir_o } = txn_config_reg[spi_state];
    // initialize config reg
    integer i;
    initial begin
        // pre-init to command
        for (i = 0; i < 8; i = i + 1) begin
            txn_config_reg[i] = { 8'h08, 2'b00, 1'b0 }; // COMMAND: quad-SPI, input, 8 bits
        end
        txn_config_reg[0] = { 8'h08,             2'b10, 1'b0 }; // COMMAND:           quad-SPI, input, 8 cycles
        txn_config_reg[1] = { ADDRBITS_RND[7:0], 2'b10, 1'b0 }; // ADDR:              quad-SPI, input
        txn_config_reg[2] = { 8'h50,             2'b10, 1'b0 }; // FAST READ STALL:   quad-SPI, input, 20 cycles
        txn_config_reg[3] = { DATABITS_RND[7:0], 2'b10, 1'b1 }; // READ DATA:         quad-SPI, output
        txn_config_reg[4] = { DATABITS_RND[7:0], 2'b10, 1'b0 }; // PROG WORD DATA:    quad-SPI, input
        txn_config_reg[5] = { DATABITS_RND[7:0], 2'b10, 1'b0 }; // WRITE THRU DATA:   quad-SPI, input
        txn_config_reg[6] = { 8'h08,             2'b10, 1'b0 }; // RFU 0              quad-SPI, input, 8 cycles
        txn_config_reg[7] = { DATABITS_RND[7:0], 2'b10, 1'b0 }; // PAGE PROG DATA:    quad-SPI, input
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
                `SPI_COMMAND_BULK_ERASE: spi_state_next = SPI_STATE_CMD;
                default:                 spi_state_next = SPI_STATE_ADDR;
            endcase
            SPI_STATE_ADDR: case (cmd_q)
                `SPI_COMMAND_READ:       spi_state_next = SPI_STATE_READ_DATA;
                `SPI_COMMAND_FAST_READ:  spi_state_next = SPI_STATE_FAST_READ_STALL;
                `SPI_COMMAND_PROG_WORD:  spi_state_next = SPI_STATE_PROG_WORD_DATA;
                `SPI_COMMAND_WRITE_THRU: spi_state_next = SPI_STATE_WRITE_THRU_DATA;
                `SPI_COMMAND_PAGE_PROG:  spi_state_next = SPI_STATE_PAGE_PROG_DATA;
                default:                 spi_state_next = SPI_STATE_CMD;
            endcase
            SPI_STATE_FAST_READ_STALL:   spi_state_next = SPI_STATE_READ_DATA;
            SPI_STATE_READ_DATA:         spi_state_next = SPI_STATE_READ_DATA; // continuous reads
            SPI_STATE_PAGE_PROG_DATA:    spi_state_next = SPI_STATE_PAGE_PROG_DATA;
            default:                     spi_state_next = SPI_STATE_CMD;
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
            SPI_STATE_CMD:             cmd_q  <= txndata_i[7:0];
            SPI_STATE_ADDR:            addr_q <= txndata_i[ADDRBITS-1:0];
            SPI_STATE_PROG_WORD_DATA,
            SPI_STATE_PAGE_PROG_DATA,
            SPI_STATE_WRITE_THRU_DATA: data_q <= txndata_i[DATABITS-1:0];
            default:;
        endcase

    // assign NOR command
    always @(*) case (cmd_q)
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
    always @(posedge clk_i) begin
        wb_req <= 'b0;
        if (!cmd_is_write && ((spi_state == SPI_STATE_READ_DATA) || (spi_state == SPI_STATE_FAST_READ_STALL)) && !txnreset_sync) begin
            wb_req <= 'b1;
        end else if (wstb_pe) case (spi_state)
            // cmd is txndata_i[7:0] on command cycle since cmd_q is latched on this cycle
            SPI_STATE_CMD: case (txndata_i[7:0])
                `SPI_COMMAND_BULK_ERASE: wb_req <= 1'b1;
                `SPI_COMMAND_RESET:      wb_req <= 1'b1;
                default:                 wb_req <= 1'b0;
            endcase
            SPI_STATE_ADDR: case (cmd_q)
                `SPI_COMMAND_READ:       wb_req <= 1'b1;
                `SPI_COMMAND_FAST_READ:  wb_req <= 1'b1;
                `SPI_COMMAND_SECT_ERASE: wb_req <= 1'b1;
                default:                 wb_req <= 1'b0;
            endcase
            SPI_STATE_PROG_WORD_DATA:    wb_req <= 1'b1;
            SPI_STATE_WRITE_THRU_DATA:   wb_req <= 1'b1;
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

    // Address counter for sequential reads
    reg [ADDRBITS-1:0] addr_counter;
    always @(posedge clk_i)
        if (spi_reset) addr_counter <= 'b0;
        else if (wb_req && !wb_stall_i && !cmd_is_write && !wb_cyc_o && !req_pipe_full)
                       addr_counter <= addr_q + 'b1;
        //else if (wb_cyc_o && !cmd_is_write && wb_ack_i)
        else if (wb_req && !wb_stall_i && !cmd_is_write && !req_pipe_full)
                       addr_counter <= addr_counter + 'b1;

    // fifo for sequential read data
    wire                fifo_full, fifo_empty;
    reg                 fifo_wr, fifo_rd;
    reg  [DATABITS-1:0] fifo_wr_data;
    wire [DATABITS-1:0] fifo_rd_data;
    wire          [4:0] fifo_filled;
    fsfifo #(.WIDTH(DATABITS), .DEPTH(16)) read_fifo (
        .clk_i(clk_i), .reset_i(spi_reset),
        .full_o(fifo_full), .empty_o(fifo_empty), .filled_o(fifo_filled),
        .wr_i(fifo_wr), .wr_data_i(fifo_wr_data),
        .rd_i(fifo_rd), .rd_data_o(fifo_rd_data)
    );

    // send read data
    reg read_this_cycle;
    always @(posedge clk_i) begin
        if (spi_reset || wstb_pe) read_this_cycle <= 'b0;

        fifo_rd <= 'b0;
        if (spi_state_next == SPI_STATE_READ_DATA && (!fifo_empty || fifo_wr) && !read_this_cycle) begin
            //&& (/*inflight_none*/ (fifo_empty && fifo_wr) || (!fifo_empty && wstb_pe))) begin
            fifo_rd <= 'b1;
            read_this_cycle <= 'b1;
        end
    end

    reg fifo_rd_delayed;
    always @(posedge clk_i) fifo_rd_delayed <= fifo_rd;

    reg first_rd_complete;
    always @(posedge clk_i) begin
        if (spi_reset)
            first_rd_complete <= 'b0;
        else if (spi_state_next == SPI_STATE_READ_DATA && fifo_rd_delayed)
            first_rd_complete <= 'b1;
    end

    always @(posedge clk_i) begin
        if (spi_reset) begin
            txndata_o <= 'b0;
        end else if ((!first_rd_complete && fifo_rd_delayed) || wstb_pe) begin
            txndata_o <= 'b0;
            txndata_o[DATABITS-1:0] <= fifo_rd_data;
        end
    end

    // in-flight counter for sequential reads
    reg [4:0] inflight;
    //wire inflight_max, inflight_none;
    //assign inflight_max  = inflight == 4'hF;
    //assign inflight_none = inflight == 4'h0;
    wire [4:0] active_reqs;
    wire       req_pipe_full;
    assign active_reqs = fifo_filled + inflight + {4'b0, fifo_wr}; //5'(fifo_wr);
    assign req_pipe_full = active_reqs[4];

    // Wishbone control

    always @(posedge clk_i) begin
        wb_stb_o <= 'b0;
        fifo_wr  <= 'b0;
        if (reset_i) begin
            wb_cyc_o     <= 'b0;
            wb_we_o      <= 'b0;
            wb_adr_o     <= 'b0;
            wb_dat_o     <= 'b0;
            fifo_wr_data <= 'b0;
            inflight     <= 'b0;
            //txndata_o <= 'b0;
        end else begin
            if (wb_cyc_o && wb_ack_i) begin
                // drop cyc if we're not doing sequential reads
                if (txnreset_sync || wb_we_o)
                    wb_cyc_o     <= 'b0;
                if (!wb_we_o) begin
                    // only subtract if we're not adding later
                    if (!wb_req || req_pipe_full || wb_stall_i || cmd_is_write)
                        inflight <= inflight - 'b1;
                    // assert !fifo_full
                    fifo_wr      <= 'b1;
                    fifo_wr_data <= wb_dat_i;
                    //txndata_o[DATABITS-1:0] <= wb_dat_i;
                    // leftover bits set to zero
                    //txndata_o[IOREG_BITS-1:DATABITS] <= 'b0;
                end
            end

            if (wb_req && !wb_stall_i && !req_pipe_full) begin
                wb_cyc_o <= 'b1;
                wb_stb_o <= 'b1;
                wb_adr_o <= { nor_cmd, addr_q };
                wb_we_o  <= cmd_is_write;
                wb_dat_o <= data_q;
                // if read
                if (!cmd_is_write) begin
                    // only add if we're not subtracting earlier
                    if (!wb_cyc_o || !wb_ack_i) inflight <= inflight + 'b1;
                    // if sequential
                    if (wb_cyc_o)
                        wb_adr_o <= { nor_cmd, addr_counter };
                end
            //end else if (wb_cyc_o) begin
            end else if (txnreset_sync) begin
                wb_cyc_o <= 'b0;
                wb_we_o  <= 'b0;
                wb_adr_o <= 'b0;
                wb_dat_o <= 'b0;
                inflight <= 'b0;
            end
        end
    end

endmodule
