/** sync2.v
 *
 * 2DFF synchronizer.
 * Platform-specific synchronizer if available,
 * otherwise simple verilog model.
 *
 * Platform    Define         Description
 * ice40       SYNTH_ICE40    Chain of two SB_DFFs
 *
 */

`default_nettype none
`timescale 1ns/100ps

// sync2 posedge srst verilog model
module sync2ps_model (input clk, rst, d, output wire q);
    reg [1:0] r;
    assign q = r[1];
    always @(posedge clk)
        if (rst) r <= 'b0;
        else     r <= {r[0], d};
endmodule

// sync2 posedge srst edge-detect verilog model
module sync2pse_model (input clk, rst, d, output wire q, pe, ne);
    reg [2:0] r;
    assign q = r[1];
    assign pe =  r[1] && !r[2];
    assign ne = !r[1] &&  r[2];
    always @(posedge clk)
        if (rst) r <= 'b0;
        else     r <= {r[1], r[0], d};
endmodule

`ifdef SYNTH_ICE40
// sync2 posedge srst ice40 primitives
module sync2ps_ice40 (input clk, rst, d, output wire q);
    wire q0;
    SB_DFFSR r0 (.Q(q0), .C(clk), .D(d),  .R(rst));
    SB_DFFSR r1 (.Q(q),  .C(clk), .D(q0), .R(rst));
endmodule
// sync2 posedge srst edge-detect ice40 primitives
module sync2pse_ice40 (input clk, rst, d, output wire q, pe, ne);
    wire q0, q2;
    assign pe =  q && !q2;
    assign ne = !q &&  q2;
    SB_DFFSR r0 (.Q(q0), .C(clk), .D(d),  .R(rst));
    SB_DFFSR r1 (.Q(q),  .C(clk), .D(q0), .R(rst));
    SB_DFFSR r2 (.Q(q2),  .C(clk), .D(q), .R(rst));
endmodule
`endif

// sync2 posedge srst
module sync2ps (input clk, rst, d, output wire q);
`ifdef SYNTH_ICE40
    sync2ps_ice40 s(.clk(clk), .rst(rst), .d(d), .q(q));
`else
    sync2ps_model s(.clk(clk), .rst(rst), .d(d), .q(q));
`endif
endmodule

// sync2 posedge srst edge-detect
module sync2pse (input clk, rst, d, output wire q, pe, ne);
`ifdef SYNTH_ICE40
    sync2pse_ice40 s(.clk(clk), .rst(rst), .d(d), .q(q), .pe(pe), .ne(ne));
`else
    sync2pse_model s(.clk(clk), .rst(rst), .d(d), .q(q), .pe(pe), .ne(ne));
`endif
endmodule

