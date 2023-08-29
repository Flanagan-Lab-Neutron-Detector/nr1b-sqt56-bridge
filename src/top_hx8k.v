/*
 * Top module for NR1B-SQT56 / protocol bridge
 */

module top_hx8k (
    input  CLK,

    input QSPI_CS,
    input QSPI_SCK,
    inout QSPI_IO0,
    inout QSPI_IO1,
    inout QSPI_IO2,
    inout QSPI_IO3,

    output NOR_CE, NOR_OE, NOR_WE, NOR_BYTE,
    input  NOR_RY_BY,

    output NOR_A0,  NOR_A1,  NOR_A2,  NOR_A3,
    output NOR_A4,  NOR_A5,  NOR_A6,  NOR_A7,
    output NOR_A8,  NOR_A9,  NOR_A10, NOR_A11,
    output NOR_A12, NOR_A13, NOR_A14, NOR_A15,
    output NOR_A16, NOR_A17, NOR_A18, NOR_A19,
    output NOR_A20, NOR_A21, NOR_A22, NOR_A23,
    output NOR_A24, NOR_A25,

    inout  NOR_DQ0,  NOR_DQ1,  NOR_DQ2,  NOR_DQ3,
    inout  NOR_DQ4,  NOR_DQ5,  NOR_DQ6,  NOR_DQ7,
    inout  NOR_DQ8,  NOR_DQ9,  NOR_DQ10, NOR_DQ11,
    inout  NOR_DQ12, NOR_DQ13, NOR_DQ14, NOR_DQ15,

    // extra pins
    output TP10,
    output TP11,
    input  FLASH_SS, FLASH_SCK, FLASH_SDI, FLASH_SDO,
    output IOB_73, IOB_74, IOB_82_GBIN4, IOB_87, IOB_89,
    output IOB_91, IOB_103_CBSEL0, IOB_104_CBSEL1,
    output IOL_5P, IOL_5N, IOL_9P, IOL_9N, IOL_12P, IOL_12N,
    output IOL_13P, IOL_13N, IOL_14P, IOL_14N,
    output IOL_18P, IOL_18N, IOL_23P, IOL_23N, IOL_25P, IOL_25N
);

	// PLL to get 240MHz clock
	(* gb_clk *) wire       sysclk;
	wire       locked;
    wire       int_reset_n;
    assign int_reset_n = locked;
    // TODO: global clock input
	pll_pad pll (.clock_in(CLK), .clock_out(sysclk), .locked(locked));
    assign TP10 = 'b0; //sysclk;
    assign TP11 = locked;

	wire [15:0] nor_dq_i;
    reg  [15:0] nor_dq_o;
    reg nor_dq_oe;

    // Debug outputs
    reg        dbg_txnmode, dbg_txndir, dbg_txndone;
    reg  [7:0] dbg_txncc;
    reg [31:0] dbg_txnmosi, dbg_txnmiso;
    wire       dbg_wb_ctrl_stb;
    wire       dbg_wb_nor_stb;
    wire       dbg_vt_mode;

    /*
    assign IOB_73 = dbg_wb_ctrl_stb;
    assign IOB_74 = dbg_wb_nor_stb;
    assign IOB_91 = dbg_txndone;
    */
    assign IOB_73 = NOR_CE;

    // extra pins
    //assign FLASH_SS  = 'bz;
    //assign FLASH_SCK = 'bz;
    //assign FLASH_SDI = 'bz;
    //assign FLASH_SDO = 'bz;
    //assign IOB_73 = 'b0;
    //assign IOB_74 = 'b0;
    assign IOB_82_GBIN4 = 'b0;
    assign IOB_87 = 'b0;
    assign IOB_89 = 'b0;
    //assign IOB_91 = 'b0;
    assign IOB_103_CBSEL0 = 'b0;
    assign IOB_104_CBSEL1 = 'b0;
    //assign IOL_5P = 'b0;
    //assign IOL_5N = 'b0;
    //assign IOL_9P = 'b0;
    //assign IOL_9N = 'b0;
    assign IOL_12P = 'b0;
    assign IOL_12N = 'b0;
    //assign IOL_13P = 'b0;
    //assign IOL_13N = 'b0;
    //assign IOL_14P = 'b0;
    //assign IOL_14N = 'b0;
    assign IOL_18P = 'b0;
    assign IOL_18N = 'b0;
    assign IOL_23P = 'b0;
    assign IOL_23N = 'b0;
    assign IOL_25P = 'b0;
    assign IOL_25N = 'b0;

    // QSPI pins

    wire [3:0] qspi_io_i, qspi_io_o;
    wire qspi_io_oe;
    /*
    assign qspi_io_i = { QSPI_IO0, QSPI_IO1, QSPI_IO2, QSPI_IO3 };
    assign {
        QSPI_IO0, QSPI_IO1, QSPI_IO2, QSPI_IO3
    } = qspi_io_oe ? qspi_io_o : 'bz;
    */

    // QSPI_IO0
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_qspi_io0 (
        .PACKAGE_PIN(QSPI_IO0),
        .OUTPUT_ENABLE(qspi_io_oe),
        .D_OUT_0(qspi_io_o[0]),
        //.D_OUT_0(1'b0),
        .D_IN_0(qspi_io_i[0])
    );

    // QSPI_IO1
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_qspi_io1 (
        .PACKAGE_PIN(QSPI_IO1),
        .OUTPUT_ENABLE(qspi_io_oe),
        .D_OUT_0(qspi_io_o[1]),
        //.D_OUT_0(1'b0),
        .D_IN_0(qspi_io_i[1])
    );

    // QSPI_IO2
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_qspi_io2 (
        .PACKAGE_PIN(QSPI_IO2),
        .OUTPUT_ENABLE(qspi_io_oe),
        .D_OUT_0(qspi_io_o[2]),
        .D_IN_0(qspi_io_i[2])
    );

    // QSPI_IO3
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_qspi_io3 (
        .PACKAGE_PIN(QSPI_IO3),
        .OUTPUT_ENABLE(qspi_io_oe),
        .D_OUT_0(qspi_io_o[3]),
        .D_IN_0(qspi_io_i[3])
    );

    // NOR DQ

	/*assign nor_dq_i = {
        NOR_DQ15, NOR_DQ14, NOR_DQ13, NOR_DQ12,
        NOR_DQ11, NOR_DQ10, NOR_DQ9,  NOR_DQ8,
        NOR_DQ7,  NOR_DQ6,  NOR_DQ5,  NOR_DQ4,
        NOR_DQ3,  NOR_DQ2,  NOR_DQ1,  NOR_DQ0
    };
	assign {
        NOR_DQ15, NOR_DQ14, NOR_DQ13, NOR_DQ12,
        NOR_DQ11, NOR_DQ10, NOR_DQ9,  NOR_DQ8,
        NOR_DQ7,  NOR_DQ6,  NOR_DQ5,  NOR_DQ4,
        NOR_DQ3,  NOR_DQ2,  NOR_DQ1,  NOR_DQ0
    } = nor_dq_oe ? nor_dq_o : 'bz;*/

    // NOR_DQ0
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_nor_dq0 (
        .PACKAGE_PIN(NOR_DQ0),
        .OUTPUT_ENABLE(nor_dq_oe),
        .D_OUT_0(nor_dq_o[0]),
        .D_IN_0(nor_dq_i[0])
    );

    // NOR_DQ1
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_nor_dq1 (
        .PACKAGE_PIN(NOR_DQ1),
        .OUTPUT_ENABLE(nor_dq_oe),
        .D_OUT_0(nor_dq_o[1]),
        .D_IN_0(nor_dq_i[1])
    );

    // NOR_DQ2
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_nor_dq2 (
        .PACKAGE_PIN(NOR_DQ2),
        .OUTPUT_ENABLE(nor_dq_oe),
        .D_OUT_0(nor_dq_o[2]),
        .D_IN_0(nor_dq_i[2])
    );

    // NOR_DQ3
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_nor_dq3 (
        .PACKAGE_PIN(NOR_DQ3),
        .OUTPUT_ENABLE(nor_dq_oe),
        .D_OUT_0(nor_dq_o[3]),
        .D_IN_0(nor_dq_i[3])
    );

    // NOR_DQ4
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_nor_dq4 (
        .PACKAGE_PIN(NOR_DQ4),
        .OUTPUT_ENABLE(nor_dq_oe),
        .D_OUT_0(nor_dq_o[4]),
        .D_IN_0(nor_dq_i[4])
    );

    // NOR_DQ5
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_nor_dq5 (
        .PACKAGE_PIN(NOR_DQ5),
        .OUTPUT_ENABLE(nor_dq_oe),
        .D_OUT_0(nor_dq_o[5]),
        .D_IN_0(nor_dq_i[5])
    );

    // NOR_DQ6
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_nor_dq6 (
        .PACKAGE_PIN(NOR_DQ6),
        .OUTPUT_ENABLE(nor_dq_oe),
        .D_OUT_0(nor_dq_o[6]),
        .D_IN_0(nor_dq_i[6])
    );

    // NOR_DQ7
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_nor_dq7 (
        .PACKAGE_PIN(NOR_DQ7),
        .OUTPUT_ENABLE(nor_dq_oe),
        .D_OUT_0(nor_dq_o[7]),
        .D_IN_0(nor_dq_i[7])
    );

    // NOR_DQ8
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_nor_dq8 (
        .PACKAGE_PIN(NOR_DQ8),
        .OUTPUT_ENABLE(nor_dq_oe),
        .D_OUT_0(nor_dq_o[8]),
        .D_IN_0(nor_dq_i[8])
    );

    // NOR_DQ9
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_nor_dq9 (
        .PACKAGE_PIN(NOR_DQ9),
        .OUTPUT_ENABLE(nor_dq_oe),
        .D_OUT_0(nor_dq_o[9]),
        .D_IN_0(nor_dq_i[9])
    );

    // NOR_DQ10
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_nor_dq10 (
        .PACKAGE_PIN(NOR_DQ10),
        .OUTPUT_ENABLE(nor_dq_oe),
        .D_OUT_0(nor_dq_o[10]),
        .D_IN_0(nor_dq_i[10])
    );

    // NOR_DQ11
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_nor_dq11 (
        .PACKAGE_PIN(NOR_DQ11),
        .OUTPUT_ENABLE(nor_dq_oe),
        .D_OUT_0(nor_dq_o[11]),
        .D_IN_0(nor_dq_i[11])
    );

    // NOR_DQ12
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_nor_dq12 (
        .PACKAGE_PIN(NOR_DQ12),
        .OUTPUT_ENABLE(nor_dq_oe),
        .D_OUT_0(nor_dq_o[12]),
        .D_IN_0(nor_dq_i[12])
    );

    // NOR_DQ13
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_nor_dq13 (
        .PACKAGE_PIN(NOR_DQ13),
        .OUTPUT_ENABLE(nor_dq_oe),
        .D_OUT_0(nor_dq_o[13]),
        .D_IN_0(nor_dq_i[13])
    );

    // NOR_DQ14
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_nor_dq14 (
        .PACKAGE_PIN(NOR_DQ14),
        .OUTPUT_ENABLE(nor_dq_oe),
        .D_OUT_0(nor_dq_o[14]),
        .D_IN_0(nor_dq_i[14])
    );

    // NOR_DQ15
    SB_IO #(
        .PIN_TYPE(6'b1010_01),
        .PULLUP(1'b0),
    ) sb_io_nor_dq15 (
        .PACKAGE_PIN(NOR_DQ15),
        .OUTPUT_ENABLE(nor_dq_oe),
        .D_OUT_0(nor_dq_o[15]),
        .D_IN_0(nor_dq_i[15])
    );

	// NOR addresses

    wire [25:0] nor_addr;
    assign {
        NOR_A25, NOR_A24, NOR_A23, NOR_A22, NOR_A21,
        NOR_A20, NOR_A19, NOR_A18, NOR_A17, NOR_A16,
        NOR_A15, NOR_A14, NOR_A13, NOR_A12, NOR_A11,
        NOR_A10, NOR_A9,  NOR_A8,  NOR_A7,  NOR_A6,
        NOR_A5,  NOR_A4,  NOR_A3,  NOR_A2,  NOR_A1,
        NOR_A0
    } = nor_addr;

    //wire [15:0] nor_dq_o_in;

    assign {
        IOL_14P, IOL_14N, IOL_13P, IOL_13N
    } = nor_addr[19:16];
    assign {
        IOL_9P,  IOL_9N,  IOL_5P,  IOL_5N
    } = qspi_io_i[3:0];
    //assign IOB_74 = nor_dq_o_in[15];
    //assign IOB_91 = nor_dq_o_in[14];
    assign IOB_74 = NOR_WE;
    assign IOB_91 = 0;

    //always @(posedge sysclk)
        //nor_dq_o <= nor_dq_o_in;

    // NOR control
    assign NOR_BYTE = 'b1;

    top top (
        .reset_i(!int_reset_n), .clk_i(sysclk),
        // QSPI
        .qspi_io_i(qspi_io_i), .qspi_io_o(qspi_io_o), .qspi_io_oe(qspi_io_oe),
        .qspi_sck(QSPI_SCK), .qspi_sce(QSPI_CS),
        // NOR
        .nor_addr_o(nor_addr), .nor_data_i(nor_dq_i), .nor_data_o(nor_dq_o),
        .nor_data_oe(nor_dq_oe), .nor_ry_i(NOR_RY_BY),
        .nor_ce_o(NOR_CE), .nor_we_o(NOR_WE), .nor_oe_o(NOR_OE),
        // debug
        .dbg_txnmode(dbg_txnmode), .dbg_txndir(dbg_txndir), .dbg_txndone(dbg_txndone),
        .dbg_txncc(dbg_txncc), .dbg_txnmosi(dbg_txnmosi), .dbg_txnmiso(dbg_txnmiso),
        .dbg_wb_ctrl_stb(dbg_wb_ctrl_stb), .dbg_wb_nor_stb(dbg_wb_nor_stb), .dbg_vt_mode(dbg_vt_mode)
    );

endmodule
