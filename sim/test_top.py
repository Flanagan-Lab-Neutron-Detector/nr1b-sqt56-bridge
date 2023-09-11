import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer, with_timeout
from test_helpers import nor, qspi

async def setup(dut):
    """Setup DUT"""

    T = 21.5 # 46.5 MHz
    cocotb.start_soon(Clock(dut.clk_i, T, units="ns").start())

    dut.qspi_io_i.value = 0
    dut.qspi_sce.value = 1
    dut.qspi_sck.value = 0

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
        ret_val = await qspi.read_fast(dut.qspi_io_i, dut.qspi_io_o, dut.qspi_sck, dut.qspi_sce, 1024*64*i, freq=22)
        assert ret_val == 0xFFFF
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
    await qspi.prog_word(dut.qspi_io_i, dut.qspi_sck, dut.qspi_sce, pa, pd, freq=22, log=dut._log.info)
    await ClockCycles(dut.clk_i, 1)

    # now wait until ready with timeout at 100us
    await with_timeout(RisingEdge(dut.nor_ry_i), 100, 'us')

    assert model.mem.mem[pa] == pd

    # now read
    w = await qspi.read_fast(dut.qspi_io_i, dut.qspi_io_o, dut.qspi_sck, dut.qspi_sce, pa, freq=40, log=dut._log.info)
    assert w == pd

    nor_task.kill()

@cocotb.test(skip=False)
async def test_erase(dut):
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
    await qspi.erase_sect(dut.qspi_io_i, dut.qspi_sck, dut.qspi_sce, sector_address, freq=22)
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
    await qspi.write_through(dut.qspi_io_i, dut.qspi_sck, dut.qspi_sce, pa, pd, freq=22, log=dut._log.info)
    await ClockCycles(dut.clk_i, 10)

    # Now we can read CFI data. First three words are 0x0051 0x0052 0x0059
    Q = await qspi.read_fast(dut.qspi_io_i, dut.qspi_io_o, dut.qspi_sck, dut.qspi_sce, 0x10, freq=22, log=dut._log.info)
    R = await qspi.read_fast(dut.qspi_io_i, dut.qspi_io_o, dut.qspi_sck, dut.qspi_sce, 0x11, freq=22, log=dut._log.info)
    Y = await qspi.read_fast(dut.qspi_io_i, dut.qspi_io_o, dut.qspi_sck, dut.qspi_sce, 0x12, freq=22, log=dut._log.info)
    assert Q == 0x0051
    assert R == 0x0052
    assert Y == 0x0059

    # exit CFI
    pa = 0
    pd = 0xF0
    await qspi.write_through(dut.qspi_io_i, dut.qspi_sck, dut.qspi_sce, pa, pd, freq=22, log=dut._log.info)
    await ClockCycles(dut.clk_i, 10)

    # read array data
    Q = await qspi.read_fast(dut.qspi_io_i, dut.qspi_io_o, dut.qspi_sck, dut.qspi_sce, 0x10, freq=22, log=dut._log.info)
    R = await qspi.read_fast(dut.qspi_io_i, dut.qspi_io_o, dut.qspi_sck, dut.qspi_sce, 0x11, freq=22, log=dut._log.info)
    Y = await qspi.read_fast(dut.qspi_io_i, dut.qspi_io_o, dut.qspi_sck, dut.qspi_sce, 0x12, freq=22, log=dut._log.info)
    assert Q == 0xFFFF
    assert R == 0xFFFF
    assert Y == 0xFFFF

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
    await qspi.write_through(dut.qspi_io_i, dut.qspi_sck, dut.qspi_sce, 0, 0x80, freq=22, log=dut._log.info)
    await Timer(300, 'ns')
    await qspi.write_through(dut.qspi_io_i, dut.qspi_sck, dut.qspi_sce, 0, 0x01, freq=22, log=dut._log.info)
    await Timer(300, 'ns')
    await qspi.write_through(dut.qspi_io_i, dut.qspi_sck, dut.qspi_sce, 0, 0x80, freq=22, log=dut._log.info)
    await Timer(300, 'ns')
    await qspi.write_through(dut.qspi_io_i, dut.qspi_sck, dut.qspi_sce, 0, 0x12, freq=22, log=dut._log.info)

    await Timer(1, 'us')
    # send VT enter
    await qspi.enter_vt(dut.qspi_io_i, dut.qspi_sck, dut.qspi_sce, freq=22)
    await ClockCycles(dut.clk_i, 5)
    assert dut.nor_we_o.value == 0

    await ClockCycles(dut.clk_i, 10)
