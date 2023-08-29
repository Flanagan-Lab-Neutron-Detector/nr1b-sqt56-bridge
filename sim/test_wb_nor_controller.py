from typing import Tuple, Iterator
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles
from test_helpers import wb

async def setup(dut):
    """Setup DUT"""

    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())

    dut.wbs_cyc_i.value = 0
    dut.wbs_stb_i.value = 0
    dut.wbs_we_i.value = 0
    dut.wbs_adr_i.value = 0
    dut.wbs_dat_i.value = 0

    dut.wbm_stall_i.value = 0
    dut.wbm_ack_i.value = 0
    dut.wbm_dat_i.value = 0x3176

    dut.rst_i.value = 1
    await ClockCycles(dut.clk_i, 5)
    dut.rst_i.value = 0

    assert dut.wbs_ack_o == 0
    assert dut.wbs_stall_o == 0

@cocotb.test()
async def test_read(dut):
    """Test read"""

    await setup(dut)

    bus_s = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wbs_cyc_i,
          'stb': dut.wbs_stb_i,
           'we': dut.wbs_we_i,
          'adr': dut.wbs_adr_i,
        'dat_o': dut.wbs_dat_o,
        'stall': dut.wbs_stall_o,
          'ack': dut.wbs_ack_o,
        'dat_i': dut.wbs_dat_i
    }

    bus = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wbm_cyc_o,
          'stb': dut.wbm_stb_o,
           'we': dut.wbm_we_o,
          'adr': dut.wbm_adr_o,
        'dat_o': dut.wbm_dat_i,
        'stall': dut.wbm_stall_i,
          'ack': dut.wbm_ack_i,
        'dat_i': dut.wbm_dat_o
    }
    #stub = slave_monitor(bus, data=0x3456, stall_cycles=4, log=dut._log.info)
    stub = wb.slave_read_expect(bus, 0x80, data=0x3456, timeout=100, stall_cycles=4, log=dut._log.info)
    stub_routine = cocotb.start_soon(stub)

    ret_val = await wb.read(bus_s, 0x00000080)
    assert int(ret_val) == 0x3456

    #stub_routine.kill()
    await ClockCycles(dut.clk_i, 1)

@cocotb.test()
async def test_simple_command(dut):
    """Test sending a single-cycle command"""

    await setup(dut)

    bus_s = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wbs_cyc_i,
          'stb': dut.wbs_stb_i,
           'we': dut.wbs_we_i,
          'adr': dut.wbs_adr_i,
        'dat_o': dut.wbs_dat_i,
        'stall': dut.wbs_stall_o,
          'ack': dut.wbs_ack_o,
        'dat_i': dut.wbs_dat_o
    }

    bus = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wbm_cyc_o,
          'stb': dut.wbm_stb_o,
           'we': dut.wbm_we_o,
          'adr': dut.wbm_adr_o,
        'dat_o': dut.wbm_dat_i,
        'stall': dut.wbm_stall_i,
          'ack': dut.wbm_ack_i,
        'dat_i': dut.wbm_dat_o
    }

    stub = wb.slave_write_expect(bus, 0, 0xf0, timeout=100, stall_cycles=4, log=dut._log.info)
    stub_routine = cocotb.start_soon(stub)

    # send reset command
    # top 6 bits are command, reset is 6'h05
    # address is don't-care, data is don't-care
    await wb.write(bus_s, 0x14000000, 0)

    #stub_routine.kill()
    await ClockCycles(dut.clk_i, 4)

@cocotb.test()
async def test_ext_command(dut):
    """Test sending a multicycle command"""

    await setup(dut)

    bus_s = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wbs_cyc_i,
          'stb': dut.wbs_stb_i,
           'we': dut.wbs_we_i,
          'adr': dut.wbs_adr_i,
        'dat_o': dut.wbs_dat_i,
        'stall': dut.wbs_stall_o,
          'ack': dut.wbs_ack_o,
        'dat_i': dut.wbs_dat_o
    }

    bus = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wbm_cyc_o,
          'stb': dut.wbm_stb_o,
           'we': dut.wbm_we_o,
          'adr': dut.wbm_adr_o,
        'dat_o': dut.wbm_dat_i,
        'stall': dut.wbm_stall_i,
          'ack': dut.wbm_ack_i,
        'dat_i': dut.wbm_dat_o
    }

    erase_sector_pairs = [
        (0x555, 0xaa),
        (0x2aa, 0x55),
        (0x555, 0x80),
        (0x555, 0xaa),
        (0x2aa, 0x55),
        (0x50000, 0x30)
    ]
    stub = wb.slave_write_multi_expect(bus, erase_sector_pairs, timeout=100, stall_cycles=2, log=dut._log.info)
    stub_routine = cocotb.start_soon(stub)

    # send erase sector command
    # top 6 bits are command, erase sector is 6'b000011
    # bottom 26 are address, of which top 10 are sector address. Here data doesn't matter
    # Let's select sector 5
    await wb.write(bus_s, 0x0C050000, 0)

    stub_routine.kill()
    await ClockCycles(dut.clk_i, 4)
