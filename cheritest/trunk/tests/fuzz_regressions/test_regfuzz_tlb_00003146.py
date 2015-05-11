from beritest_tools import BaseBERITestCase
from nose.plugins.attrib import attr
import os
import tools.sim
expected_uncached=[
    0x0,
    0xf7ffffffffffffff,
    0x10,
    0xc00000007fffed28,
    0x9000000040000d20,
    0xc00000007fffe000,
    0x40000000,
    0x1000014,
    0x1000054,
    0x909090909090909,
    0xc00000007fffe0ff,
    0xfedcba9876543210,
    0x9000000040000d20,
    0xffffffffffbfffff,
    0xe0e0e0e0e0e0e0e,
    0xf0f0f0f0f0f0f0f,
    0xd20,
    0xc00000007fffed20,
    0xc00000007fffed28,
    0xc00000007fffed28,
    0x1414141414141414,
    0x1515151515151515,
    0xc00000007fffe0ff,
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
    0xf7ffffffffffffff,
    0x10,
    0xc00000007fffed48,
    0x9800000040000d40,
    0xc00000007fffe000,
    0x40000000,
    0x1000014,
    0x1000054,
    0x909090909090909,
    0xc00000007fffe0ff,
    0xfedcba9876543210,
    0x9000000040000d40,
    0xffffffffffbfffff,
    0xe0e0e0e0e0e0e0e,
    0xf0f0f0f0f0f0f0f,
    0xd40,
    0xc00000007fffed40,
    0xc00000007fffed48,
    0xc00000007fffed48,
    0x1414141414141414,
    0x1515151515151515,
    0xc00000007fffe0ff,
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
class test_regfuzz_tlb_00003146(BaseBERITestCase):
  @attr('tlb')
  def test_registers_expected(self):
    cached=bool(int(os.getenv('CACHED',False)))
    expected=expected_cached if cached else expected_uncached
    for reg in xrange(len(tools.sim.MIPS_REG_NUM2NAME)):
      self.assertRegisterExpected(reg, expected[reg])

