from typing import Tuple
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Join
from test_helpers import wb

async def setup(dut):
    """Prepare DUT for test"""

    #T = 15.15 # ~66 MHz
    #T = 13.33 # ~75 MHz
    T = 11.9 # ~84 MHz
    cocotb.start_soon(Clock(dut.clk_i, 13.33, units="ns").start())

    dut.memwb_cyc_i.value = 0
    dut.memwb_stb_i.value = 0
    dut.memwb_we_i.value = 0
    dut.memwb_adr_i.value = 0
    dut.memwb_dat_i.value = 0
    dut.cfgwb_adr_i.value = 0
    dut.cfgwb_dat_i.value = 0
    dut.cfgwb_we_i.value = 0
    dut.cfgwb_stb_i.value = 0
    dut.cfgwb_cyc_i.value = 0
    dut.nor_ry_i.value = 1

    #dut._log.info("reset")
    dut.rst_i.value = 1
    dut.cfgwb_rst_i.value = 1
    await ClockCycles(dut.clk_i, 4)
    dut.rst_i.value = 0
    dut.cfgwb_rst_i.value = 0

    assert dut.nor_data_oe.value == 0
    assert dut.memwb_ack_o.value == 0
    assert dut.memwb_stall_o.value == 0

    await ClockCycles(dut.clk_i, 1)

@cocotb.test(skip=False)
async def test_normal_read(dut):
    """Normal read"""

    await setup(dut)

    bus = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.memwb_cyc_i,
          'stb': dut.memwb_stb_i,
           'we': dut.memwb_we_i,
          'adr': dut.memwb_adr_i,
        'dat_i': dut.memwb_dat_i,
        'stall': dut.memwb_stall_o,
          'ack': dut.memwb_ack_o,
        'dat_o': dut.memwb_dat_o
    }

    # test some normal reads
    dut.nor_data_i.value = 0x5AA5
    await ClockCycles(dut.clk_i, 1)

    read_val = await wb.read(bus, 0x3080153)
    assert read_val == 0x5AA5
    await ClockCycles(dut.clk_i, 1)

    read_val = await wb.read(bus, 0x3080153)
    assert read_val == 0x5AA5
    await ClockCycles(dut.clk_i, 1)

    read_val = await wb.read(bus, 0)
    assert read_val == 0x5AA5
    await ClockCycles(dut.clk_i, 1)

    dut.nor_data_i.value = 0
    await ClockCycles(dut.clk_i, 1)
    read_val = await wb.read(bus, 0)
    assert read_val == 0
    await ClockCycles(dut.clk_i, 1)

@cocotb.test(skip=False)
async def test_aborted_read(dut):
    """Aborted read"""

    await setup(dut)

    bus = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.memwb_cyc_i,
          'stb': dut.memwb_stb_i,
           'we': dut.memwb_we_i,
          'adr': dut.memwb_adr_i,
        'dat_i': dut.memwb_dat_i,
        'stall': dut.memwb_stall_o,
          'ack': dut.memwb_ack_o,
        'dat_o': dut.memwb_dat_o
    }

    # test aborted read
    await wb.read_abort(bus, 100, after_cycles=4)
    await ClockCycles(dut.clk_i, 3)
    assert dut.memwb_ack_o.value == 0
    assert dut.memwb_stall_o.value == 0
    assert dut.nor_ce_o.value == 1
    assert dut.nor_we_o.value == 1
    assert dut.nor_oe_o.value == 1

    # test recover after aborted read
    dut.nor_data_i.value = 0x7010
    read_val = await wb.read(bus, 100)
    assert read_val == 0x7010
    await ClockCycles(dut.clk_i, 1)

@cocotb.test(skip=False)
async def test_write(dut):
    """Test normal write"""

    await setup(dut)

    bus = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.memwb_cyc_i,
          'stb': dut.memwb_stb_i,
           'we': dut.memwb_we_i,
          'adr': dut.memwb_adr_i,
        'dat_i': dut.memwb_dat_i,
        'stall': dut.memwb_stall_o,
          'ack': dut.memwb_ack_o,
        'dat_o': dut.memwb_dat_o
    }

    await wb.write(bus, 0x3F0F0, 0x9876)
    await ClockCycles(dut.clk_i, 1)
    assert dut.nor_data_o.value == 0x9876

    await ClockCycles(dut.clk_i, 4)

