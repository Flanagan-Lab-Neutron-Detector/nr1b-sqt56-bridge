import cocotb
from random import random
from typing import Tuple, Iterator
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Join, Timer
from test_helpers import wb, qspi

async def setup(dut):
    """Setup DUT"""

    dut.t_dumpb.value = 0 # dump VCD

    dut.sck_i.value = 0
    dut.sce_i.value = 0
    dut.sio_i.value = 0
    dut.wb_ack_i.value = 0
    dut.wb_stall_i.value = 0
    dut.wb_ack_i.value = 0
    dut.wb_dat_i.value = 0
    dut.wb_adr_o.value = 0
    dut.wb_dat_o.value = 0

    #T = 21.5 # 46.5 MHz
    T = 15.15 # ~66 MHz
    #T = 11.11 # ~90 MHz
    cocotb.start_soon(Clock(dut.clk_i, T, units="ns").start())

    dut.rst_i.value = 1
    await ClockCycles(dut.clk_i, 5)
    dut.rst_i.value = 0

@cocotb.test()
async def test_fast_read(dut):
    """Test fast read"""

    await setup(dut)

    bus_wb = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wb_cyc_o,
          'stb': dut.wb_stb_o,
           'we': dut.wb_we_o,
          'adr': dut.wb_adr_o,
        'dat_o': dut.wb_dat_i,
        'stall': dut.wb_stall_i,
          'ack': dut.wb_ack_i,
        'dat_i': dut.wb_dat_o
    }
    task = cocotb.start_soon(wb.slave_read_expect(bus_wb, 0x83, data=0x3456, timeout=2000, stall_cycles=4, log=dut._log.info))

    ret_val = await qspi.read_fast(dut.sio_i, dut.sio_o, dut.sio_oe, dut.sck_i, dut.sce_i, 0x83, 1, freq=20, sce_pol=1, log=dut._log.info)
    assert ret_val[0] == 0x3456

    await ClockCycles(dut.clk_i, 1)
    await Join(task)

@cocotb.test(skip=False)
async def test_slow_read(dut):
    """Test slow read"""

    await setup(dut)

    bus_wb = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wb_cyc_o,
          'stb': dut.wb_stb_o,
           'we': dut.wb_we_o,
          'adr': dut.wb_adr_o,
        'dat_o': dut.wb_dat_i,
        'stall': dut.wb_stall_i,
          'ack': dut.wb_ack_i,
        'dat_i': dut.wb_dat_o
    }

    task = cocotb.start_soon(wb.slave_read_expect(bus_wb, 0x83, data=0x3456, timeout=10000, stall_cycles=2, log=dut._log.info))

    ret_val = await qspi.read_slow(dut.sio_i, dut.sio_o, dut.sio_oe, dut.sck_i, dut.sce_i, 0x83, 1, freq=6, sce_pol=1, log=dut._log.info)
    assert ret_val[0] == 0x3456

    await ClockCycles(dut.clk_i, 1)
    await Join(task)

@cocotb.test()
async def test_cmd_translation(dut):
    """Test command translation (erase sector)"""

    await setup(dut)

    bus_wb = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wb_cyc_o,
          'stb': dut.wb_stb_o,
           'we': dut.wb_we_o,
          'adr': dut.wb_adr_o,
        'dat_o': dut.wb_dat_i,
        'stall': dut.wb_stall_i,
          'ack': dut.wb_ack_i,
        'dat_i': dut.wb_dat_o
    }
    task = cocotb.start_soon(wb.slave_write_expect(bus_wb, 0xC050000, 0, timeout=2000, stall_cycles=4, log=dut._log.info))

    await qspi.erase_sect(dut.sio_i, dut.sck_i, dut.sce_i, 0x50000, freq=20, sce_pol=1, log=dut._log.info)

    await ClockCycles(dut.clk_i, 1)
    await Join(task)

@cocotb.test()
async def test_clock_rate(dut):
    """Test a range of clock rates"""

    await setup(dut)

    bus_wb = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wb_cyc_o,
          'stb': dut.wb_stb_o,
           'we': dut.wb_we_o,
          'adr': dut.wb_adr_o,
        'dat_o': dut.wb_dat_i,
        'stall': dut.wb_stall_i,
          'ack': dut.wb_ack_i,
        'dat_i': dut.wb_dat_o
    }

    # Frequency range in MHz
    fstart = 1
    fstop = 20
    fsteps = 32
    freqs = [fstart + i*(fstop-fstart)/fsteps for i in range(fsteps+1)]
    for i,freq in enumerate(freqs):
        T = 10*int(100000.0/freq) # ps
        timeout = int(T/1000) * (8+8+20+4)*2 # timeout ~= twice the expected transaction time
        dut._log.info(f"Test f={freq}MHz timeout={timeout}ns")
        data = 0x3456 ^ i
        task = cocotb.start_soon(wb.slave_read_expect(bus_wb, 0x83, data=data, timeout=timeout, stall_cycles=4, log=dut._log.info))
        #dut._log.info(f"starting read")
        ret_val = await qspi.read_fast(dut.sio_i, dut.sio_o, dut.sio_oe, dut.sck_i, dut.sce_i, 0x83, 1, freq=freq, sce_pol=1, log=dut._log.info)
        #dut._log.info(f"Read {ret_val}")
        assert ret_val[0] == data
        #await ClockCycles(dut.clk_i, 1)
        #dut._log.info(f"Waiting on task")
        await Join(task)
        await Timer(50, 'ns')
        #dut._log.info(f"Done")
    await ClockCycles(dut.clk_i, 1)

