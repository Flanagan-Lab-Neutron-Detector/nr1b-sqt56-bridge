from typing import Tuple
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Join
from test_helpers import wb

async def wb_read_double(dut, addr1: int, addr2: int, after_cycles=1, indata1=None, indata2=None) -> Tuple[int,int]:
    if dut.wb_cyc_i.value:
        raise Exception("Transaction already in progress")
    if dut.wb_stall_o.value:
        await FallingEdge(dut.wb_stall_o)
        await ClockCycles(dut.clk_i, 1)

    # To avoid affecting earlier transactions, only change nor_data_i on
    # rising ack (guaranteed after the nor input latches). However, still
    # change the bus request earlier

    # initiate cycle: cyc high, stb high, we low, assert address
    dut.wb_adr_i.value = addr1
    dut.wb_cyc_i.setimmediatevalue(1)
    dut.wb_stb_i.setimmediatevalue(1)
    dut.wb_we_i.value = 0
    if indata1 is not None:
        dut.nor_data_i.value = indata1
    await ClockCycles(dut.clk_i, 2)

    await ClockCycles(dut.clk_i, after_cycles)
    # set up second transaction
    dut.wb_adr_i.value = addr2

    await RisingEdge(dut.wb_ack_o)
    ret1 = dut.wb_dat_o.value
    # now we can change the data
    if indata2 is not None:
        dut.nor_data_i.value = indata2

    await RisingEdge(dut.wb_ack_o)
    ret2 = dut.wb_dat_o.value

    dut.wb_cyc_i.setimmediatevalue(0)
    dut.wb_stb_i.setimmediatevalue(0)

    return ret1, ret2

async def setup(dut):
    """Prepare DUT for test"""

    cocotb.start_soon(Clock(dut.clk_i, 15.15, units="ns").start())

    dut.wb_cyc_i.value = 0
    dut.wb_stb_i.value = 0
    dut.wb_we_i.value = 0
    dut.wb_adr_i.value = 0
    dut.wb_dat_i.value = 0
    dut.nor_ry_i.value = 1

    #dut._log.info("reset")
    dut.rst_i.value = 1
    await ClockCycles(dut.clk_i, 4)
    dut.rst_i.value = 0

    assert dut.nor_data_oe.value == 0
    assert dut.wb_ack_o.value == 0
    assert dut.wb_stall_o.value == 0

    await ClockCycles(dut.clk_i, 1)

@cocotb.test(skip=False)
async def test_normal_read(dut):
    """Normal read"""

    await setup(dut)

    bus = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wb_cyc_i,
          'stb': dut.wb_stb_i,
           'we': dut.wb_we_i,
          'adr': dut.wb_adr_i,
        'dat_i': dut.wb_dat_i,
        'stall': dut.wb_stall_o,
          'ack': dut.wb_ack_o,
        'dat_o': dut.wb_dat_o
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
          'cyc': dut.wb_cyc_i,
          'stb': dut.wb_stb_i,
           'we': dut.wb_we_i,
          'adr': dut.wb_adr_i,
        'dat_i': dut.wb_dat_i,
        'stall': dut.wb_stall_o,
          'ack': dut.wb_ack_o,
        'dat_o': dut.wb_dat_o
    }

    # test aborted read
    await wb.read_abort(bus, 100, after_cycles=1)
    await ClockCycles(dut.clk_i, 2)
    assert dut.wb_ack_o.value == 0
    assert dut.wb_stall_o.value == 0
    assert dut.nor_ce_o.value == 1
    assert dut.nor_we_o.value == 1
    assert dut.nor_oe_o.value == 1

    # test recover after aborted read
    dut.nor_data_i.value = 0x7010
    read_val = await wb.read(bus, 100)
    assert read_val == 0x7010
    await ClockCycles(dut.clk_i, 1)

@cocotb.test(skip=False)
async def test_second_request(dut):
    """Request during transaction"""

    await setup(dut)

    bus = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wb_cyc_i,
          'stb': dut.wb_stb_i,
           'we': dut.wb_we_i,
          'adr': dut.wb_adr_i,
        'dat_i': dut.wb_dat_i,
        'stall': dut.wb_stall_o,
          'ack': dut.wb_ack_o,
        'dat_o': dut.wb_dat_o
    }

    # test second request while first request being processed
    # TODO: pipelining
    r1, r2 = await wb_read_double(dut, 1, 2, after_cycles=1, indata1=0x8020, indata2=0x4571)
    assert r1 == 0x8020
    assert r2 == 0x4571
    await ClockCycles(dut.clk_i, 1)

@cocotb.test(skip=False)
async def test_stall(dut):
    """Test NOR device stall"""

    await setup(dut)

    bus = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wb_cyc_i,
          'stb': dut.wb_stb_i,
           'we': dut.wb_we_i,
          'adr': dut.wb_adr_i,
        'dat_i': dut.wb_dat_i,
        'stall': dut.wb_stall_o,
          'ack': dut.wb_ack_o,
        'dat_o': dut.wb_dat_o
    }

    async def set_signal_delay(signal, value, delay_cycles):
        await ClockCycles(dut.clk_i, delay_cycles)
        signal.value = value

    # test not stalling on read when ready/busy
    dut.nor_ry_i.value = 0 # assert busy (like a long program or erase)
    dut.nor_data_i.value = 0x0604
    await ClockCycles(dut.clk_i, 1)
    read_val = await wb.read(bus, 30, timeout=1000)
    assert read_val == 0x0604
    await ClockCycles(dut.clk_i, 5)

    # test stalling on write when busy
    dut.nor_ry_i.value = 0 # assert busy (like a long program or erase)
    dut.nor_data_i.value = 0xFFFF
    cocotb.start_soon(set_signal_delay(dut.nor_ry_i, 1, 30))
    await ClockCycles(dut.clk_i, 1)
    await wb.write(bus, 30, 0x1111)
    assert dut.nor_data_o.value == 0x1111
    await ClockCycles(dut.clk_i, 4)

@cocotb.test(skip=False)
async def test_write(dut):
    """Test normal write"""

    await setup(dut)

    bus = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wb_cyc_i,
          'stb': dut.wb_stb_i,
           'we': dut.wb_we_i,
          'adr': dut.wb_adr_i,
        'dat_i': dut.wb_dat_i,
        'stall': dut.wb_stall_o,
          'ack': dut.wb_ack_o,
        'dat_o': dut.wb_dat_o
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
          'cyc': dut.wb_cyc_i,
          'stb': dut.wb_stb_i,
           'we': dut.wb_we_i,
          'adr': dut.wb_adr_i,
        'dat_i': dut.wb_dat_i,
        'stall': dut.wb_stall_o,
          'ack': dut.wb_ack_o,
        'dat_o': dut.wb_dat_o
    }

    addrs = [1, 2, 100, 1351, 38510]

    async def set_data(oe, dat_i, N):
        for i in range(N):
            await FallingEdge(oe)
            dat_i.value = i+1
    set_data_task = cocotb.start_soon(set_data(dut.nor_oe_o, dut.nor_data_i, len(addrs)))

    #dut.nor_data_i.value = 0x1357
    addr_data = await wb.multi_read(bus, addrs, timeout=1000, log=dut._log.info)
    await Join(set_data_task)
    await ClockCycles(dut.clk_i, 1)

    assert len(addr_data) == len(addrs)
    for i,ad in enumerate(addr_data):
        assert int(ad[0]) == addrs[i]
        assert int(ad[1]) == i + 1

    await ClockCycles(dut.clk_i, 10)
