/** dbguart.v
 *
 * Debug UART interface
 *
 */

`default_nettype none
`timescale 1ns/100ps

module dbguart #(
    parameter CLKFREQ  = 75_000_000,
    parameter BAUDRATE = 115_200,
    parameter REGLEN   = 72
) (
    // system
    input                  i_clk,
    input                  i_rst,

    // UART
    output reg             o_tx,
    //output reg             o_rdy,

    // debug interface
    input                  i_dbg_stb,
    input     [REGLEN-1:0] i_dbg
);

    // incoming message fifo
    wire fifo_full, fifo_empty;
    reg  fifo_wr, fifo_rd;
    reg  [REGLEN-1:0] fifo_wr_data;
    wire [REGLEN-1:0] fifo_rd_data;
    fsfifo #(.WIDTH(REGLEN), .DEPTH(32)) infifo (
        .clk_i(i_clk), .reset_i(i_rst),
        .full_o(fifo_full), .empty_o(fifo_empty), .filled_o(),
        .wr_i(fifo_wr), .wr_data_i(fifo_wr_data),
        .rd_i(fifo_rd), .rd_data_o(fifo_rd_data)
    );

    // uart handshake
    wire       uart_rdy;
    reg        uart_start;
    reg  [7:0] word;
    reg [REGLEN-1:0] dbgreg;

    // word counter
    localparam REGLENLVL  = REGLEN - 1;
    localparam REGLENBITS = $clog2(REGLENLVL);
    reg  [REGLENBITS-1:0] word_cnt;
    wire                  word_stb = word_cnt == REGLENLVL[REGLENBITS-1:0];
    always @(posedge i_clk) begin
        if (i_rst)
            word_cnt <= 'b0;
        else if (uart_rdy) begin
            if (word_stb)
                word_cnt <= 'b0;
            else
                word_cnt <= word_cnt + 'b1;
        end
    end

    // load debug reg
    always @(*) begin
        fifo_rd = uart_rdy && word_stb;
    end
    always @(posedge i_clk)
        if (i_rst)        dbgreg <= 'b0;
        else if (fifo_rd) dbgreg <= fifo_rd_data;

    // Debug reg -> bytes
    always @(*) word = dbgreg[8*word_cnt-:8];

    // TX UART
    txuart #(
        .CLKFREQ(CLKFREQ), .BAUDRATE(BAUDRATE), .REGLEN(8)
    ) uart (
        .i_clk(i_clk), .i_rst(i_rst),
        .o_tx(o_tx), .o_rdy(uart_rdy), .i_start(uart_start),
        .i_reg(word)
    );

    // write whenever we can
    always @(*) fifo_wr      = i_dbg_stb;
    always @(*) fifo_wr_data = i_dbg;

endmodule
