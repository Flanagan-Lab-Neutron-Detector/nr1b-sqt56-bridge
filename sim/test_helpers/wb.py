from typing import Tuple, Iterator, List
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, with_timeout, Join
from cocotb import start_soon

async def read(bus: dict, addr: int, timeout=0) -> int:
    if bus['cyc'].value:
        raise Exception("Transaction already in progress")
    if bus['stall'].value:
        await FallingEdge(bus['stall'])
        await ClockCycles(bus['clk'], 1)

    # initiate cycle: cyc high, stb high, we low, assert
    bus['adr'].value = addr
    bus['cyc'].value = 1
    bus['stb'].value = 1
    bus['we'].value  = 0

    await ClockCycles(bus['clk'], 1)
    bus['stb'].value = 0

    if bus['ack'].value == 0:
        trig = RisingEdge(bus['ack'])
        if timeout > 0:
            await with_timeout(trig, timeout, 'ns')
        else:
            await trig
    await ClockCycles(bus['clk'], 1)

    bus['cyc'].value = 0

    return bus['dat_o'].value

async def multi_read(bus: dict, addrs: Iterator[int], timeout=0, log=lambda a: None) -> List[Tuple[int,int]]:
    if bus['cyc'].value:
        raise Exception("Transaction already in progress")

    # Start cycle
    bus['cyc'].value = 1
    bus['we'].value = 0

    # send the reads
    async def send_reads(clk, stall, stb, adr, addrs: Iterator[int]) -> List[int]:
        addr_ret = []
        for a in addrs:
            addr_ret.append(a) # keep a record
            if stall.value:
                log("[multi_read.send_reads] awaiting end of stall")
                await FallingEdge(stall)
                await ClockCycles(clk, 1)
            log(f"[multi_read.send_reads] stb a={a:X}")
            stb.value = 1
            adr.value = a
            await ClockCycles(clk, 1)
            stb.value = 0
        return addr_ret
    addr_task = start_soon(send_reads(bus['clk'], bus['stall'], bus['stb'], bus['adr'], addrs))

    # await the data
    async def collect_data(clk, ack, dat, N) -> List[int]:
        data = []
        for i in range(N):
            if not ack.value:
                log(f"[multi_read.collect_data] {i}: awaiting ack")
                await RisingEdge(ack)
                await FallingEdge(clk)
            log(f"[multi_read.collect_data] {i}: got dat={int(dat.value):04X}")
            data.append(dat.value)
            #await RisingEdge(clk)
            await ClockCycles(clk, 1, rising=False)
        return data
    data_task = start_soon(collect_data(bus['clk'], bus['ack'], bus['dat_o'], len(addrs)))

    addrs_sent = await Join(addr_task)
    data = await Join(data_task)
    assert len(addrs_sent) == len(data)
    addr_data = [(addrs_sent[i], data[i]) for i in range(len(addrs_sent))]

    bus['cyc'].value = 0

    return addr_data

async def read_abort(bus: dict, addr: int, after_cycles: int = 1) -> None:
    if bus['cyc'].value:
        raise Exception("Transaction already in progress")
    if bus['stall'].value:
        await FallingEdge(bus['stall'])
        await ClockCycles(bus['clk'], 1)

    # initiate cycle: cyc high, stb high, we low, assert address
    bus['adr'].value = addr
    bus['cyc'].value = 1
    bus['stb'].value = 1
    bus['we'].value  = 0
    await ClockCycles(bus['clk'], 1)
    bus['stb'].value = 0
    await ClockCycles(bus['clk'], 1)

    await ClockCycles(bus['clk'], after_cycles)
    bus['cyc'].value = 0

async def write(bus: dict, addr: int, data: int) -> None:
    if bus['cyc'].value:
        raise Exception("Transaction already in progress")
    if bus['stall'].value:
        await FallingEdge(bus['stall'])
        await ClockCycles(bus['clk'], 1)

    # initiate cycle: cyc high, stb high, we low, assert
    bus['adr'].value = addr
    bus['dat_i'].value = data
    bus['cyc'].value = 1
    bus['stb'].value = 1
    bus['we'].value  = 1

    await ClockCycles(bus['clk'], 1)
    bus['stb'].value = 0
    bus['we'].value  = 0

    if not bus['ack'].value:
        await RisingEdge(bus['ack'])

    bus['cyc'].value = 0
    bus['stb'].value = 0
    bus['we'].value  = 0

async def slave_read_expect(bus: dict, adr, data=0, timeout=0, stall_cycles=0, log=lambda s: None):
    """Expects a read."""

    bus['stall'].value = 0

    if not bus['stb'].value:
        trigger = RisingEdge(bus['stb'])
        if timeout > 0:
            await with_timeout(trigger, timeout, 'ns')
        else:
            await trigger
    
    if stall_cycles > 0:
        bus['stall'].value = 1
        stall_cycles -= 1

    await ClockCycles(bus['clk'], 1)

    #await FallingEdge(bus['clk']) # Assert on falling edge so everything is stable
    #log(f"[slave_read_expect] got stb: adr={int(bus['adr'].value):X} (expected {int(adr):X})")
    assert bus['cyc'].value == 1
    assert bus['we'].value == 0
    assert bus['adr'].value == adr

    if stall_cycles > 0:
        bus['stall'].value = 1
        await ClockCycles(bus['clk'], stall_cycles)
    bus['dat_o'].value = data
    bus['ack'].value = 1
    await ClockCycles(bus['clk'], 1)
    bus['ack'].value = 0
    bus['stall'].value = 0

