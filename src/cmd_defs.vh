/** cmd_defs.v
 *
 * Common command definitions
 */

// SPI commands
`define SPI_COMMAND_READ       8'h03
`define SPI_COMMAND_FAST_READ  8'h0B
`define SPI_COMMAND_PAGE_PROG  8'h02
`define SPI_COMMAND_BULK_ERASE 8'h60
`define SPI_COMMAND_SECT_ERASE 8'hD8
`define SPI_COMMAND_PROG_WORD  8'hF2
`define SPI_COMMAND_RESET      8'hF0
`define SPI_COMMAND_WRITE_THRU 8'hF8
`define SPI_COMMAND_LOOPBACK   8'hFA
`define SPI_COMMAND_DET_VT     8'hFB
