/** qspi.v
 *
 * QSPI interface
 *
 */

`default_nettype none
`timescale 1ns/10ps

module qspi_slave #(
    parameter IOREG_BITS       = 32, // bits in IO registers
    parameter CYCLE_COUNT_BITS = 8, // number of bits for cycle counter
    parameter IO_POL           = 1  // 1 = positive, 0 = negative
    // TODO: CPOL and CPHA
) (
    input reset_i,
    input clk_i, // do we need this?

    // QSPI interface
    input                             sck_i,
    input                             sce_i,     // active low
    input                       [3:0] sio_i,
    output                      [3:0] sio_o,
    output                            sio_oe,    // 0 = input, 1 = output

    // higher-level interface
    input      [CYCLE_COUNT_BITS-1:0] txncc_i,   // transaction cycle
    input                             txnmode_i, // transaction mode, 0 = single SPI with MOSI=sio_i[0] and MISO=sio_o[1], 1 = quad SPI
    input                             txndir_i,  // transaction direction, 0 = read, 1 = write
    input            [IOREG_BITS-1:0] txndata_i,
    output reg       [IOREG_BITS-1:0] txndata_o,
    output reg                        txndone_o  // high for one cycle when data has been received
);

    localparam IOREG_INDEX_BITS = $clog2(IOREG_BITS);

    // polarity
    wire [3:0] sio_in;
    reg  [3:0] sio_out;
    generate
        if (IO_POL) begin
            assign sio_in = sio_i;
            assign sio_o  = sio_out;
        end else begin
            assign sio_in = ~sio_i;
            assign sio_o  = ~sio_out;
        end
    endgenerate

    // negate sce so we can trigger on negedge for reset
    wire sce_i_b;
    assign sce_i_b = !sce_i;

    // enable output when we are in a transaction and the direction is out
    assign sio_oe = !sce_i && txndir_i;

    // cycle counter
    reg [CYCLE_COUNT_BITS-1:0] cycle_counter;
    always @(negedge sck_i or posedge sce_i)
        if (sce_i) begin
            cycle_counter <= 'b0;
        end else if (reset_i || txndone_o) begin
            cycle_counter <= 'b0;
        end else begin
            cycle_counter <= cycle_counter + 'b1;
        end

    wire [CYCLE_COUNT_BITS-1:0] outdata_index;
    assign outdata_index = txncc_i - cycle_counter;

    // signal done on POSITIVE edge
    always @(posedge sck_i)
        txndone_o <= (cycle_counter == txncc_i);

    /*
    always @(*) case(txnmode_i)
        1'b0: sio_out = txndata_i[outdata_index[IOREG_INDEX_BITS-1:0]];
        1'b1: sio_out = txndata_i[4*outdata_index[IOREG_INDEX_BITS-1:0]+:4];
    endcase
    */
    always @(*)
        sio_out = txndata_i[4*outdata_index[IOREG_INDEX_BITS-1:0]+:4];

    // SPI
    always @(posedge sck_i or posedge sce_i) begin
        if (sce_i) begin
            txndata_o <= 'b0;
        end else if (reset_i) begin
            txndata_o <= 'b0;
        end else begin
            if (!txndir_i) begin // input
                case (txnmode_i)
                    1'b0: txndata_o <= { txndata_o[IOREG_BITS-2:0], sio_in[0] };
                    1'b1: txndata_o <= { txndata_o[IOREG_BITS-5:0], sio_in    };
                endcase
            end
        end
    end

    // Formal verification
`ifdef FORMAL

    // past valid and reset
    reg f_past_valid_sck;
    initial f_past_valid_sck <= 1'b0;
    always @(negedge sck_i)
        f_past_valid_sck <= 1'b1;
    always @(*)
        if (!f_past_valid_sck) assume(reset_i);

    // reset conditions

    initial assume(reset_i);
    initial assume(sce_i);
    initial assume(sck_i);

    always @(negedge sck_i) begin
        if (!f_past_valid_sck || $past(reset_i)) begin
            // reset condition
            assume(sce_i);
            assume(sio_i == 'b0);
        end
	end

    // txncc does not change while we're transfering
    always @(negedge sck_i)
        if (!reset_i && !sce_i && cycle_counter != txncc_i) begin
            assume(txncc_i   == $past(txncc_i));
            assume(txnmode_i == $past(txnmode_i));
            assume(txndir_i  == $past(txndir_i ));
            if (txndir_i)
                assume(txndata_i == $past(txndata_i));
        end

    always @(*)
        if (!sce_i && !txndone_o)
            assume(!sce_i);

    // assertions

    // never assert output if not enabled
    always @(negedge sck_i)
        if (sce_i)
            assert(!sio_oe);
    // only assert output if txndir_i
    always @(negedge sck_i)
        if (!txndir_i)
            assert(!sio_oe);

    always @(negedge sck_i) begin
        if (!reset_i) begin
            cover(sio_oe);
        end
    end

    always @(posedge sck_i)
        if (!reset_i)
            cover(txndone_o);

`endif // FORMAL

