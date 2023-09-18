import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer, Join
from typing import List
from enum import Enum

async def with_delay(coro: cocotb.Task or cocotb.Coroutine, delay, units: str = "step"):
    await Timer(delay, units)
    return await coro

def start_sck(sck, freq: float):
    T = 10*int(100000.0/freq) # freq (MHz) -> period (ps), rounded to 10ps
    #log(f"[start_sck] starting sck with f={freq} => T={T} (rounded to 10 ps)")
    sck_task = cocotb.start_soon(with_delay(Clock(sck, T, units='ps').start(), 11, 'ns'))
    return sck_task

class SPI_MODE(Enum):
    SINGLE = 0,
    QUAD = 1

async def spi_write_lsb(sio_i, sck, data: int, mode: SPI_MODE, cycles: int, init_wait=0) -> None:
    for i in range(cycles):
        if mode == SPI_MODE.QUAD:
            sio_i.value = (data >> 4*i) & 0xF
        else: # single
            sio_i.value = (data >> i) & 0x1
        if i == 0 and init_wait > 0:
            await Timer(init_wait, 'ns')
        await FallingEdge(sck)
        #log(f"[spi_write_lsb] cmd bit {i} = {int(sio.value):04X}h (?= {(cmd>>i)&0x01:04X}h)")

async def spi_write_msb(sio_i, sck, data: int, mode: SPI_MODE, cycles: int, init_wait=0) -> None:
    for i in range(cycles-1, -1, -1):
        if mode == SPI_MODE.QUAD:
            sio_i.value = (data >> 4*i) & 0xF
        else: # single
            sio_i.value = (data >> i) & 0x1
        if i == cycles-1 and init_wait > 0:
            await Timer(init_wait, 'ns')
        await FallingEdge(sck)
        #log(f"[spi_write_msb] cmd bit {i} = {int(sio.value):04X}h (?= {(cmd>>i)&0x01:04X}h)")

spi_write = spi_write_msb

async def prog_word(sio_i, sck, sce, addr: int, data: int, freq: float=108, sce_pol=0, log=lambda s: None) -> None:
    sce.value = sce_pol
    await Timer(2, 'ns')

    sck_task = start_sck(sck, freq)
    #await ClockCycles(sck, 1)

    # send prog word command
    await spi_write(sio_i, sck, 0xF2, SPI_MODE.SINGLE, 8)
    # address
    await spi_write(sio_i, sck, addr, SPI_MODE.QUAD, 8)
    # data
    await spi_write(sio_i, sck, data, SPI_MODE.QUAD, 4)

    sck_task.kill()
    await Timer(25, 'ns')
    sce.value = not sce_pol
    sck.value = 0
    await Timer(1, 'ns')

    log("[qspi.prog_word] done")

async def write_through(sio_i, sck, sce, addr: int, data: int, freq: float=108, sce_pol=0, log=lambda s: None) -> None:
    sce.value = sce_pol
    await Timer(2, 'ns')

    sck_task = start_sck(sck, freq)
    #await ClockCycles(sck, 1)

    # send write through command
    await spi_write(sio_i, sck, 0xF8, SPI_MODE.SINGLE, 8)
    # address
    await spi_write(sio_i, sck, addr, SPI_MODE.QUAD, 8)
    # data
    await spi_write(sio_i, sck, data, SPI_MODE.QUAD, 4)

    sck_task.kill()
    sce.value = not sce_pol
    sck.value = 0
    await Timer(1, 'ns')
    log("[qspi.write_through] done")

async def page_prog(sio_i, sck, sce, addr: int, words: List[int], freq: float = 108, sce_pol=0, log=lambda s: None) -> None:
    sce.value = sce_pol
    await Timer(2, 'ns')

    sck_task = start_sck(sck, freq)
    #await ClockCycles(sck, 1)

    # send page prog command
    await spi_write(sio_i, sck, 0x02, SPI_MODE.SINGLE, 8)

    # send sector address
    await spi_write(sio_i, sck, addr, SPI_MODE.QUAD, 8)

    # stall
    await ClockCycles(sck, 16)

    # write all (16 bit = 4 cycle) words
    for w in words:
        await spi_write(sio_i, sck, w, SPI_MODE.QUAD, 4)

    sck_task.kill()
    sce.value = not sce_pol
    sck.value = 0
    await Timer(1, 'ns')