async def slave_read_multi_expect(bus: dict, adr_data: Iterator[Tuple[int,int]], timeout=0, stall_cycles=0, log=lambda s: None):
    """Expects a sequence of reads"""

    for adr,data in adr_data:
        log(f"[multi_expect] expect a={adr:x}")

        bus['stall'].value = 0

        if not bus['stb'].value:
            trigger = RisingEdge(bus['stb'])
            if timeout > 0:
                await with_timeout(trigger, timeout, 'ns')
            else:
                await trigger

        if stall_cycles > 0:
            bus['stall'].value = 1
            #stall_cycles -= 1

        await ClockCycles(bus['clk'], 1)

        #await FallingEdge(bus['clk'])
        log(f"[multi_expect] got a={int(bus['adr']):x}, send d={int(data):x}")
        assert bus['cyc'].value == 1
        assert bus['we'].value == 0
        assert bus['adr'].value == adr

        if stall_cycles > 0:
            bus['stall'].value = 1
            await ClockCycles(bus['clk'], stall_cycles - 1)
        bus['dat_o'].value = data
        bus['ack'].value = 1
        await ClockCycles(bus['clk'], 1)
        bus['ack'].value = 0
        bus['stall'].value = 0

        await ClockCycles(bus['clk'], 1)

async def slave_write_expect(bus: dict, adr, data, timeout=0, stall_cycles=0, log=lambda s: None):
    """Expects a write"""

    bus['stall'].value = 0

    if not bus['stb'].value:
        trigger = RisingEdge(bus['stb'])
        if timeout > 0:
            log(f"[slave_write_expect] awaiting /stb timeout={timeout}ns")
            await with_timeout(trigger, timeout, 'ns')
        else:
            log("[slave_write_expect] awaiting /stb")
            await trigger
    else:
        log("[slave_write_expect] stb already high")
    log("[slave_write_expect] awaiting \\clk")
    await FallingEdge(bus['clk'])
    log("[slave_write_expect] checking assertions")
    assert bus['cyc'].value == 1
    assert bus['we'].value == 1
    assert bus['adr'].value == adr
    assert bus['dat_i'].value == data

    if stall_cycles > 0:
        log(f"[slave_write_expect] stalling for {stall_cycles} cycles")
        bus['stall'].value = 1
        await ClockCycles(bus['clk'], stall_cycles)
    log("[slave_write_expect] ack")
    bus['ack'].value = 1
    await ClockCycles(bus['clk'], 1)
    log("[slave_write_expect] deack")
    bus['ack'].value = 0
    bus['stall'].value = 0
    log("[slave_write_expect] done")

async def slave_write_multi_expect(bus: dict, adr_data: Iterator[Tuple[int,int]], timeout=0, stall_cycles=0, log=lambda s: None):
    """Expects a sequence of writes"""

    for adr,data in adr_data:
        log(f"[multi_expect] expect a={adr:x} d={data:x}")

        bus['stall'].value = 0

        if not bus['stb'].value:
            trigger = RisingEdge(bus['stb'])
            if timeout > 0:
                await with_timeout(trigger, timeout, 'ns')
            else:
                await trigger
        await FallingEdge(bus['clk'])
        log(f"[multi_expect] got a={int(bus['adr']):x} d={int(bus['dat_i']):x}")
        assert bus['cyc'].value == 1
        assert bus['we'].value == 1
        assert bus['adr'].value == adr
        assert bus['dat_i'].value == data

        if stall_cycles > 0:
            bus['stall'].value = 1
            await ClockCycles(bus['clk'], stall_cycles)
        bus['ack'].value = 1
        await ClockCycles(bus['clk'], 1)
        bus['ack'].value = 0
        bus['stall'].value = 0

        await ClockCycles(bus['clk'], 1)

async def slave_monitor(bus: dict, data=0, stall_cycles=0, log=lambda s: None):
    """
    Slave stub

    Start with cocotb.start_soon. Records slave transactions on the given bus.
    """

    state = 'idle'
    stall_count = 0

    while True:
        if bus['rst'].value or not bus['cyc'].value:
            bus['stall'].value = 0
            bus['ack'].value = 0
            bus['dat_i'].value = 0
            stall_count = 0
            state = 'idle'
            #log("[slave_stub] reset")
        elif bus['cyc'].value and bus['stb'].value and not bus['stall'].value:
            if bus['we'].value:
                log(f"[slave stub] write {int(bus['dat_o'].value):x} to {int(bus['adr'].value):x}")
            else:
                bus['dat_i'].value = data
                log(f"[slave stub] read from {int(bus['adr'].value):x} result={int(bus['dat_i'].value):x}")
            if stall_cycles > 0:
                log(f"[slave stub] stalling for {stall_cycles} cycles")
                bus['stall'].value = 1
                stall_count = 0
                state = 'stall'
            else:
                log(f"[slave stub] ack (immediate)")
                bus['ack'].value = 1
        else:
            if state == 'stall':
                if stall_count == stall_cycles:
                    log(f"[slave stub] ack (stall)")
                    bus['ack'].value = 1
                    state = 'idle'
                else:
                    stall_count += 1
            else:
                bus['ack'].value = 0
                stall_count = 0
        await ClockCycles(bus['clk'], 1)

async def slave_expect_nothing(bus: dict):
    """Expects no WB activity"""

    bus['stall'].value = 0

    while True:
        assert bus['stb'].value == 0
        await ClockCycles(bus['clk'], 1)