@cocotb.test()
async def test_prog_word(dut):
    """Test single word program"""

    await setup(dut)

    bus_wb = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wb_cyc_o,
          'stb': dut.wb_stb_o,
           'we': dut.wb_we_o,
          'adr': dut.wb_adr_o,
        'dat_o': dut.wb_dat_i,
        'stall': dut.wb_stall_i,
          'ack': dut.wb_ack_i,
        'dat_i': dut.wb_dat_o
    }

    task = cocotb.start_soon(wb.slave_write_expect(bus_wb, 0x08030000, 0xABCD, timeout=2000, stall_cycles=10, log=dut._log.info))

    await qspi.prog_word(dut.sio_i, dut.sck_i, dut.sce_i, 0x30000, 0xABCD, freq=20, sce_pol=1, log=dut._log.info)

    await ClockCycles(dut.clk_i, 1)
    await Join(task)

@cocotb.test(skip=True)
async def test_page_prog(dut):
    """Test page program mode"""

    await setup(dut)

    bus_wb = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wb_cyc_o,
          'stb': dut.wb_stb_o,
           'we': dut.wb_we_o,
          'adr': dut.wb_adr_o,
        'dat_o': dut.wb_dat_i,
        'stall': dut.wb_stall_i,
          'ack': dut.wb_ack_i,
        'dat_i': dut.wb_dat_o
    }

    progwords = [
        0x1234,
        0x4321,
        0xabcd,
        0x0000,
        0xFFFF,
        0xF0F0,
        0x0F0F,
        0x5A5A
    ]

    expected_writes = [
        (0x18050000, 0),
    ]

    for i,w in enumerate(progwords):
        expected_writes.append((0x18000000 + i, w))

    task = cocotb.start_soon(wb.slave_write_multi_expect(bus_wb, expected_writes, timeout=2000, stall_cycles=4, log=dut._log.info))

    #assert False, "TODO: implement page program"
    await qspi.page_prog(dut.sio_i, dut.sck_i, dut.sce_i, 0x50000, progwords, sce_pol=1)

    await ClockCycles(dut.clk_i, 1)
    await Join(task)

@cocotb.test(skip=False)
async def test_sequential_reads(dut):
    """Test reading a sequence of words in one transaction"""

    await setup(dut)

    bus_wb = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wb_cyc_o,
          'stb': dut.wb_stb_o,
           'we': dut.wb_we_o,
          'adr': dut.wb_adr_o,
        'dat_o': dut.wb_dat_i,
        'stall': dut.wb_stall_i,
          'ack': dut.wb_ack_i,
        'dat_i': dut.wb_dat_o
    }

    pairs = [
        (0x100, 0xFFFF),
        (0x101, 0xFEFE),
        (0x102, 0xFDFD),
        (0x103, 0xFCFC),
        (0x104, 0xFBFB),
        (0x105, 0xFAFA),
        (0x106, 0xF9F9),
        (0x107, 0xF8F8),
        (0x108, 0xF7F7),
        (0x109, 0xF6F6),
        (0x10A, 0xF5F5),
        (0x10B, 0xF4F4),
        (0x10C, 0xF3F3),
        (0x10D, 0xF2F2),
        (0x10E, 0xF1F1),
        (0x10F, 0xF0F0),
        (0x110, 0x0F0F),
        (0x111, 0x1F1F),
        (0x112, 0x2F2F),
        (0x113, 0x3F3F)
    ]

    task = cocotb.start_soon(wb.slave_read_multi_expect(bus_wb, pairs, timeout=2000*len(pairs), stall_cycles=2, log=dut._log.info))

    ret_val = await qspi.read_fast(dut.sio_i, dut.sio_o, dut.sio_oe, dut.sck_i, dut.sce_i, 0x100, len(pairs), freq=20, sce_pol=1, log=dut._log.info)
    for i,p in enumerate(pairs):
        _, w = p
        assert ret_val[i] == w

    await ClockCycles(dut.clk_i, 1)
    await Join(task)

@cocotb.test()
async def test_fast_read_mc(dut):
    """Test fast read with random start offsets"""

    await setup(dut)

    bus_wb = {
          'clk': dut.clk_i,
          'rst': dut.rst_i,
          'cyc': dut.wb_cyc_o,
          'stb': dut.wb_stb_o,
           'we': dut.wb_we_o,
          'adr': dut.wb_adr_o,
        'dat_o': dut.wb_dat_i,
        'stall': dut.wb_stall_i,
          'ack': dut.wb_ack_i,
        'dat_i': dut.wb_dat_o
    }

    # stop dump
    dut.t_dumpb.value = 1

    N = 100
    for i in range(100):
        # clk period is 8ns, sck period is 16.67ns, so pick toff in [0, 8]ns
        toff = 8.0 * random()
        task = cocotb.start_soon(wb.slave_read_expect(bus_wb, 0x83, data=0x3456, timeout=2000, stall_cycles=4, log=dut._log.info))
        ret_val = await qspi.read_fast(dut.sio_i, dut.sio_o, dut.sio_oe, dut.sck_i, dut.sce_i, 0x83, 1, freq=20, toff=toff, sce_pol=1)
        assert ret_val[0] == 0x3456
        await Join(task)
        await Timer(50, 'ns')

    # restart dump
    dut.t_dumpb.value = 0

    await ClockCycles(dut.clk_i, 1)

