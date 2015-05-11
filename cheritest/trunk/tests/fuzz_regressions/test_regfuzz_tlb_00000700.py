from beritest_tools import BaseBERITestCase
from nose.plugins.attrib import attr
import os
import tools.sim
expected_uncached=[
    0x0,
    0x800000000000000,
    0x20,
    0x2cc8,
    0x9000000040000ca0,
    0x2000,
    0x40000000,
    0x100001e,
    0x100005e,
    0xfedcba9876543210,
    0x20aa,
    0x1020304050607080,
    0x9800000040000ca0,
    0xffffffffffbfffff,
    0xe0e0e0e0e0e0e0e,
    0xf0f0f0f0f0f0f0f,
    0xca0,
    0x2ca0,
    0x2ca8,
    0x0,
    0x0,
    0x0,
    0x20aa,
    0x2,
    0x1818181818181818,
    0x9000000040000b50,
    0x0,
    0x1b1b1b1b1b1b1b1b,
    0x1c1c1c1c1c1c1c1c,
    0x9000000000007fe0,
    0x9000000000008000,
    0x900000004000038c,
  ]
expected_cached=[
    0x0,
    0x800000000000000,
    0x20,
    0x2ce8,
    0x9800000040000cc0,
    0x2000,
    0x40000000,
    0x100001e,
    0x100005e,
    0xfedcba9876543210,
    0x20aa,
    0x1020304050607080,
    0x9800000040000cc0,
    0xffffffffffbfffff,
    0xe0e0e0e0e0e0e0e,
    0xf0f0f0f0f0f0f0f,
    0xcc0,
    0x2cc0,
    0x2cc8,
    0x0,
    0x0,
    0x0,
    0x20aa,
    0x2,
    0x1818181818181818,
    0x9800000040000b70,
    0x0,
    0x1b1b1b1b1b1b1b1b,
    0x1c1c1c1c1c1c1c1c,
    0x9800000000007fe0,
    0x9800000000008000,
    0x98000000400003ac,
  ]
class test_regfuzz_tlb_00000700(BaseBERITestCase):
  @attr('tlb')
  def test_registers_expected(self):
    cached=bool(int(os.getenv('CACHED',False)))
    expected=expected_cached if cached else expected_uncached
    for reg in xrange(len(tools.sim.MIPS_REG_NUM2NAME)):
      self.assertRegisterExpected(reg, expected[reg])

