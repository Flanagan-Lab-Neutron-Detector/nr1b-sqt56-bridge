import cocotb
from cocotb.triggers import Timer
from cocotb.binary import BinaryValue

async def setup(dut):
    """Set up DUT"""

    dut.io_o.value = 0
    dut.io_oe.value = 0
    dut.io.value = BinaryValue("ZZZZ")
    await Timer(1, 'ns')

@cocotb.test()
async def test(dut):
    """Test tristate"""

    await setup(dut)

    dut.io.value = 0x5
    await Timer(1, 'ns')
    assert dut.io_i.value == 0x5

    dut.io.value = 0xA
    await Timer(1, 'ns')
    assert dut.io_i.value == 0xA

    dut.io_oe.value = 1
    await Timer(1, 'ns')
    assert dut.io.value == 0

    dut.io_o.value = 0x7
    await Timer(1, 'ns')
    assert dut.io.value == 0x7
