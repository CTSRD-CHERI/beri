from beritest_tools import BaseBERITestCase
from nose.plugins.attrib import attr
import os
import tools.sim
expected_uncached=[
    0x0,
    0x800000000000000,
    0x20,
    0x2d28,
    0x9000000040000d00,
    0x2000,
    0x40000000,
    0x100001e,
    0x100005e,
    0xfedcba9876543210,
    0x20aa,
    0x1020304050607080,
    0x9800000040000d00,
    0xffffffffffbfffff,
    0xe0e0e0e0e0e0e0e,
    0xf0f0f0f0f0f0f0f,
    0xd00,
    0x2d00,
    0x2d08,
    0x0,
    0x0,
    0x0,
    0x20aa,
    0x2,
    0x1818181818181818,
    0x9000000040000b9c,
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
    0x2d48,
    0x9800000040000d20,
    0x2000,
    0x40000000,
    0x100001e,
    0x100005e,
    0xfedcba9876543210,
    0x20aa,
    0x1020304050607080,
    0x9800000040000d20,
    0xffffffffffbfffff,
    0xe0e0e0e0e0e0e0e,
    0xf0f0f0f0f0f0f0f,
    0xd20,
    0x2d20,
    0x2d28,
    0x0,
    0x0,
    0x0,
    0x20aa,
    0x2,
    0x1818181818181818,
    0x9800000040000bbc,
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

