/** txuart.v
 *
 * Transmit-only UART interface
 *
 */

`default_nettype none
`timescale 1ns/100ps

module txuart #(
    parameter CLKFREQ  = 75_000_000,
    parameter BAUDRATE = 115_200,
    parameter REGLEN   = 8,
    parameter BAUDDIV  = CLKFREQ / BAUDRATE
) (
    // system
    input                  i_clk,
    input                  i_rst,

    // UART
    output reg             o_tx,
    output reg             o_rdy,
    input                  i_start,

    // debug interface
    input     [REGLEN-1:0] i_reg
);

    // transmit states
    localparam [1:0] IDLE  = 2'b00,
                     START = 2'b01,
                     DATA  = 2'b10,
                     STOP  = 2'b11;
    reg [1:0] state;
    reg [1:0] next_state;

    // baud clock divider
    localparam BAUDBITS = $clog2(BAUDDIV);
    reg [BAUDBITS-1:0] baudcnt;
    wire               baudstb = baudcnt == 'b0;
    always @(posedge i_clk) begin
        if (i_rst || baudstb) baudcnt <= BAUDDIV[BAUDBITS-1:0];
        else                  baudcnt <= baudcnt - 'b1;
    end

    // baud clock
    reg baudclk;
    always @(posedge i_clk) begin
        if (i_rst)        baudclk <= 'b0;
        else if (baudstb) baudclk <= !baudclk;
    end

    // bit counter
    localparam BITSTBLVL = REGLEN-1;
    localparam REGBITS   = $clog2(REGLEN-1);
    reg [REGBITS-1:0] bitcnt;
    wire bitstb = bitcnt == BITSTBLVL[REGBITS-1:0];
    always @(posedge i_clk) begin
        if (i_rst)                           bitcnt <= 'b0;
        else if (baudstb && (state == DATA)) bitcnt <= bitcnt + 'b1;
    end

    // transmit state machine

    always @(*) begin
        next_state = 2'bx;
        case (state)
            IDLE:  next_state = i_start ? START : IDLE;
            START: next_state = DATA;
            DATA:  next_state = bitstb  ? STOP  : DATA;
            STOP:  next_state = IDLE;
        endcase
    end

    always @(posedge i_clk) begin
        if (i_rst)        state <= IDLE;
        else if (baudstb) state <= next_state;
    end

    always @(*) o_rdy = !i_rst && (state == IDLE);
    always @(posedge i_clk) begin
        if (i_rst) begin
            o_tx <= 'b1;
        end else case (state)
            IDLE:  o_tx <= 'b1;
            START: o_tx <= 'b1;
            DATA:  o_tx <= i_reg[bitcnt];
            STOP:  o_tx <= 'b1;
            default: o_tx <= 1'bx;
        endcase
    end

endmodule
