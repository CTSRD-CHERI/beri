from beritest_tools import BaseBERITestCase
from nose.plugins.attrib import attr
import os
import tools.sim
expected_uncached=[
    0x0,
    0x101010101010101,
    0x202020202020202,
    0x303030303030303,
    0x7fffffff,
    0x900000004000038c,
    0x92fab75ffc8e4345,
    0x707070707070707,
    0x808080808080808,
    0x909090909090909,
    0xa0a0a0a0a0a0a0a,
    0xb0b0b0b0b0b0b0b,
    0xc0c0c0c0c0c0c0c,
    0xd0d0d0d0d0d0d0d,
    0xe0e0e0e0e0e0e0e,
    0xf0f0f0f0f0f0f0f,
    0x1,
    0x0,
    0x1,
    0x0,
    0x0,
    0x1,
    0x1616161616161616,
    0x1717171717171717,
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
    0x101010101010101,
    0x202020202020202,
    0x303030303030303,
    0x7fffffff,
    0x98000000400003ac,
    0x92fab75ffc8e4345,
    0x707070707070707,
    0x808080808080808,
    0x909090909090909,
    0xa0a0a0a0a0a0a0a,
    0xb0b0b0b0b0b0b0b,
    0xc0c0c0c0c0c0c0c,
    0xd0d0d0d0d0d0d0d,
    0xe0e0e0e0e0e0e0e,
    0xf0f0f0f0f0f0f0f,
    0x1,
    0x0,
    0x1,
    0x0,
    0x0,
    0x1,
    0x1616161616161616,
    0x1717171717171717,
    0x1818181818181818,
    0x9800000040000bbc,
    0x0,
    0x1b1b1b1b1b1b1b1b,
    0x1c1c1c1c1c1c1c1c,
    0x9800000000007fe0,
    0x9800000000008000,
    0x98000000400003ac,
  ]
class test_regfuzz_branch_two_args_00002986(BaseBERITestCase):
  
  def test_registers_expected(self):
    cached=bool(int(os.getenv('CACHED',False)))
    expected=expected_cached if cached else expected_uncached
    for reg in xrange(len(tools.sim.MIPS_REG_NUM2NAME)):
      self.assertRegisterExpected(reg, expected[reg])

