"""NOR flash device model"""

from typing import Union
import cocotb
from cocotb.triggers import Edge, RisingEdge, FallingEdge, ClockCycles, First, Timer, ReadOnly
from array import array
from enum import Enum

class nor_flash_array:
    """NOR flash memory array"""
    mem: array
    tc: str
    size: int
    erase_val: int

    def __init__(self, typecode: str, size: int, erase_size: int):
        self.tc = typecode
        self.size = size

        if size % erase_size != 0:
            raise ValueError(f"Array length ({size}) must be a multiply of the erase size ({erase_size}). size % erase_size = {size%erase_size}")
        self.erase_size = min(erase_size, size)

        if self.tc == 'b' or self.tc == 'B':
            self.erase_val = 0xFF
        elif self.tc == 'u' or self.tc == 'h' or self.tc == 'H' or self.tc == 'i' or self.tc == 'I':
            self.erase_val = 0xFFFF
        elif self.tc == 'l' or self.tc == 'L' or self.tc == 'f':
            self.erase_val = 0xFFFFFFFF
        elif self.tc == 'q' or self.tc == 'Q' or self.tc == 'd':
            self.erase_val = 0xFFFFFFFFFFFFFFFF
        else:
            raise TypeError("typecode must be one of bBuhHiIlLfqQd")

        self.mem = array(self.tc, [self.erase_val]*self.size)

    def read(self, addr) -> int:
        return self.mem[addr]

    def program(self, addr: int, data: int) -> None:
        self.mem[addr] &= data

    def erase(self, addr: int) -> None:
        base_address = self.erase_size * int(addr / self.erase_size)
        self.mem[base_address:base_address + self.erase_size] = array(self.tc, [self.erase_val]*self.erase_size)

    def erase_all(self) -> None:
        self.mem = array(self.tc, [self.erase_val]*self.size)