endmodule

`include "cmd_defs.v"

module qspi_ctrl_passthrough #(
    parameter ADDRBITS = 26,
    parameter DATABITS = 16,
    parameter IOREG_BITS = 32,
    parameter WCOUNTERBITS = 8
) (
    input reset_i, // synchronous to local clock
    input clk_i, // local clock

    // data inputs
    output reg            [7:0] txncc_o,   // transaction cycle count
    output reg                  txnmode_o, // transaction mode, 0 = single SPI with MOSI=sio_i[0] and MISO=sio_o[1], 1 = quad SPI
    output reg                  txndir_o,  // transaction direction, 0 = read, 1 = write
    output     [IOREG_BITS-1:0] txndata_o,
    input      [IOREG_BITS-1:0] txndata_i,
    input                       txndone_i, // high for one cycle when data has been received
    input                       txnreset_i, // transaction reset (CE high)

    // wishbone
    output reg                  wb_cyc_o,
    output reg                  wb_stb_o,
    output reg                  wb_we_o,
    output reg                  wb_err_o,
    output reg           [31:0] wb_adr_o,
    output reg   [DATABITS-1:0] wb_dat_o,
    input                       wb_ack_i,
    input                       wb_stall_i,
    input        [DATABITS-1:0] wb_dat_i
);

    localparam QSPI_ADDR_CYCLES     = 2 * ((ADDRBITS+8-1) / 8);
    localparam QSPI_ADDR_CYCLE_BITS = $clog2(QSPI_ADDR_CYCLES);
    localparam QSPI_DATA_CYCLES     = (DATABITS+4-1) / 4;
    localparam QSPI_DATA_CYCLE_BITS = $clog2(QSPI_DATA_CYCLES);

    localparam [1:0] SPI_PHASE_CMD   = 2'b00,
                     SPI_PHASE_ADDR  = 2'b01, // read in address
                     SPI_PHASE_STALL = 2'b10, // stall while reading or writing
                     SPI_PHASE_DATA  = 2'b11; // read in data / write out data

    reg [1:0] phase; // state machine state
    // Address may not be an even multiple of 4, so we shift in extra and discard high bits
    reg [QSPI_ADDR_CYCLES*4-1:0] addr_in;
    reg                    [5:0] addr_nor_cmd; // NOR command encoded into wb address
    // latched parameters
    reg           [7:0] cmd_q;
    reg  [DATABITS-1:0] data_q;

    reg [IOREG_BITS-1:0] txndata_wb;
    assign txndata_o = cmd_q == `SPI_COMMAND_LOOPBACK ? addr_in[IOREG_BITS-1:0] : txndata_wb;

    wire spi_reset;
    assign spi_reset = reset_i || txnreset_i;

    wire cmd_is_write = (cmd_q == `SPI_COMMAND_WRITE_THRU);
    //cmd_q != `SPI_COMMAND_READ && cmd_q != `SPI_COMMAND_FAST_READ && cmd_q != `SPI_COMMAND_LOOPBACK;

    // QSPI->wb sync
    wire wb_we_d;
    reg wb_req_d; // d captures the signal, which is captured into q on a rising edge of clk
    assign wb_we_d = cmd_is_write;

    // SPI parameters
    always @(*) begin
        case (phase)
            SPI_PHASE_CMD: begin
                txnmode_o = 'b0; // single SPI
                txndir_o  = 'b0; // input
                txncc_o   = 'h7;
            end
            SPI_PHASE_ADDR: begin
                txnmode_o = 'b1; // quad
                txndir_o  = 'b0; // input
                txncc_o   = QSPI_ADDR_CYCLES-1;
            end
            SPI_PHASE_STALL: begin
                txnmode_o = 'b1; // quad
                txndir_o  = 'b0; // input
                txncc_o   = 'h13; // 20 cycles
            end
            SPI_PHASE_DATA: begin
                txnmode_o = 'b1; // qspi
                txndir_o  = !cmd_is_write; // output if read, else input
                txncc_o   = QSPI_DATA_CYCLES-1;
            end
            default: begin // cmd
                txnmode_o = 'b0; // single SPI
                txndir_o  = 'b0; // input
                txncc_o   = 'h7;
            end
        endcase
    end

    // Register inputs
    always @(posedge txndone_i or posedge reset_i) begin
        if (reset_i) begin
            cmd_q   <= 'b0;
            data_q  <= 'b0;
            addr_in <= 'b0;
        end else
            /* verilator lint_off CASEINCOMPLETE */
            case (phase)
                SPI_PHASE_CMD:  cmd_q   <= txndata_i[7:0];
                SPI_PHASE_ADDR: addr_in <= txndata_i[QSPI_ADDR_CYCLES*4-1:0];
                SPI_PHASE_DATA: data_q  <= txndata_i[DATABITS-1:0];
            endcase
            /* verilator lint_on CASEINCOMPLETE */
    end

    // Request generation
    always @(posedge txndone_i or posedge reset_i) begin
        if (reset_i)
            wb_req_d <= 'b0;
        else case (phase)
            SPI_PHASE_CMD:
                wb_req_d <= 'b0;
            SPI_PHASE_ADDR:
                if (cmd_q == `SPI_COMMAND_READ || cmd_q == `SPI_COMMAND_FAST_READ || cmd_q == `SPI_COMMAND_LOOPBACK)
                    wb_req_d <= 'b1;
                else
                    wb_req_d <= 'b0;
            SPI_PHASE_STALL:
                wb_req_d <= 'b0;
            SPI_PHASE_DATA: begin
                if (cmd_q == `SPI_COMMAND_WRITE_THRU)
                    wb_req_d <= 'b1;
                else
                    wb_req_d <= 'b0;
            end
        endcase
    end

    // QSPI phases
    always @(posedge txndone_i or posedge spi_reset) begin
        if (spi_reset) begin
            phase <= SPI_PHASE_CMD;
        end else case (phase)
            SPI_PHASE_CMD: begin
                phase <= SPI_PHASE_ADDR;
            end
            SPI_PHASE_ADDR: begin
                case (cmd_q)
                    `SPI_COMMAND_FAST_READ: begin
                        phase <= SPI_PHASE_STALL;
                    end
                    default: begin
                        phase <= SPI_PHASE_DATA;
                    end
                endcase
            end
            SPI_PHASE_STALL: begin
                phase <= SPI_PHASE_DATA;
            end
            SPI_PHASE_DATA: begin
                phase <= SPI_PHASE_CMD;
            end
            default: begin
                phase <= SPI_PHASE_CMD;
            end
        endcase
    end

    wire [31:0] wb_adr_d;
    assign wb_adr_d = { addr_nor_cmd, addr_in[ADDRBITS-1:0] };

    // Map QSPI commands to our wb commands, encode in top six bits of addr_q
    always @(*) case(cmd_q)
        `SPI_COMMAND_READ:       addr_nor_cmd = `NOR_CYCLE_READ;
        `SPI_COMMAND_FAST_READ:  addr_nor_cmd = `NOR_CYCLE_READ;
        `SPI_COMMAND_WRITE_THRU: addr_nor_cmd = `NOR_CYCLE_WRITE;
        default:                 addr_nor_cmd = `NOR_CYCLE_RESET;
    endcase

    // Wishbone control

    reg [1:0] wb_req_q;
    wire      wb_req_q_posedge;
    assign    wb_req_q_posedge = wb_req_q[0] && !wb_req_q[1];
    always @(posedge clk_i)
        wb_req_q <= { wb_req_q[0], wb_req_d };
        //wb_req_q <= { wb_req_q[0], wb_req_d && txndone_i };

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

module qspi_ctrl_fsm #(
    parameter ADDRBITS = 26,
    parameter DATABITS = 16,
    parameter IOREG_BITS = 32,
    parameter WCOUNTERBITS = 8
) (
    input reset_i, // synchronous to local clock
    input clk_i, // local clock

    // data inputs
    output                [7:0] txncc_o,   // transaction cycle count minus one (e.g. txncc=3 => 4 cycles)
    output                      txnmode_o, // transaction mode, 0 = single SPI with MOSI=sio_i[0] and MISO=sio_o[1], 1 = quad SPI
    output                      txndir_o,  // transaction direction, 0 = read, 1 = write
    output     [IOREG_BITS-1:0] txndata_o,
    input      [IOREG_BITS-1:0] txndata_i,
    input                       txndone_i, // high for one cycle when data has been received
    input                       txnreset_i, // transaction reset (CE high)

    // controller requests
    output reg                  vt_mode,

    // wishbone
    output reg                  wb_cyc_o,
    output reg                  wb_stb_o,
    output reg                  wb_we_o,
    output reg                  wb_err_o,
    output reg           [31:0] wb_adr_o,
    output reg   [DATABITS-1:0] wb_dat_o,
    input                       wb_ack_i,
    input                       wb_stall_i,
    input        [DATABITS-1:0] wb_dat_i
);

    localparam QSPI_ADDR_CYCLES     = 2 * ((ADDRBITS+8-1) / 8);
    localparam QSPI_ADDR_CYCLE_BITS = $clog2(QSPI_ADDR_CYCLES);
    localparam QSPI_DATA_CYCLES     = (DATABITS+4-1) / 4;
    localparam QSPI_DATA_CYCLE_BITS = $clog2(QSPI_DATA_CYCLES);

    localparam [3:0] SPI_STATE_CMD             = 4'h0,
                     SPI_STATE_ADDR            = 4'h1,
                     SPI_STATE_FAST_READ_STALL = 4'h2,
                     SPI_STATE_READ_DATA       = 4'h3,
                     SPI_STATE_PROG_WORD_DATA  = 4'h4,
                     SPI_STATE_WRITE_THRU_DATA = 4'h5,
                     SPI_STATE_LOOPBACK_DATA   = 4'h6,
                     SPI_STATE_PAGE_PROG_DATA  = 4'h7;

    // spi reset
    wire spi_reset;
    assign spi_reset = reset_i || txnreset_i;

    // SPI state
    reg [3:0] spi_state_next;
    reg [3:0] spi_state;

    // latched command words
    reg                     [7:0] cmd_in;
    reg  [4*QSPI_ADDR_CYCLES-1:0] addr_in;
    reg  [4*QSPI_DATA_CYCLES-1:0] data_q;

    // wb control and sync
    reg wb_req_d; // wb sync signal
    // reduce data width (e.g. from 32bits to 24)
    wire             [ADDRBITS-1:0] addr_q;
    assign addr_q = addr_in[ADDRBITS-1:0];
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
    assign txndata_o = (cmd_in == `SPI_COMMAND_LOOPBACK) ? addr_in : txndata_wb;

    // { 9=mode, 8=dir, [7:0]=cycle_count }
    reg [9:0] txn_config_reg[16]; // up to index 6 currently specified, the rest default to command
    assign { txnmode_o, txndir_o, txncc_o } = txn_config_reg[spi_state];
    // initialize config reg
    integer i;
    initial begin
        // pre-init to command
        for (i = 0; i < 16; i = i + 1) begin
            txn_config_reg[i] = { 1'b0, 1'b0, 8'h7 }; // COMMAND: single-SPI, input, 8 cycles
        end
        txn_config_reg[0] = { 1'b0, 1'b0, 8'h7 };                       // COMMAND:       single-SPI, input, 8 cycles
        txn_config_reg[1] = { 1'b1, 1'b0, QSPI_ADDR_CYCLES[7:0]-8'd1 }; // ADDR:            quad-SPI, input
        txn_config_reg[2] = { 1'b1, 1'b0, 8'h13 };                      // FAST READ STALL: quad-SPI, input, 20 cycles
        txn_config_reg[3] = { 1'b1, 1'b1, QSPI_DATA_CYCLES[7:0]-8'd1 }; // READ DATA:       quad-SPI, output
        txn_config_reg[4] = { 1'b1, 1'b0, QSPI_DATA_CYCLES[7:0]-8'd1 }; // PROG WORD DATA:  quad-SPI, input
        txn_config_reg[5] = { 1'b1, 1'b0, QSPI_DATA_CYCLES[7:0]-8'd1 }; // WRITE THRU DATA: quad-SPI, input
        txn_config_reg[6] = { 1'b1, 1'b1, QSPI_DATA_CYCLES[7:0]-8'd1 }; // LOOPBACK DATA:   quad-SPI, output
        txn_config_reg[7] = { 1'b1, 1'b0, QSPI_DATA_CYCLES[7:0]-8'd1 }; // PAGE PROG DATA:  quad-SPI, input
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
            cmd_in  <= 'b0;
            addr_in <= 'b0;
            data_q  <= 'b0;
        end else case (spi_state)
            SPI_STATE_CMD:             cmd_in  <= txndata_i[7:0];
            SPI_STATE_ADDR:            addr_in <= txndata_i[4*QSPI_ADDR_CYCLES-1:0];
            SPI_STATE_PROG_WORD_DATA,
            SPI_STATE_PAGE_PROG_DATA,
            SPI_STATE_WRITE_THRU_DATA: data_q  <= txndata_i[DATABITS-1:0];
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
