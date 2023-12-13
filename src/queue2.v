/** fifo.v
 *
 * FIFOs
 *
 */

`default_nettype none
`timescale 1ns/10ps

module queue2 #(
    parameter WIDTH = 32
) (
    input                  i_clk, i_rst,
    // status
    output                 o_full,
    output                 o_empty,
    output reg       [1:0] o_vld,
    // write port
    input                  i_wr,
    input      [WIDTH-1:0] i_wr_data,
    // read port
    input                  i_rd,
    output reg [WIDTH-1:0] o_rd_data1,
    output reg [WIDTH-1:0] o_rd_data0
);

    assign o_full  = &o_vld;
    assign o_empty = !(|o_vld);
    wire write = i_wr && !o_full;
    wire read  = i_rd && !o_empty;

    always @(posedge i_clk) begin
        o_rd_data1 <= 'x;
        o_rd_data0 <= 'x;
        if (write && read) begin
            if (o_vld == 2'b11) begin
                o_rd_data1 <= i_wr_data;
                o_rd_data0 <= o_rd_data1;
            end else if (o_vld == 2'b01) begin
                o_rd_data0 <= i_wr_data;
            end
        end else if (write) begin
            if (o_vld == 2'b01) begin
                o_rd_data1 <= i_wr_data;
                o_rd_data0 <= o_rd_data0;
            end else if (o_vld == 2'b00) begin
                o_rd_data0 <= i_wr_data;
            end
        end else if (read) begin
            if (o_vld == 2'b11) begin
                o_rd_data0 <= o_rd_data1;
            end
        end else begin
            o_rd_data1 <= o_rd_data1;
            o_rd_data0 <= o_rd_data0;
        end
    end

    always @(posedge i_clk) begin
        if (i_rst)   o_vld <= 2'b00;
        else case ({ write, read, o_vld })
            // write && read
            4'b1111: o_vld <= 2'b11;
            4'b1110: o_vld <= 2'bxx;
            4'b1101: o_vld <= 2'b01;
            4'b1100: o_vld <= 2'bxx;
            // write
            4'b1011: o_vld <= 2'bxx;
            4'b1010: o_vld <= 2'bxx;
            4'b1001: o_vld <= 2'b11;
            4'b1000: o_vld <= 2'b01;
            // read
            4'b0111: o_vld <= 2'b01;
            4'b0110: o_vld <= 2'bxx;
            4'b0101: o_vld <= 2'b00;
            4'b0100: o_vld <= 2'bxx;
            // neither write nor read
            4'b0011: o_vld <= 2'b11;
            4'b0010: o_vld <= 2'b10;
            4'b0001: o_vld <= 2'b01;
            4'b0000: o_vld <= 2'b00;
            default: o_vld <= 2'bxx;
        endcase
    end

`ifdef FORMAL

    reg f_past_valid;
    initial f_past_valid <= 'b0;
    always @(posedge i_clk) f_past_valid <= 'b1;

    `ifdef FORMAL_QUEUE2_TOP
    initial assume (i_rst);
    initial assume (!i_wr);
    initial assume (!i_rd);
    always @(i_clk) if (o_full)  assume(!i_wr);
    always @(i_clk) if (o_empty) assume(!i_rd);
    `else
    always @(i_clk) if (o_full)  assert(!i_wr);
    always @(i_clk) if (o_empty) assert(!i_rd);
    `endif

    reg [3:0] f_ctrl;
    reg [3:0] f_ctrl_q;
    always @(*)             f_ctrl    = { i_wr && !o_full, i_rd && !o_empty, o_vld };
    always @(posedge i_clk) f_ctrl_q <= f_ctrl;

    reg [WIDTH-1:0] f_write1;
    reg [WIDTH-1:0] f_write0;
    always @(posedge i_clk) begin
        if (f_past_valid && !i_rst) begin
            case (f_ctrl)
                // write && read
                4'b1111: begin
                    f_write1 <= i_wr_data;
                    f_write0 <= f_write1;
                end
                4'b1101: begin
                    f_write0 <= i_wr_data;
                end
                // write
                4'b1001: begin
                    f_write1 <= i_wr_data;
                end
                4'b1000: begin
                    f_write0 <= i_wr_data;
                end
                // read
                4'b0111: begin
                    f_write0 <= f_write1;
                end
                default:;
            endcase
        end
    end

    always @(posedge i_clk) begin
        if (f_past_valid && !i_rst) begin
            assert(!o_full || !o_empty); // cannot be full and empty
            assert(o_vld != 2'b10);
            assert(f_ctrl != 4'b1100);
            assert(f_ctrl != 4'b1011);
            assert(f_ctrl != 4'b0100);

            if (!o_empty) assert(o_vld[0]);

            if (o_vld[0]) assert(o_rd_data0 == f_write0);
            if (o_vld[1]) assert(o_rd_data1 == f_write1);

            if (!$past(i_rst) && $past(f_ctrl[2:0]) == 3'b111)  assert(o_rd_data0 == $past(o_rd_data1));
            if (!$past(i_rst) && $past(f_ctrl)      == 4'b1000) assert(o_rd_data0 == $past(i_wr_data));
            if (!$past(i_rst) && $past(f_ctrl)      == 4'b1001) assert(o_rd_data1 == $past(i_wr_data));
            if (!$past(i_rst) && $past(f_ctrl)      == 4'b1101) assert(o_rd_data0 == $past(i_wr_data));
            if (!$past(i_rst) && $past(f_ctrl)      == 4'b1111) begin
                assert(o_rd_data1 == $past(i_wr_data));
                assert(o_rd_data0 == $past(o_rd_data1));
            end
        end
    end

    // count valid reads and writes (for covers)
    integer f_writes, f_reads;
    initial f_writes = 0;
    initial f_reads  = 0;
    always @(posedge i_clk) if (i_wr && !o_full)  f_writes = f_writes + 1;
    always @(posedge i_clk) if (i_rd && !o_empty) f_reads  = f_reads  + 1;

    always @(posedge i_clk) assert(f_writes >= f_reads);

    // covers
    always @(posedge i_clk) begin
        if (f_past_valid && !i_rst) begin
            c_full:   cover( o_full);
            c_nfull:  cover(!o_full);
            c_empty:  cover( o_empty);
            c_nempty: cover(!o_empty);
            c_vld00:  cover(o_vld == 2'b00);
            c_vld01:  cover(o_vld == 2'b01);
            c_vld11:  cover(o_vld == 2'b11);
            c_wr:     cover(i_wr && !o_full);
            c_rd:     cover(i_rd && !o_empty);
            c_rd3:    cover(f_reads == 3);
            c_vldnzp: cover((o_vld == 2'b11) && (o_rd_data0 != 'b0) && (o_rd_data1 != 'b0) && (o_rd_data0 != o_rd_data1) && (f_reads == 3));
        end
    end

`endif // FORMAL

endmodule
