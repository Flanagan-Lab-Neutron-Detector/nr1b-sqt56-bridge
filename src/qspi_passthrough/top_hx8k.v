/*
 * Top module for NR1B-SQT56 / protocol bridge
 */

`default_nettype none
`timescale 1ns/10ps

module top_hx8k (
    input  CLK,

    input  QSPI_CS,
    input  QSPI_SCK,
    input  QSPI_DI, // IO0
    output QSPI_DO, // IO1
    input  QSPI_IO2,
    input  QSPI_IO3,

    output FLASH_SS, FLASH_SCK, FLASH_SDO,
    input  FLASH_SDI,

    output NOR_CE, NOR_OE, NOR_WE, NOR_BYTE,
    input  NOR_RY_BY,

    output NOR_A0,  NOR_A1,  NOR_A2,  NOR_A3,
    output NOR_A4,  NOR_A5,  NOR_A6,  NOR_A7,
    output NOR_A8,  NOR_A9,  NOR_A10, NOR_A11,
    output NOR_A12, NOR_A13, NOR_A14, NOR_A15,
    output NOR_A16, NOR_A17, NOR_A18, NOR_A19,
    output NOR_A20, NOR_A21, NOR_A22, NOR_A23,
    output NOR_A24, NOR_A25,

    output NOR_DQ0,  NOR_DQ1,  NOR_DQ2,  NOR_DQ3,
    output NOR_DQ4,  NOR_DQ5,  NOR_DQ6,  NOR_DQ7,
    output NOR_DQ8,  NOR_DQ9,  NOR_DQ10, NOR_DQ11,
    output NOR_DQ12, NOR_DQ13, NOR_DQ14, NOR_DQ15,

    // extra pins
    input  TP10,
    input  TP11,
    input  IOB_73, IOB_74, IOB_82_GBIN4, IOB_87, IOB_89,
    input  IOB_91, IOB_103_CBSEL0, IOB_104_CBSEL1,
    input  IOL_5P, IOL_5N, IOL_9P, IOL_9N, IOL_12P, IOL_12N,
    input  IOL_13P, IOL_13N, IOL_14P, IOL_14N,
    input  IOL_18P, IOL_18N, IOL_23P, IOL_23N, IOL_25P, IOL_25N
);

    // QSPI / FLASH
    assign FLASH_SS  = QSPI_CS;
    assign FLASH_SCK = QSPI_SCK;
    assign FLASH_SDO = QSPI_DI;
    assign QSPI_DO   = FLASH_SDI;

    assign NOR_BYTE = 'b1;
    assign NOR_OE = 1'b1;
    assign NOR_WE = 1'b1;
    assign NOR_CE = 1'b1;
	assign {
        NOR_DQ15, NOR_DQ14, NOR_DQ13, NOR_DQ12,
        NOR_DQ11, NOR_DQ10, NOR_DQ9,  NOR_DQ8,
        NOR_DQ7,  NOR_DQ6,  NOR_DQ5,  NOR_DQ4,
        NOR_DQ3,  NOR_DQ2,  NOR_DQ1,  NOR_DQ0
    } = 'b0;
    assign {
        NOR_A25, NOR_A24,
        NOR_A23, NOR_A22, NOR_A21, NOR_A20,
        NOR_A19, NOR_A18, NOR_A17, NOR_A16,
        NOR_A15, NOR_A14, NOR_A13, NOR_A12,
        NOR_A11, NOR_A10, NOR_A9,  NOR_A8,
        NOR_A7,  NOR_A6,  NOR_A5,  NOR_A4,
        NOR_A3,  NOR_A2,  NOR_A1,  NOR_A0
    } = 'b0;

    // extra pins
    /*assign IOB_73 = 'b0;
    assign IOB_74 = 'b0;
    assign IOB_82_GBIN4 = 'b0;
    assign IOB_87 = 'b0;
    assign IOB_89 = 'b0;
    assign IOB_91 = 'b0;
    assign IOB_103_CBSEL0 = 'b0;
    assign IOB_104_CBSEL1 = 'b0;
    assign IOL_5P = 'b0;
    assign IOL_5N = 'b0;
    assign IOL_9P = 'b0;
    assign IOL_9N = 'b0;
    assign IOL_12P = 'b0;
    assign IOL_12N = 'b0;
    assign IOL_13P = 'b0;
    assign IOL_13N = 'b0;
    assign IOL_14P = 'b0;
    assign IOL_14N = 'b0;
    assign IOL_18P = 'b0;
    assign IOL_18N = 'b0;
    assign IOL_23P = 'b0;
    assign IOL_23N = 'b0;
    assign IOL_25P = 'b0;
    assign IOL_25N = 'b0;*/

endmodule
