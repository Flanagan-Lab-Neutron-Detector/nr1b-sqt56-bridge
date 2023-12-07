import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer, with_timeout
from test_helpers import nor, qspi

spi_freq = 20

async def setup(dut):
    """Setup DUT"""

    #T = 21.5 # 46.5 MHz
    #T = 15.15 # ~66 MHz
    T = 13.33 # ~75 MHz
    cocotb.start_soon(Clock(dut.clk_i, T, units="ns").start())

    dut.pad_spi_io_i.value = 0
    dut.pad_spi_sce_i.value = 1
    dut.pad_spi_sck_i.value = 0

    dut.nor_ry_i.value = 0
    dut.nor_data_i.value = 0

    dut.rst_i.value = 1
    await ClockCycles(dut.clk_i, 4)
    dut.rst_i.value = 0

    assert dut.nor_ce_o.value == 1
    assert dut.nor_we_o.value == 1
    assert dut.nor_oe_o.value == 1
    assert dut.nor_data_o.value == 0

@cocotb.test(skip=False)
async def test_read(dut):
    """Test NOR read"""

    await setup(dut)

    nor_bus = {
            'ce': dut.nor_ce_o,
            'oe': dut.nor_oe_o,
            'we': dut.nor_we_o,
           'doe': dut.nor_data_oe,
          'addr': dut.nor_addr_o,
        'data_o': dut.nor_data_o,
        'data_i': dut.nor_data_i,
            'ry': dut.nor_ry_i
    }

    model = nor.nor_flash_behavioral_x16(1024*1024*64, 1024*64, log=dut._log.info)
    nor_task = cocotb.start_soon(model.state_machine_func(nor_bus))
    await ClockCycles(dut.clk_i, 1)

    # test some reads
    for i in range(4):
        ret_val = await qspi.read_fast(dut.pad_spi_io_i, dut.pad_spi_io_o, dut.pad_spi_io_oe, dut.pad_spi_sck_i, dut.pad_spi_sce_i, 1024*64*i, 1, freq=spi_freq)
        assert ret_val[0] == 0xFFFF
        await ClockCycles(dut.clk_i, 1)

    nor_task.kill()

@cocotb.test(skip=False)
async def test_program(dut):
    """Program one word"""

    await setup(dut)

    nor_bus = {
            'ce': dut.nor_ce_o,
            'oe': dut.nor_oe_o,
            'we': dut.nor_we_o,
           'doe': dut.nor_data_oe,
          'addr': dut.nor_addr_o,
        'data_o': dut.nor_data_o,
        'data_i': dut.nor_data_i,
            'ry': dut.nor_ry_i
    }

    model = nor.nor_flash_behavioral_x16(1024*1024*64, 1024*64, log=dut._log.info)
    # Word program busy time is typically 60us, so we set it to shorter here
    model.tbusy_program = 1000 # 1 us
    nor_task = cocotb.start_soon(model.state_machine_func(nor_bus))
    await ClockCycles(dut.clk_i, 1)

    # send program
    pa = 0x0000400
    pd = 0x3456
    await qspi.write_through(dut.pad_spi_io_i, dut.pad_spi_sck_i, dut.pad_spi_sce_i, 0x555, 0xAA, freq=spi_freq, log=dut._log.info)
    await Timer(100, 'ns')
    await qspi.write_through(dut.pad_spi_io_i, dut.pad_spi_sck_i, dut.pad_spi_sce_i, 0x2AA, 0x55, freq=spi_freq, log=dut._log.info)
    await Timer(100, 'ns')
    await qspi.write_through(dut.pad_spi_io_i, dut.pad_spi_sck_i, dut.pad_spi_sce_i, 0x555, 0xA0, freq=spi_freq, log=dut._log.info)
    await Timer(100, 'ns')
    await qspi.write_through(dut.pad_spi_io_i, dut.pad_spi_sck_i, dut.pad_spi_sce_i, pa, pd, freq=spi_freq, log=dut._log.info)
    #await qspi.prog_word(dut.pad_spi_io_i, dut.pad_spi_sck_i, dut.pad_spi_sce_i, pa, pd, freq=spi_freq, log=dut._log.info)
    await ClockCycles(dut.clk_i, 1)

    # now wait until ready with timeout at 100us
    await with_timeout(RisingEdge(dut.nor_ry_i), 100, 'us')

    assert model.mem.mem[pa] == pd

    # now read
    w = await qspi.read_fast(dut.pad_spi_io_i, dut.pad_spi_io_o, dut.pad_spi_io_oe, dut.pad_spi_sck_i, dut.pad_spi_sce_i, pa, 1, freq=spi_freq, log=dut._log.info)
    assert w[0] == pd

    nor_task.kill()