@cocotb.test(skip=False)
async def test_pipeline(dut):
    """Test pipelined operations"""

    await setup(dut)

    bus = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.memwb_cyc_i,
          'stb': dut.memwb_stb_i,
           'we': dut.memwb_we_i,
          'adr': dut.memwb_adr_i,
        'dat_i': dut.memwb_dat_i,
        'stall': dut.memwb_stall_o,
          'ack': dut.memwb_ack_o,
        'dat_o': dut.memwb_dat_o
    }

    addrs = [1, 2, 100, 1351, 38510]

    async def set_data(oe, ack, dat_i, N):
        dat_i.value = 1
        await FallingEdge(oe)
        for i in range(1,N):
            await RisingEdge(ack)
            dat_i.value = i+1
    set_data_task = cocotb.start_soon(set_data(dut.nor_oe_o, bus['ack'], dut.nor_data_i, len(addrs)))

    #dut.nor_data_i.value = 0x1357
    addr_data = await wb.multi_read(bus, addrs, timeout=1000, log=dut._log.info)
    await Join(set_data_task)
    await ClockCycles(dut.clk_i, 1)

    assert len(addr_data) == len(addrs)
    for i,ad in enumerate(addr_data):
        assert int(ad[0]) == addrs[i]
        assert int(ad[1]) == i + 1

    await ClockCycles(dut.clk_i, 10)

@cocotb.test()
async def test_cfg_read(dut):
    """Read cfg registers"""

    await setup(dut)

    memwb = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.memwb_cyc_i,
          'stb': dut.memwb_stb_i,
           'we': dut.memwb_we_i,
          'adr': dut.memwb_adr_i,
        'dat_i': dut.memwb_dat_i,
        'stall': dut.memwb_stall_o,
          'ack': dut.memwb_ack_o,
        'dat_o': dut.memwb_dat_o
    }

    cfgwb = {
          'clk': dut.clk_i,
          'rst': dut.cfgwb_rst_i,
          'cyc': dut.cfgwb_cyc_i,
          'stb': dut.cfgwb_stb_i,
           'we': dut.cfgwb_we_i,
          'adr': dut.cfgwb_adr_i,
        'dat_i': dut.cfgwb_dat_i,
        'stall': dut.cfgwb_stall_o,
          'ack': dut.cfgwb_ack_o,
        'dat_o': dut.cfgwb_dat_o
    }

    await ClockCycles(dut.clk_i, 1)

    reg_def = [
        # (register addr, default value)
        (0x0100, 0x0001), # R_NBUSCTRL
        (0x0101, 0x4F0E), # R_NBUSWAIT0
        (0x0102, 0x1115), # R_NBUSWAIT1
    ]

    for a,d in reg_def:
        read_val = await wb.read(cfgwb, a)
        assert read_val == d, f"Reg {a:04X} = {int(read_val):04X} (expected {d:04X})"
        await ClockCycles(dut.clk_i, 1)

@cocotb.test()
async def test_cfg_write(dut):
    """Read cfg registers"""

    await setup(dut)

    memwb = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.memwb_cyc_i,
          'stb': dut.memwb_stb_i,
           'we': dut.memwb_we_i,
          'adr': dut.memwb_adr_i,
        'dat_i': dut.memwb_dat_i,
        'stall': dut.memwb_stall_o,
          'ack': dut.memwb_ack_o,
        'dat_o': dut.memwb_dat_o
    }

    cfgwb = {
          'clk': dut.clk_i,
          'rst': dut.cfgwb_rst_i,
          'cyc': dut.cfgwb_cyc_i,
          'stb': dut.cfgwb_stb_i,
           'we': dut.cfgwb_we_i,
          'adr': dut.cfgwb_adr_i,
        'dat_i': dut.cfgwb_dat_i,
        'stall': dut.cfgwb_stall_o,
          'ack': dut.cfgwb_ack_o,
        'dat_o': dut.cfgwb_dat_o
    }

    await ClockCycles(dut.clk_i, 1)

    reg_val = [
        # (register addr, write value)
        (0x0100, 0xFEDC), # R_NBUSCTRL
        (0x0101, 0x2011), # R_NBUSWAIT0
        (0x0102, 0x1410), # R_NBUSWAIT1
    ]

    for a,d in reg_val:
        await wb.write(cfgwb, a, d)
        await ClockCycles(dut.clk_i, 1)

    for a,d in reg_val:
        read_val = await wb.read(cfgwb, a)
        assert read_val == d, f"Reg {a:04X} = {int(read_val):04X} (expected {d:04X})"
        await ClockCycles(dut.clk_i, 1)

