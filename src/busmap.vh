/** busmap.vh
 *
 * Address map and bus widths
 */

// Buses

// NOR
`define NORADDRBITS   26
`define NORDATABITS   16

// SPI
`define SPI_CMD_BITS  8
`define SPI_ADDR_BITS 32
`define SPI_WAIT_CYC  20
`define SPI_DATA_BITS `NORDATABITS

// Internal CFG WB
`define CFGWBADDRBITS 16
`define CFGWBDATABITS `NORDATABITS

// Address masks (masks QSPI addr)
`define NORADDRMASK   {(`NORADDRBITS){1'b1}} //32'h03FFFFFF
`define CFGADDRMASK   {(`CFGWBADDRBITS){1'b1}} //32'h0000FFFF
`define CTRLBIT       31 // SPI addr high bit. 0 = nor request, 1 = management request
`define CTRLBITMASK   ('1 << `CTRLBIT)

// CFG address maps

`define CFGWBMODMASK  16'hFF00
`define CFGWBREGMASK  15'h00FF

// modules
`define QSPIADDRBASE  16'h0000 // qspi_ctrl_frm
`define NBUSADDRBASE  16'h0100 // nor_bus

// QSPI regs
`define R_QSPICTRL    16'h0001
// R_QSPICTRL bits
`define R_QSPICTRL_RPEN_BIT 16'h0001
`define R_QSPICTRL_WPEN_BIT 16'h0002
`define R_QSPICTRL_VTEN_BIT 16'h0004

// NOR bus regs
`define R_NBUSCTRL    16'h0100
`define R_NBUSWAIT    16'h0101
// R_NBUSCTRL bits
// R_NBUSWAIT bits