@cocotb.test(skip=False)
async def test_erase_sector(dut):
    """Erase one sector"""

    await setup(dut)

    wb_bus = {
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

    nor_bus = {
            'ce': dut.nor_ce_o,
            'oe': dut.nor_oe_o,
            'we': dut.nor_we_o,
           'doe': dut.nor_data_oe,
          'addr': dut.nor_addr_o,
        'data_o': dut.nor_data_o,
        'data_i': dut.nor_data_i,
            'ry': dut.nor_ry_i
    }

    model = nor.nor_flash_behavioral_x16(1024*1024*64, 1024*64, log=dut._log.info)
    # Sector erase busy time is typically 0.5s, so we set it to shorter here
    model.tbusy_erase_sector = 1000 # 1 us

    sector_address = 1024*64*7
    for i in range(32):
        model.mem.program(sector_address + i, i)
    data_str = ' '.join([f"{x:04X}" for x in model.mem.mem[sector_address:sector_address+i]])
    dut._log.info(f"{sector_address:X}[0:32] = {{ {data_str} }}")

    nor_task = cocotb.start_soon(model.state_machine_func(nor_bus))
    await ClockCycles(dut.clk_i, 1)

    # send erase
    #await wb.write(wb_bus, c, 0x1234)
    await qspi.erase_sect(dut.pad_spi_io_i, dut.pad_spi_sck_i, dut.pad_spi_sce_i, sector_address, freq=spi_freq)
    await ClockCycles(dut.clk_i, 1)

    await with_timeout(RisingEdge(dut.nor_ry_i), 100, 'us')
    await ClockCycles(dut.clk_i, 1)

    dut._log.info("Erase")
    data_str = ' '.join([f"{x:04X}" for x in model.mem.mem[sector_address:sector_address+i]])
    dut._log.info(f"{sector_address:X}[0:32] = {{ {data_str} }}")

    # now read
    for i in range(32):
        assert model.mem.read(sector_address + i) == 0xFFFF

    nor_task.kill()

@cocotb.test(skip=False)
async def test_erase_chip(dut):
    """Erase one sector"""

    await setup(dut)

    wb_bus = {
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

    nor_bus = {
            'ce': dut.nor_ce_o,
            'oe': dut.nor_oe_o,
            'we': dut.nor_we_o,
           'doe': dut.nor_data_oe,
          'addr': dut.nor_addr_o,
        'data_o': dut.nor_data_o,
        'data_i': dut.nor_data_i,
            'ry': dut.nor_ry_i
    }

    model = nor.nor_flash_behavioral_x16(1024*1024*64, 1024*64, log=dut._log.info)
    # Chip erase busy time is typically up to 34min, so we set it to shorter here
    model.tbusy_erase_chip = 1000 # 1 us

    # start nor state machin
    nor_task = cocotb.start_soon(model.state_machine_func(nor_bus))
    await ClockCycles(dut.clk_i, 1)

    # pre program sector 7
    sa1 = 1024*64 * 7
    for i in range(32):
        model.mem.program(sa1 + i, i)
    data_str = ' '.join([f"{x:04X}" for x in model.mem.mem[sa1:sa1+i]])
    dut._log.info(f"{sa1:X}[0:32] = {{ {data_str} }}")

    # pre program sector 30
    sa2 = 1024*64 * 30
    for i in range(32):
        model.mem.program(sa2 + i, i)
    data_str = ' '.join([f"{x:04X}" for x in model.mem.mem[sa2:sa2+i]])
    dut._log.info(f"{sa2:X}[0:32] = {{ {data_str} }}")

    # send erase
    await qspi.erase_chip(dut.pad_spi_io_i, dut.pad_spi_sck_i, dut.pad_spi_sce_i, freq=spi_freq)
    await ClockCycles(dut.clk_i, 1)

    # wait for ready
    await with_timeout(RisingEdge(dut.nor_ry_i), 100, 'us')
    await ClockCycles(dut.clk_i, 1)

    #dut._log.info("Erase")
    #data_str = ' '.join([f"{x:04X}" for x in model.mem.mem[sector_address:sector_address+i]])
    #dut._log.info(f"{sector_address:X}[0:32] = {{ {data_str} }}")

    # now read
    for i in range(32):
        assert model.mem.read(sa1 + i) == 0xFFFF
    for i in range(32):
        assert model.mem.read(sa2 + i) == 0xFFFF

    nor_task.kill()

@cocotb.test(skip=False)
async def test_write_through(dut):
    """Write word directly to device"""

    await setup(dut)

    nor_bus = {
            'ce': dut.nor_ce_o,
            'oe': dut.nor_oe_o,
            'we': dut.nor_we_o,
           'doe': dut.nor_data_oe,
          'addr': dut.nor_addr_o,
        'data_o': dut.nor_data_o,
        'data_i': dut.nor_data_i,
            'ry': dut.nor_ry_i
    }

    model = nor.nor_flash_behavioral_x16(1024*1024*64, 1024*64, log=dut._log.info)
    nor_task = cocotb.start_soon(model.state_machine_func(nor_bus))
    await ClockCycles(dut.clk_i, 1)

    # send write through (enter CFI)
    pa = 0x55
    pd = 0x98
    await qspi.write_through(dut.pad_spi_io_i, dut.pad_spi_sck_i, dut.pad_spi_sce_i, pa, pd, freq=spi_freq, log=dut._log.info)
    await Timer(100, 'ns')

    # Now we can read CFI data. First three words are 0x0051 0x0052 0x0059
    Q = await qspi.read_fast(dut.pad_spi_io_i, dut.pad_spi_io_o, dut.pad_spi_io_oe, dut.pad_spi_sck_i, dut.pad_spi_sce_i, 0x10, 1, freq=spi_freq, log=dut._log.info)
    await Timer(100, 'ns')
    R = await qspi.read_fast(dut.pad_spi_io_i, dut.pad_spi_io_o, dut.pad_spi_io_oe, dut.pad_spi_sck_i, dut.pad_spi_sce_i, 0x11, 1, freq=spi_freq, log=dut._log.info)
    await Timer(100, 'ns')
    Y = await qspi.read_fast(dut.pad_spi_io_i, dut.pad_spi_io_o, dut.pad_spi_io_oe, dut.pad_spi_sck_i, dut.pad_spi_sce_i, 0x12, 1, freq=spi_freq, log=dut._log.info)
    await Timer(100, 'ns')
    assert Q[0] == 0x0051
    assert R[0] == 0x0052
    assert Y[0] == 0x0059

    # exit CFI
    pa = 0
    pd = 0xF0
    await qspi.write_through(dut.pad_spi_io_i, dut.pad_spi_sck_i, dut.pad_spi_sce_i, pa, pd, freq=spi_freq, log=dut._log.info)
    await Timer(100, 'ns')

    # read array data
    Q = await qspi.read_fast(dut.pad_spi_io_i, dut.pad_spi_io_o, dut.pad_spi_io_oe, dut.pad_spi_sck_i, dut.pad_spi_sce_i, 0x10, 1, freq=spi_freq, log=dut._log.info)
    await Timer(100, 'ns')
    R = await qspi.read_fast(dut.pad_spi_io_i, dut.pad_spi_io_o, dut.pad_spi_io_oe, dut.pad_spi_sck_i, dut.pad_spi_sce_i, 0x11, 1, freq=spi_freq, log=dut._log.info)
    await Timer(100, 'ns')
    Y = await qspi.read_fast(dut.pad_spi_io_i, dut.pad_spi_io_o, dut.pad_spi_io_oe, dut.pad_spi_sck_i, dut.pad_spi_sce_i, 0x12, 1, freq=spi_freq, log=dut._log.info)
    await Timer(100, 'ns')
    assert Q[0] == 0xFFFF
    assert R[0] == 0xFFFF
    assert Y[0] == 0xFFFF

    nor_task.kill()

@cocotb.test(skip=False)
async def test_vt_enter(dut):
    """Enter VT"""

    await setup(dut)

    nor_bus = {
            'ce': dut.nor_ce_o,
            'oe': dut.nor_oe_o,
            'we': dut.nor_we_o,
           'doe': dut.nor_data_oe,
          'addr': dut.nor_addr_o,
        'data_o': dut.nor_data_o,
        'data_i': dut.nor_data_i,
            'ry': dut.nor_ry_i
    }

    model = nor.nor_flash_behavioral_x16(1024*1024*64, 1024*64, log=dut._log.info)
    nor_task = cocotb.start_soon(model.state_machine_func(nor_bus))
    await ClockCycles(dut.clk_i, 1)

    # send write through sequence
    await qspi.write_through(dut.pad_spi_io_i, dut.pad_spi_sck_i, dut.pad_spi_sce_i, 0, 0x80, freq=spi_freq, log=dut._log.info)
    await Timer(300, 'ns')
    await qspi.write_through(dut.pad_spi_io_i, dut.pad_spi_sck_i, dut.pad_spi_sce_i, 0, 0x01, freq=spi_freq, log=dut._log.info)
    await Timer(300, 'ns')
    await qspi.write_through(dut.pad_spi_io_i, dut.pad_spi_sck_i, dut.pad_spi_sce_i, 0, 0x80, freq=spi_freq, log=dut._log.info)
    await Timer(300, 'ns')
    await qspi.write_through(dut.pad_spi_io_i, dut.pad_spi_sck_i, dut.pad_spi_sce_i, 0, 0x12, freq=spi_freq, log=dut._log.info)

    await Timer(1, 'us')
    # send VT enter
    await qspi.enter_vt(dut.pad_spi_io_i, dut.pad_spi_sck_i, dut.pad_spi_sce_i, freq=spi_freq)
    await ClockCycles(dut.clk_i, 5)
    assert dut.nor_we_o.value == 0

    await ClockCycles(dut.clk_i, 10)

@cocotb.test()
async def test_multi_read(dut):
    """Enter VT"""

    await setup(dut)

    nor_bus = {
            'ce': dut.nor_ce_o,
            'oe': dut.nor_oe_o,
            'we': dut.nor_we_o,
           'doe': dut.nor_data_oe,
          'addr': dut.nor_addr_o,
        'data_o': dut.nor_data_o,
        'data_i': dut.nor_data_i,
            'ry': dut.nor_ry_i
    }

    model = nor.nor_flash_behavioral_x16(1024*1024*64, 1024*64, log=dut._log.info)
    nor_task = cocotb.start_soon(model.state_machine_func(nor_bus))
    await ClockCycles(dut.clk_i, 1)

    base = 640 * 65536 - 20

    # set test data
    for i in range(100):
        model.mem.program(base + i, ((i+17 % 256) << 8) + (i+17 % 256))

    # read
    data = await qspi.read_fast(dut.pad_spi_io_i, dut.pad_spi_io_o, dut.pad_spi_io_oe, dut.pad_spi_sck_i, dut.pad_spi_sce_i, base, 100, freq=spi_freq, log=dut._log.info)

    for i,w in enumerate(data):
        exp = ((i+17 % 256) << 8) + (i+17 % 256)
        assert w == exp, f"Word {i} = {w}, expected {exp}"

    await ClockCycles(dut.clk_i, 10)
