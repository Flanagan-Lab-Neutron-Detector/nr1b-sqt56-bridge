/** upcounter.v
 *
 * Up-counter
 *
 */

`default_nettype none
`timescale 1ns/10ps

module upcounter #(
    parameter BITS = 8
) (
    input                 i_clk, i_rst,
    input                 i_load, i_en,
    input      [BITS-1:0] i_load_val,
    output reg [BITS-1:0] o_count
);

    always @(posedge i_clk)
        if (i_rst)       o_count <= 'b0;
        else if (i_load) o_count <= i_load_val;
        else if (i_en)   o_count <= o_count + 'b1;

endmodule
