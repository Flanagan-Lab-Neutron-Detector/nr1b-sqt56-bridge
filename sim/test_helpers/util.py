""" General Cocotb utilities """

from cocotb.binary import BinaryValue
from cocotb.handle import ModifiableObject

def bvstr(b: BinaryValue, fmt='04X') -> str:
    return f"{{:{fmt}}}".format(b.integer) if b.is_resolvable else b.binstr

def sigstr(s: ModifiableObject, fmt='04X') -> str:
    return bvstr(s.value)