async def erase_sect(sio_i, sck, sce, addr: int, freq: float=108, sce_pol=0, log=lambda s: None) -> None:
    sce.value = sce_pol
    await Timer(2, 'ns')

    sck_task = start_sck(sck, freq)
    #await ClockCycles(sck, 1)

    # command phase
    await spi_write(sio_i, sck, 0xD8, SPI_MODE.SINGLE, 8)
    #cmd = 0xD8
    #for i in range(8):
    #    sio_i.value = (cmd >> i) & 0x1
    #    await ClockCycles(sck, 1)

    # address phase
    await spi_write(sio_i, sck, addr, SPI_MODE.QUAD, 8)
    #for i in range(8):
    #    sio_i.value = (addr >> 4*i) & 0xF
    #    await ClockCycles(sck, 1)

    sck_task.kill()
    sck.value = 0
    sce.value = not sce_pol
    await Timer(1, 'ns')

async def read_txn(sio_i, sio_o, sio_oe, sck, sce, addr: int, freq: float, cmd: int, stall: int, toff: float=0, sce_pol=0, log=lambda s: None) -> int:
    sce.value = sce_pol
    await Timer(2 + toff, 'ns')

    sck_task = start_sck(sck, freq)
    #await ClockCycles(sck, 1)

    # command phase
    await spi_write(sio_i, sck, cmd, SPI_MODE.SINGLE, 8, init_wait=1)

    # address phase
    await spi_write(sio_i, sck, addr, SPI_MODE.QUAD, 8)

    # stall for stall cycles
    if stall > 0:
        await ClockCycles(sck, stall, rising=False) # ?

    # read data
    word = 0x0000
    # lsb for i in range(4):
    for i in range(3, -1, -1):
        await RisingEdge(sck)
        assert sio_oe
        log(f"[qspi.read_txn] data cycle {i} = {int(sio_o.value):04X}h")
        word |= (int(sio_o.value) & 0xF) << i*4
    log(f"[qspi.read_txn] data word = {word:04X}")

    await FallingEdge(sck)
    sck_task.kill()
    sck.value = 0
    await Timer(9, 'ns')
    sce.value = not sce_pol
    await Timer(1, 'ns')

    return word

async def read_fast(sio_i, sio_o, sio_oe, sck, sce, addr: int, freq: float = 108, toff: float=0, sce_pol=0, log=lambda s: None) -> int:
    return await read_txn(sio_i, sio_o, sio_oe, sck, sce, addr, freq, cmd=0x0B, stall=20, sce_pol=sce_pol, log=log)

async def read_slow(sio_i, sio_o, sio_oe, sck, sce, addr: int, freq: float = 50, toff: float=0, sce_pol=0, log=lambda s: None) -> int:
    return await read_txn(sio_i, sio_o, sio_oe, sck, sce, addr, freq, cmd=0x03, stall=0, sce_pol=sce_pol, log=log)

async def loopback(sio_i, sio_o, sio_oe, sck, sce, addr: int, freq: float=100, sce_pol=0, log=lambda s: None) -> int:
    return await read_txn(sio_i, sio_o, sio_oe, sck, sce, addr, freq, cmd=0xFA, stall=0, sce_pol=sce_pol, log=log)

async def enter_vt(sio_i, sck, sce, freq: float=60, sce_pol=0, log=lambda s: None) -> int:
    sce.value = sce_pol
    await Timer(2, 'ns')

    sck_task = start_sck(sck, freq)

    # command phase
    await spi_write(sio_i, sck, 0xFB, SPI_MODE.SINGLE, 8)

    sck_task.kill()
    sck.value = 0
    sce.value = not sce_pol
    await Timer(1, 'ns')
    log("[qspi.enter_vt] done")

async def reset(sio_i, sck, sce, freq: float=60, sce_pol=0, log=lambda s: None) -> int:
    sce.value = sce_pol
    await Timer(2, 'ns')

    sck_task = start_sck(sck, freq)

    # command phase
    await spi_write(sio_i, sck, 0xF0, SPI_MODE.SINGLE, 8)

    sck_task.kill()
    sck.value = 0
    sce.value = not sce_pol
    await Timer(1, 'ns')
    log("[qspi.reset] done")
