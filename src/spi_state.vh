/** spi_state.vh
 *
 * SPI control state definitions
 */

`define SPI_STATE_BITS 3

`define SPI_STATE_CMD        3'h0
`define SPI_STATE_ADDR       3'h1
`define SPI_STATE_STALL      3'h2
`define SPI_STATE_READ_DATA  3'h3
`define SPI_STATE_WRITE_DATA 3'h4