class nor_flash_behavioral_x16:
    """NOR flash cocotb behavioral model (x16)"""

    # utility
    log = lambda s: None

    # memory
    mem: nor_flash_array
    # cfi array
    cfi: array

    # behavioral state
    busy: bool = False

    # timing parameters, ns
    tbusy_program = 60*1000
    tbusy_erase_sector = 0.5e9
    tbusy_erase_chip = 30 * 1e9

    class bus_state(Enum):
        IDLE = 0
        RECOVERY = 1
        BUSY = 2

    class ctrl_state(Enum):
        CMD_CYCLE_1    = 1
        CMD_CYCLE_2    = 2
        CMD_SELECT     = 3
        CMD_PROGRAM    = 4
        CMD_WRITE_BUF  = 5
        CMD_WRITE_BUF_DATA = 6
        CMD_ERASE_1    = 7
        CMD_ERASE_2    = 8
        CMD_ERASE_SEL  = 9

    class mem_overlay(Enum):
        OVERLAY_ARRAY = 0
        OVERLAY_CFI = 1

    if_state: bus_state = bus_state.IDLE
    state: ctrl_state = ctrl_state.CMD_CYCLE_1
    overlay: mem_overlay = mem_overlay.OVERLAY_ARRAY

    def _init_cfi(self):
        self.cfi = array('H', [0]*(0x3C*2))
        self.cfi[0x10] = 0x0051
        self.cfi[0x11] = 0x0052
        self.cfi[0x12] = 0x0059
        self.cfi[0x13] = 0x0002
        self.cfi[0x14] = 0x0000
        self.cfi[0x15] = 0x0000
        self.cfi[0x16] = 0x0000
        self.cfi[0x17] = 0x0000
        self.cfi[0x18] = 0x0000
        self.cfi[0x19] = 0x0000
        self.cfi[0x1A] = 0x0000

    def __init__(self, size: int, erase_size: int, log=lambda s: None):
        self.mem = nor_flash_array('H', size, erase_size)
        self._init_cfi()
        self.log = log

    def read(self, addr: int) -> int:
        data = 0
        if self.overlay == self.mem_overlay.OVERLAY_CFI:
            data = self.cfi[addr] if addr < len(self.cfi) else 0
            self.log(f"[flash] read CFI @{addr:07X}h = {data:04X}")
        else:
            data = self.mem.read(addr)
            self.log(f"[flash] read @{addr:07X}h = {data:04X}")
        return data

    def _handle_cmd_cycle(self, addr: int, data: int) -> int:
        self.log(f"[flash] cmd cycle state={self.state} addr={addr:X} data={data:04X}")

        wait_time = 0

        if self.state == self.ctrl_state.CMD_CYCLE_1:
            if data == 0xF0: # reset
                self.busy = False
                self.overlay = self.mem_overlay.OVERLAY_ARRAY
                self.log("[flash] received cmd reset")
            elif addr == 0x55 and data == 0x98: # CFI enter
                self.overlay = self.mem_overlay.OVERLAY_CFI
                self.log("[flash] received cmd cfi enter")
            elif addr == 0x555 and data == 0xAA: # unlock cycle 1-1
                self.state = self.ctrl_state.CMD_CYCLE_2
            else: # invalid, treat like reset
                self.state = self.ctrl_state.CMD_CYCLE_1
        elif self.state == self.ctrl_state.CMD_CYCLE_2:
            if addr == 0x2AA and data == 0x55:
                self.state = self.ctrl_state.CMD_SELECT
            else: # invalid, treat like reset
                self.state = self.ctrl_state.CMD_CYCLE_1
        elif self.state == self.ctrl_state.CMD_SELECT:
            if addr == 0x555 and data == 0xA0:
                self.state = self.ctrl_state.CMD_PROGRAM
            elif data == 0x25:
                self.state = self.ctrl_state.CMD_WRITE_BUF
            elif addr == 0x555 and data == 0x80:
                self.state = self.ctrl_state.CMD_ERASE_1
            else: # invalid, treat like reset
                self.state = self.ctrl_state.CMD_CYCLE_1
        elif self.state == self.ctrl_state.CMD_PROGRAM:
            self.log(f"[flash] received cmd program {addr:X} = {data:04X}")
            # addr is program address and data is program data
            self.mem.program(addr, data)
            wait_time = self.tbusy_program
        elif self.state == self.ctrl_state.CMD_WRITE_BUF:
            self.log("[flash] received cmd write buf")
            pass
        elif self.state == self.ctrl_state.CMD_ERASE_1:
            if addr == 0x555 and data == 0xAA:
                self.state = self.ctrl_state.CMD_ERASE_2
            else: # invalid, treat like reset
                self.state = self.ctrl_state.CMD_CYCLE_1
        elif self.state == self.ctrl_state.CMD_ERASE_2:
            if addr == 0x2AA and data == 0x55:
                self.state = self.ctrl_state.CMD_ERASE_SEL
            else: # invalid, treat like reset
                self.state = self.ctrl_state.CMD_CYCLE_1
        elif self.state == self.ctrl_state.CMD_ERASE_SEL:
            if addr == 0x555 and data == 0x10:
                self.log("[flash] received cmd erase chip")
                # chip erase
                self.mem.erase_all()
                wait_time = self.tbusy_erase_chip
            elif data == 0x30:
                self.log(f"[flash] received cmd erase sector {addr:X}")
                # sector erase
                self.mem.erase(addr)
                wait_time = self.tbusy_erase_sector

        return wait_time

    async def state_machine_func(self, bus: dict):
        """Flash state machine function"""

        self.log("[flash] startup")

        self.busy = False
        self.if_state = self.bus_state.IDLE
        self.state = self.ctrl_state.CMD_CYCLE_1

        bus['ry'].value = 1

        while True:
            #bus['ry'].value = 0 if self.busy else 1
            if self.if_state == self.bus_state.IDLE:
                self.log("[flash] IDLE wait for request")
                #await First(FallingEdge(bus['we']), FallingEdge(bus['oe']))
                await FallingEdge(bus['ce'])
                await ReadOnly()
                self.log(f"[flash] IDLE request ce={bus['ce'].value} oe={bus['oe'].value} we={bus['we'].value}")
                if not bus['ce'].value: # we only care if CE is low TODO: fix this
                    assert bus['we'].value or bus['oe'].value # at most one should be asserted
                    if (not bus['we'].value) and (not self.busy):
                        self.log(f"[flash] IDLE request write not busy")
                        await Timer(35, 'ns') # tWP
                        # now we sample the address and data
                        addr = int(bus['addr'].value)
                        data = int(bus['data_o'].value)
                        wait_time = self._handle_cmd_cycle(addr, data)
                        if wait_time > 0:
                            async def set_busy():
                                self.log(f"[flash] set_busy: wait 90 ns")
                                await Timer(90, 'ns')
                                self.busy = 1
                                bus['ry'].value = 0
                                self.log(f"[flash] set_busy: done")
                            await cocotb.start(set_busy())
                            async def unset_busy(wait):
                                self.log(f"[flash] unset_busy: wait {wait} ns")
                                await Timer(wait, 'ns')
                                bus['ry'].value = 1
                                self.busy = 0
                                self.log(f"[flash] unset_busy: done")
                            await cocotb.start(unset_busy(wait_time))
                        self.if_state = self.bus_state.RECOVERY
                    elif not bus['oe'].value:
                        self.log(f"[flash] IDLE request read {int(bus['addr'].value):07X}h")
                        await First(Timer(180, 'ns'), RisingEdge(bus['ce']), RisingEdge(bus['oe'])) # tACC worst case, or deselect
                        if not bus['ce'].value and not bus['oe'].value: # timer expired
                            # TODO: status data
                            if self.busy:
                                raise Warning("status data is not yet implemented, reading memory")
                            bus['data_i'].value = self.read(int(bus['addr'].value))
                            #self.log(f"[flash] read @{int(bus['addr'].value):07X}h = {self.read(int(bus['addr'].value)):04X}")
                            #self.log(f"[flash] IDLE request read wait for end")
                            last_addr = int(bus['addr'].value)
                            await First(Edge(bus['addr']), RisingEdge(bus['ce']), RisingEdge(bus['oe']))
                            await Timer(1, 'ns') # just to be sure
                            while not bus['ce'].value and not bus['oe'].value: # address changed
                                if (bus['addr'].value >> 3) == (last_addr >> 3):
                                    await Timer(25, 'ns') # tPACC
                                else:
                                    await Timer(180, 'ns') # tACC, worst case
                                bus['data_i'].value = self.read(int(bus['addr'].value))
                                #self.log(f"[flash] read @{int(bus['addr'].value):07X}h = {self.read(int(bus['addr'].value)):04X}")
                                last_addr = int(bus['addr'].value)
                                if not bus['ce'].value or not bus['oe'].value:
                                    await First(Edge(bus['addr']), RisingEdge(bus['ce']), RisingEdge(bus['oe']))
                                await Timer(1, 'ns') # just to be sure
                        self.if_state = self.bus_state.IDLE
                    else:
                        self.log("[flash] request while busy")
            elif self.if_state == self.bus_state.RECOVERY:
                self.log(f"[flash] RECOVERY")
                await Timer(35, 'ns') # tCEH
                self.if_state = self.bus_state.IDLE
            else:
                self.log(f"[flash] if_state = {self.if_state}")
                self.if_state = self.bus_state.IDLE
