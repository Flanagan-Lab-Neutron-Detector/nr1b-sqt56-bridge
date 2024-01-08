/** ctrl.v
 *
 * Controller
 *
 */

`include "cmd_defs.vh"
`include "busmap.vh"
`include "spi_state.vh"

`default_nettype none
`timescale 1ns/10ps

module ctrl #(
    parameter SPICMDBITS    = `SPI_CMD_BITS,
    parameter SPIADDRBITS   = `SPI_ADDR_BITS,
    parameter SPIDATABITS   = `SPI_DATA_BITS,
    parameter MEMWBADDRBITS = `NORADDRBITS,
    parameter MEMWBDATABITS = `NORDATABITS,
    parameter CFGWBADDRBITS = `CFGWBADDRBITS,
    parameter CFGWBDATABITS = `CFGWBDATABITS
) (
    input i_clk, i_sysrst,

    input                            i_spirst,
    //input                            i_spistb,
    input                            i_spistbcmd,
    input                            i_spistbadr,
    input                            i_spistbrrq,
    input                            i_spistbwrq,
    input      [`SPI_STATE_BITS-1:0] i_spistate,
    input           [SPICMDBITS-1:0] i_spicmd,
    input          [SPIADDRBITS-1:0] i_spiaddr,
    input          [SPIDATABITS-1:0] i_spidata,
    output         [SPIDATABITS-1:0] o_spidata,

    // memory wishbone
    output reg                        o_memwb_cyc,
    output reg                        o_memwb_stb,
    output reg                        o_memwb_we,
    output reg    [MEMWBADDRBITS-1:0] o_memwb_adr,
    output reg    [MEMWBDATABITS-1:0] o_memwb_dat,
    input                             i_memwb_err,
    input                             i_memwb_ack,
    input                             i_memwb_stall,
    input         [MEMWBDATABITS-1:0] i_memwb_dat,

    // cfg wishbone
    output                            o_cfgwb_rst,
    output reg    [CFGWBADDRBITS-1:0] o_cfgwb_adr,
    output reg    [CFGWBDATABITS-1:0] o_cfgwb_dat,
    output reg                        o_cfgwb_we,
    output reg                        o_cfgwb_stb, // TODO: one stb per peripheral
    output reg                        o_cfgwb_cyc,
    input                             i_cfgwb_err,
    input                             i_cfgwb_ack,
    input         [CFGWBDATABITS-1:0] i_cfgwb_dat,
    input                             i_cfgwb_stall,

    output reg                        o_vtmode
);

    // VT override control
    always @(posedge i_clk)
        if (i_sysrst)
            o_vtmode <= 'b0;
        else if (i_spirst) begin
            if (i_spicmd == `SPI_COMMAND_DET_VT)
                o_vtmode <= 'b1;
            else if (i_spicmd == `SPI_COMMAND_WRITE_THRU && i_spidata == 16'h00F0)
                o_vtmode <= 'b0;
        end

    // address counter
    reg  [SPIADDRBITS-1:0]   addr_count;
    wire [MEMWBADDRBITS-1:0] memaddr;
    wire [SPIADDRBITS-MEMWBADDRBITS-1:0] ctrladdr;
    wire addr_latch = i_spistbadr; // i_spistb && (i_spistate == `SPI_STATE_ADDR);
    wire addr_inc   = o_memwb_stb;
    //reg  addr_latch;
    //always @(posedge i_clk) addr_latch <= i_spistb && (i_spistate == `SPI_STATE_ADDR);
    upcounter #(.BITS(SPIADDRBITS)) addr_counter (
        .i_clk(i_clk), .i_rst(i_sysrst),
        .i_load(addr_latch), .i_en(addr_inc),
        .i_load_val(i_spiaddr), .o_count(addr_count)
    );
    assign memaddr  = addr_count[MEMWBADDRBITS-1:0];
    assign ctrladdr = addr_count[SPIADDRBITS-1:MEMWBADDRBITS];

    // (wb) read/write request generation
    //
    // write direction
    wire cmd_is_write;
    assign cmd_is_write = !((i_spicmd == `SPI_COMMAND_READ) || (i_spicmd == `SPI_COMMAND_FAST_READ));

    // memwb / cfgwb routing
    wire bus_is_cfg = i_spiaddr[SPIADDRBITS-1]; //ctrladdr[SPIADDRBITS-MEMWBADDRBITS-1];
    reg  [CFGWBDATABITS-1:0] cfgwb_dat_q;
    reg  [MEMWBDATABITS-1:0] pipe_fifo_rd_data;
    assign o_spidata[MEMWBDATABITS-1:0] = bus_is_cfg ? cfgwb_dat_q : pipe_fifo_rd_data;

    // cfgwb control
    assign o_cfgwb_rst = i_sysrst;
    reg cfg_req_read, cfg_req_write;
    always @(posedge i_clk) begin
        cfg_req_read  <= 'b0;
        cfg_req_write <= 'b0;
        if (!o_cfgwb_cyc && !i_cfgwb_stall) begin
            cfg_req_read  <= i_spistbrrq;
            cfg_req_write <= i_spistbwrq;
        end
        /*if (!o_cfgwb_cyc && !i_cfgwb_stall && i_spistb) begin
            cfg_req_read  <= !cmd_is_write && (i_spistate == `SPI_STATE_ADDR);
            cfg_req_write <=  cmd_is_write && (i_spistate == `SPI_STATE_WRITE_DATA);
        end*/
    end
    always @(posedge i_clk) begin
        o_cfgwb_adr <= 'b0;
        o_cfgwb_dat <= 'b0;
        o_cfgwb_we  <= 'b0;
        o_cfgwb_stb <= 'b0;
        if (o_cfgwb_rst || i_cfgwb_err) begin
            o_cfgwb_cyc <= 'b0;
            cfgwb_dat_q <= 'b0;
        end else if (bus_is_cfg) begin
            if (!o_cfgwb_cyc && !i_cfgwb_stall && (cfg_req_read || cfg_req_write)) begin
                o_cfgwb_cyc <= 'b1;
                o_cfgwb_stb <= 'b1;
                o_cfgwb_adr <= addr_count[CFGWBADDRBITS-1:0];
                if (cfg_req_write) begin
                    o_cfgwb_dat <= i_spidata;
                    o_cfgwb_we  <= 'b1;
                end else if (cfg_req_read) begin
                    o_cfgwb_we  <= 'b0;
                end
            end else if (o_cfgwb_cyc && i_cfgwb_ack) begin
                o_cfgwb_cyc <= 'b0;
                cfgwb_dat_q <= i_cfgwb_dat;
            end
        end
    end

    // memwb control
    reg memwb_write_req, memwb_read_req, memwb_req;
    always @(*) memwb_req = memwb_write_req || memwb_read_req;

    // pipeline management
    // Ack FIFO
    wire pipe_fifo_full, pipe_fifo_empty;
    wire [4:0] pipe_fifo_filled;
    reg  pipe_fifo_wr;
    wire pipe_fifo_rd;
    reg  [MEMWBDATABITS-1:0] pipe_fifo_wr_data;
    fsfifo #(.WIDTH(MEMWBDATABITS), .DEPTH(16)) pipe_fifo (
        .clk_i(i_clk), .reset_i(i_sysrst || i_spirst),
        .full_o(pipe_fifo_full), .empty_o(pipe_fifo_empty),
        .filled_o(pipe_fifo_filled),
        .wr_i(pipe_fifo_wr), .wr_data_i(pipe_fifo_wr_data),
        .rd_i(pipe_fifo_rd), .rd_data_o(pipe_fifo_rd_data)
    );

    assign pipe_fifo_rd = i_spistbrrq;

    // Read acks go to a 16-deep FIFO. FIFO filled + pending reqs must be <= 16 or data will be lost
    reg  [4:0] pipe_inflight;
    wire [4:0] pipe_total = pipe_fifo_filled + pipe_inflight + (pipe_fifo_wr?'b1:'b0);
    wire inflight_empty = pipe_inflight == 'b0;
    wire pipeline_full = pipe_total[4];
    wire pipeline_almost_full = &pipe_total[3:0];

    // track inflight requests
    wire pipe_valid_wr = o_memwb_stb;
    wire pipe_valid_rd = i_memwb_ack && !inflight_empty;
    always @(posedge i_clk) begin
        if (i_sysrst || i_spirst) pipe_inflight <= 'b0;
        else case ({ pipe_valid_wr, pipe_valid_rd })
            2'b01: pipe_inflight <= inflight_empty ? 'x : pipe_inflight - 1;
            2'b10: pipe_inflight <= pipeline_full  ? 'x : pipe_inflight + 1;
            default: pipe_inflight <= pipe_inflight;
        endcase
    end

    // stb control
    reg stb, stb_d;
    always @(*)             stb_d     = !i_sysrst && !i_memwb_stall && memwb_req;
    always @(posedge i_clk) stb      <= stb_d;
    always @(*)             o_memwb_stb = stb && !i_memwb_stall;

    // write request generation
    //always @(posedge i_clk) memwb_write_req <= !bus_is_cfg && i_spistb && (i_spistate == `SPI_STATE_WRITE_DATA);
    always @(posedge i_clk) memwb_write_req <= !bus_is_cfg && i_spistbwrq;

    // read request generation
    always @(posedge i_clk) begin
        memwb_read_req <= 'b0;
        if (!bus_is_cfg && !pipeline_full && !(pipeline_almost_full && (stb_d || o_memwb_stb))) begin
            if (!cmd_is_write && ((i_spistate == `SPI_STATE_READ_DATA) || (i_spistate == `SPI_STATE_STALL)) && !i_spirst) begin
                memwb_read_req <= 'b1;
            end else if (i_spistbrrq)
                // true when address phase finishes -- this will be the first pipelined read request
                memwb_read_req <= !cmd_is_write;
        end
    end

    // Wishbone control

    always @(*) o_memwb_adr = memaddr;
    always @(posedge i_clk) begin
        pipe_fifo_wr      <= 'b0;
        pipe_fifo_wr_data <= 'b0;
        o_memwb_we        <= 'b0;
        if (i_sysrst) begin
            o_memwb_cyc <= 'b0;
            o_memwb_dat <= 'b0;
        end else begin
            if (o_memwb_cyc && i_memwb_ack) begin
                if (inflight_empty)
                    o_memwb_cyc <= 'b0;
                pipe_fifo_wr      <= 'b1;
                pipe_fifo_wr_data <= i_memwb_dat;
            end

            if (memwb_read_req && i_spirst) begin
                o_memwb_cyc <= 'b0;
                o_memwb_dat <= 'b0;
            end else if (memwb_req && !i_memwb_stall) begin
                o_memwb_cyc <= 'b1;
                o_memwb_we  <= cmd_is_write;
                o_memwb_dat <= i_spidata;
            end
        end
    end

endmodule
