/** fifo.v
 *
 * FIFOs
 *
 */

`default_nettype none
`timescale 1ns/10ps

// Full-Synchronous FIFO (one clock)
module fsfifo #(
    parameter WIDTH = 32,
    parameter DEPTH = 16
) (
    input  clk_i, reset_i,
    // status
    output full_o, empty_o,
    output [$clog2(DEPTH):0] filled_o,
    // write port
    input  wr_i,
    input  [WIDTH-1:0] wr_data_i,
    // read port
    input  rd_i,
    output reg [WIDTH-1:0] rd_data_o
);

    localparam DEPTH_BITS = $clog2(DEPTH);
    `define MAX_PATTERN { 1'b1, {(DEPTH_BITS){1'b0}} }

    // memory
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // read/write pointers
    // one extra bit for full/empty detection
    reg  [DEPTH_BITS:0] rdp, wrp;
    assign filled_o  = wrp - rdp;
    assign empty_o = filled_o == 'b0;
    assign full_o  = filled_o == `MAX_PATTERN;

    // read/write signals
    wire read, write;
    assign read  = rd_i && !empty_o;
    assign write = wr_i && !full_o;

    // increment pointers
    always @(posedge clk_i)
        if (reset_i)    rdp <= 'b0;
        else if (read)  rdp <= rdp + 'b1;
    always @(posedge clk_i)
        if (reset_i)    wrp <= 'b0;
        else if (write) wrp <= wrp + 'b1;

    // read/write
    always @(posedge clk_i)
        if (write) mem[wrp[DEPTH_BITS-1:0]] <= wr_data_i;
    always @(posedge clk_i)
        if (reset_i) rd_data_o <= {(WIDTH){1'bx}};
        else if (read) rd_data_o <= mem[rdp[DEPTH_BITS-1:0]];

    generate
        genvar i;
        for (i = 0; i < DEPTH; i = i + 1) begin
            always @(posedge clk_i) if (reset_i) mem[i] <= {(WIDTH){1'bx}};
        end
    endgenerate

`ifdef FORMAL
    reg f_past_valid = 0;
    always @(posedge clk_i) f_past_valid = 1;

    `ifdef FORMAL_FSFIFO_TOP
    initial assume(reset_i);
    `endif // FORMAL_FSFIFO_TOP

    always @(*) assert(empty_o == (filled_o == 'b0));
    always @(*) assert(full_o == (filled_o == `MAX_PATTERN));

    always @(*) assert(!full_o || !empty_o);
    //always @(*) if (f_past_valid) assert(filled_o <= `MAX_PATTERN);

    always @(posedge clk_i) begin
        if (f_past_valid && !reset_i && !$past(reset_i) && !$past(full_o) && $past(wr_i))
            assert(mem[$past(wrp[DEPTH_BITS-1:0])] == $past(wr_data_i));
        if (f_past_valid && !reset_i && !$past(reset_i) && !$past(empty_o) && $past(rd_i))
            assert((mem[$past(rdp[DEPTH_BITS-1:0])]) == rd_data_o);

        if (f_past_valid && !reset_i && !$past(reset_i))
            assert((rdp == $past(rdp)+'b1) || (rdp == $past(rdp)) || ((rdp == 'b1) && ($past(rdp) == `MAX_PATTERN)));
        if (f_past_valid && !reset_i && !$past(reset_i))
            assert((wrp == $past(wrp)+'b1) || (wrp == $past(wrp)) || ((wrp == 'b1) && ($past(wrp) == `MAX_PATTERN)));
    end

    // covers
    always @(posedge clk_i) begin
        cover(full_o && !$past(full_o));
        cover(!full_o && $past(full_o));
        cover(empty_o && !$past(empty_o));
        cover(!empty_o && $past(empty_o));
        cover(!$past(full_o,2) && $past(full_o) && !full_o);
        cover($past(empty_o,2) && !$past(empty_o) && empty_o);
    end
`endif

endmodule
