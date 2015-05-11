/*
 *  Copyright (C) 2003-2009  Anders Gavare.
 *  Copyright (C) 2012 Robert Norton
 *  Copyright (C) 2013 Jonathan Woodruff
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions are met:
 *
 *  1. Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *  2. Redistributions in binary form must reproduce the above copyright  
 *     notice, this list of conditions and the following disclaimer in the 
 *     documentation and/or other materials provided with the distribution.
 *  3. The name of the author may not be used to endorse or promote products
 *     derived from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 *  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 *  ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE   
 *  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 *  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 *  HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 *  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 *  OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 *  SUCH DAMAGE.
 */

#include <string.h>
#include <stdio.h>
#include <inttypes.h>
#include "mips_opcodes.h"

#define debug printf

static const char *exception_names[] = EXCEPTION_NAMES;
static const char *hi6_names[] = HI6_NAMES;
static const char *regimm_names[] = REGIMM_NAMES;
static const char *special_names[] = SPECIAL_NAMES;
static const char *special_rot_names[] = SPECIAL_ROT_NAMES;
static const char *special2_names[] = SPECIAL2_NAMES;
static const char *mmi_names[] = MMI_NAMES;
static const char *mmi0_names[] = MMI0_NAMES;
static const char *mmi1_names[] = MMI1_NAMES;
static const char *mmi2_names[] = MMI2_NAMES;
static const char *mmi3_names[] = MMI3_NAMES;
static const char *special3_names[] = SPECIAL3_NAMES;

static const char *regnames[] = MIPS_REGISTER_NAMES;
//static const char *cop0_names[] = COP0_NAMES;

/*
 * mips_exception_name():
 *
 * Return string representation of a MIPS exception code.
 */
const char *
mips_exception_name(int excode)
{
	if (excode >= sizeof(exception_names) / sizeof(exception_names[0]))
		return ("<UNKNOWN>");
	else
		return (exception_names[excode]);
}

/*
 *  mips_cpu_disassemble_instr():
 *
 *  Convert an instruction word into human readable format, for instruction
 *  tracing.
 *
 *  NOTE 2:  coprocessor instructions are not decoded nicely yet  (TODO)
 */
int mips_cpu_disassemble_instr(unsigned char *originstr, uint64_t dumpaddr)
{
	int hi6, special6, regimm5, sub;
	int rt, rd, rs, sa, imm, copz, cache_op, which_cache, showtag;
	uint64_t addr, offset = 0;
	uint32_t instrword;
	unsigned char instr[4];
	char *symbol;

	if ((dumpaddr & 3) != 0)
		printf("WARNING: Unaligned address!\n");

	symbol = NULL;
	if (symbol != NULL && offset==0)
		debug("<%s>\n", symbol);

        debug("%016"PRIx64, (uint64_t)dumpaddr);

	memcpy(instr, originstr, sizeof(uint32_t));

	debug(": %02x%02x%02x%02x",
	    instr[3], instr[2], instr[1], instr[0]);

	//if (running && cpu->delay_slot)
	//	debug(" (d)");

	debug("\t");

	/*
	 *  Decode the instruction:
	 */

	hi6 = (instr[3] >> 2) & 0x3f;

	switch (hi6) {
	case HI6_SPECIAL:
		special6 = instr[0] & 0x3f;
		switch (special6) {
		case SPECIAL_SLL:
		case SPECIAL_SRL:
		case SPECIAL_SRA:
		case SPECIAL_DSLL:
		case SPECIAL_DSRL:
		case SPECIAL_DSRA:
		case SPECIAL_DSLL32:
		case SPECIAL_DSRL32:
		case SPECIAL_DSRA32:
			sub = ((instr[3] & 3) << 3) + ((instr[2] >> 5) & 7);
			rt = instr[2] & 31;
			rd = (instr[1] >> 3) & 31;
			sa = ((instr[1] & 7) << 2) + ((instr[0] >> 6) & 3);

			if (rd == 0 && special6 == SPECIAL_SLL) {
				if (sa == 0)
					debug("nop");
				else if (sa == 1)
					debug("ssnop");
				else if (sa == 3)
					debug("ehb");
				else
					debug("nop (weird, sa=%i)", sa);
				break;
			}

			switch (sub) {
			case 0x00:
				debug("%s\t%s,", special_names[special6],
				    regnames[rd]);
				debug("%s,%i", regnames[rt], sa);
				break;
			case 0x01:
				debug("%s\t%s,",
				    special_rot_names[special6],
				    regnames[rd]);
				debug("%s,%i", regnames[rt], sa);
				break;
			default:debug("UNIMPLEMENTED special, sub=0x%02x\n",
				    sub);
			}
			break;
		case SPECIAL_DSRLV:
		case SPECIAL_DSRAV:
		case SPECIAL_DSLLV:
		case SPECIAL_SLLV:
		case SPECIAL_SRAV:
		case SPECIAL_SRLV:
			rs = ((instr[3] & 3) << 3) + ((instr[2] >> 5) & 7);
			rt = instr[2] & 31;
			rd = (instr[1] >> 3) & 31;
			sub = ((instr[1] & 7) << 2) + ((instr[0] >> 6) & 3);

			switch (sub) {
			case 0x00:
				debug("%s\t%s", special_names[special6],
				    regnames[rd]);
				debug(",%s", regnames[rt]);
				debug(",%s", regnames[rs]);
				break;
			case 0x01:
				debug("%s\t%s", special_rot_names[special6],
				    regnames[rd]);
				debug(",%s", regnames[rt]);
				debug(",%s", regnames[rs]);
				break;
			default:debug("UNIMPLEMENTED special, sub=0x%02x\n",
				    sub);
			}
			break;
		case SPECIAL_JR:
			rs = ((instr[3] & 3) << 3) + ((instr[2] >> 5) & 7);
			symbol = NULL;
			/*  .hb = hazard barrier hint on MIPS32/64 rev 2  */
			debug("jr%s\t%s",
			    (instr[1] & 0x04) ? ".hb" : "",
			    regnames[rs]);
			//if (running && symbol != NULL)
			//	debug("\t<%s>", symbol);
			break;
		case SPECIAL_JALR:
			rs = ((instr[3] & 3) << 3) + ((instr[2] >> 5) & 7);
			rd = (instr[1] >> 3) & 31;
			symbol = NULL;
			/*  .hb = hazard barrier hint on MIPS32/64 rev 2  */
			debug("jalr%s\t%s",
			    (instr[1] & 0x04) ? ".hb" : "",
			    regnames[rd]);
			debug(",%s", regnames[rs]);
			//if (running && symbol != NULL)
			//	debug("\t<%s>", symbol);
			break;
		case SPECIAL_MFHI:
		case SPECIAL_MFLO:
			rd = (instr[1] >> 3) & 31;
			debug("%s\t%s", special_names[special6], regnames[rd]);
			break;
		case SPECIAL_MTLO:
		case SPECIAL_MTHI:
			rs = ((instr[3] & 3) << 3) + ((instr[2] >> 5) & 7);
			debug("%s\t%s", special_names[special6], regnames[rs]);
			break;
		case SPECIAL_ADD:
		case SPECIAL_ADDU:
		case SPECIAL_SUB:
		case SPECIAL_SUBU:
		case SPECIAL_AND:
		case SPECIAL_OR:
		case SPECIAL_XOR:
		case SPECIAL_NOR:
		case SPECIAL_SLT:
		case SPECIAL_SLTU: 
		case SPECIAL_DADD:
		case SPECIAL_DADDU:
		case SPECIAL_DSUB:
		case SPECIAL_DSUBU:
		case SPECIAL_MOVZ:
		case SPECIAL_MOVN:
			rs = ((instr[3] & 3) << 3) + ((instr[2] >> 5) & 7);
			rt = instr[2] & 31;
			rd = (instr[1] >> 3) & 31;
			debug("%s\t%s", special_names[special6],
			    regnames[rd]);
			debug(",%s", regnames[rs]);
			debug(",%s", regnames[rt]);
			break;
		case SPECIAL_MULT:
		case SPECIAL_MULTU:
		case SPECIAL_DMULT:
		case SPECIAL_DMULTU:
		case SPECIAL_DIV:
		case SPECIAL_DIVU:
		case SPECIAL_DDIV:
		case SPECIAL_DDIVU:
			rs = ((instr[3] & 3) << 3) + ((instr[2] >> 5) & 7);
			rt = instr[2] & 31;
			rd = (instr[1] >> 3) & 31;
			debug("%s\t", special_names[special6]);
                        if (rd != 0)
                          debug("WEIRD_RD_NONZERO,");
			debug("%s", regnames[rs]);
			debug(",%s", regnames[rt]);
			break;
		case SPECIAL_TGE:
		case SPECIAL_TGEU:
		case SPECIAL_TLT:
		case SPECIAL_TLTU:
		case SPECIAL_TEQ:
		case SPECIAL_TNE:
			rs = ((instr[3] & 3) << 3) + ((instr[2] >> 5) & 7);
			rt = instr[2] & 31;
			rd = ((instr[1] << 8) + instr[0]) >> 6;	// code, not rd
			debug("%s\t", special_names[special6]);
			debug("%s", regnames[rs]);
			debug(",%s", regnames[rt]);
			if (rd != 0)
				debug(",0x%x", rd);
			break;
		case SPECIAL_SYNC:
			imm = ((instr[1] & 7) << 2) + (instr[0] >> 6);
			debug("sync\t0x%02x", imm);
			break;
		case SPECIAL_SYSCALL:
			imm = (((instr[3] << 24) + (instr[2] << 16) +
			    (instr[1] << 8) + instr[0]) >> 6) & 0xfffff;
			if (imm != 0)
				debug("syscall\t0x%05x", imm);
			else
				debug("syscall");
			break;
		case SPECIAL_BREAK:
			imm = (((instr[3] << 24) + (instr[2] << 16) +
			    (instr[1] << 8) + instr[0]) >> 6) & 0xfffff;
			if (imm != 0)
				debug("break\t0x%05x", imm);
			else
				debug("break");
			break;
		case SPECIAL_MFSA:
                        debug("unimplemented special 0x28");
		case SPECIAL_MTSA:
			debug("unimplemented special 0x29");
			break;
		default:
			debug("%s\t= UNIMPLEMENTED", special_names[special6]);
		}
		break;
	case HI6_BEQ:
	case HI6_BEQL:
	case HI6_BNE:
	case HI6_BNEL:
	case HI6_BGTZ:
	case HI6_BGTZL:
	case HI6_BLEZ:
	case HI6_BLEZL:
		rs = ((instr[3] & 3) << 3) + ((instr[2] >> 5) & 7);
		rt = instr[2] & 31;
		imm = (instr[1] << 8) + instr[0];
		if (imm >= 32768)
			imm -= 65536;
		addr = (dumpaddr + 4) + (imm << 2);

		if (hi6 == HI6_BEQ && rt == MIPS_GPR_ZERO &&
		    rs == MIPS_GPR_ZERO)
			debug("b\t");
		else {
			debug("%s\t", hi6_names[hi6]);
			switch (hi6) {
			case HI6_BEQ:
			case HI6_BEQL:
			case HI6_BNE:
			case HI6_BNEL:
				debug("%s,", regnames[rt]);
			}
			debug("%s,", regnames[rs]);
		}

                debug("0x%016"PRIx64, (uint64_t)addr);

		symbol = NULL;
		if (symbol != NULL && offset != addr)
			debug("\t<%s>", symbol);
		break;
	case HI6_ADDI:
	case HI6_ADDIU:
	case HI6_DADDI:
	case HI6_DADDIU:
	case HI6_SLTI:
	case HI6_SLTIU:
	case HI6_ANDI:
	case HI6_ORI:
	case HI6_XORI:
		rs = ((instr[3] & 3) << 3) + ((instr[2] >> 5) & 7);
		rt = instr[2] & 31;
		imm = (instr[1] << 8) + instr[0];
		if (imm >= 32768)
			imm -= 65536;
		debug("%s\t%s,", hi6_names[hi6], regnames[rt]);
		debug("%s,", regnames[rs]);
		if (hi6 == HI6_ANDI || hi6 == HI6_ORI || hi6 == HI6_XORI)
			debug("0x%04x", imm & 0xffff);
		else
			debug("%i", imm);
		break;
	case HI6_LUI:
		rt = instr[2] & 31;
		imm = (instr[1] << 8) + instr[0];
		debug("lui\t%s,0x%x", regnames[rt], imm);
		break;
	case HI6_LB:
	case HI6_LBU:
	case HI6_LH:
	case HI6_LHU:
	case HI6_LW:
	case HI6_LWU:
	case HI6_LD:
	case HI6_LQ_MDMX:
	case HI6_LWC1:
	case HI6_LWC2:
	case HI6_LWC3:
	case HI6_LDC1:
	case HI6_LDC2:
	case HI6_LL:
	case HI6_LLD:
	case HI6_SB:
	case HI6_SH:
	case HI6_SW:
	case HI6_SD:
	case HI6_SQ_SPECIAL3:
	case HI6_SC:
	case HI6_SCD:
	case HI6_SWC1:
	case HI6_SWC2:
	case HI6_SWC3:
	case HI6_SDC1:
	case HI6_SDC2:
	case HI6_LWL:   
	case HI6_LWR:
	case HI6_LDL:
	case HI6_LDR:
	case HI6_SWL:
	case HI6_SWR:
	case HI6_SDL:
	case HI6_SDR:
		if (hi6 == HI6_LQ_MDMX) {
			debug("mdmx\t(UNIMPLEMENTED)");
			break;
		}
		if (hi6 == HI6_SQ_SPECIAL3) {
			int msbd, lsb, sub10;
			special6 = instr[0] & 0x3f;
			rs = ((instr[3] & 3) << 3) + ((instr[2] >> 5) & 7);
			rt = instr[2] & 31;
			rd = msbd = (instr[1] >> 3) & 31;
			lsb = ((instr[1] & 7) << 2) | (instr[0] >> 6);
			sub10 = (rs << 5) | lsb;

			switch (special6) {

			case SPECIAL3_EXT:
			case SPECIAL3_DEXT:
			case SPECIAL3_DEXTM:
			case SPECIAL3_DEXTU:
				debug("%s", special3_names[special6]);
				if (special6 == SPECIAL3_DEXTM)
					msbd += 32;
				if (special6 == SPECIAL3_DEXTU)
					lsb += 32;
				debug("\t%s", regnames[rt]);
				debug(",%s", regnames[rs]);
				debug(",%i,%i", lsb, msbd + 1);
				break;

			case SPECIAL3_INS:
			case SPECIAL3_DINS:
			case SPECIAL3_DINSM:
			case SPECIAL3_DINSU:
				debug("%s", special3_names[special6]);
				if (special6 == SPECIAL3_DINSM)
					msbd += 32;
				if (special6 == SPECIAL3_DINSU) {
					lsb += 32;
					msbd += 32;
				}
				msbd -= lsb;
				debug("\t%s", regnames[rt]);
				debug(",%s", regnames[rs]);
				debug(",%i,%i", lsb, msbd + 1);
				break;

			case SPECIAL3_BSHFL:
				switch (sub10) {
				case BSHFL_WSBH:
				case BSHFL_SEB:
				case BSHFL_SEH:
					switch (sub10) {
					case BSHFL_WSBH: debug("wsbh"); break;
					case BSHFL_SEB:  debug("seb"); break;
					case BSHFL_SEH:  debug("seh"); break;
					}
					debug("\t%s", regnames[rd]);
					debug(",%s", regnames[rt]);
					break;
				default:debug("%s", special3_names[special6]);
					debug("\t(UNIMPLEMENTED)");
				}
				break;

			case SPECIAL3_DBSHFL:
				switch (sub10) {
				case BSHFL_DSBH:
				case BSHFL_DSHD:
					switch (sub10) {
					case BSHFL_DSBH: debug("dsbh"); break;
					case BSHFL_DSHD: debug("dshd"); break;
					}
					debug("\t%s", regnames[rd]);
					debug(",%s", regnames[rt]);
					break;
				default:debug("%s", special3_names[special6]);
					debug("\t(UNIMPLEMENTED)");
				}
				break;

			case SPECIAL3_RDHWR:
				debug("%s", special3_names[special6]);
				debug("\t%s", regnames[rt]);
				debug(",hwr%i", rd);
				break;

			default:debug("%s", special3_names[special6]);
				debug("\t(UNIMPLEMENTED)");
			}
			break;
		}

		rs = ((instr[3] & 3) << 3) + ((instr[2] >> 5) & 7);
		rt = instr[2] & 31;
		imm = (instr[1] << 8) + instr[0];
		if (imm >= 32768)
			imm -= 65536;
		symbol = NULL;

		/*  LWC3 is PREF in the newer ISA levels:  */
		/*  TODO: Which ISAs? IV? V? 32? 64?  */
		if (hi6 == HI6_LWC3) {
			debug("pref\t0x%x,%i(%s)",
			    rt, imm, regnames[rs]);

			//debug("\t[0x%016"PRIx64" = %s]",
			//    (uint64_t)(cpu->cd.mips.gpr[rs] + imm));
			if (symbol != NULL)
				debug(" = %s", symbol);
			debug("]");

			goto disasm_ret;
		}

		debug("%s\t", hi6_names[hi6]);

		if (hi6 == HI6_SWC1 || hi6 == HI6_SWC2 || hi6 == HI6_SWC3 ||
		    hi6 == HI6_SDC1 || hi6 == HI6_SDC2 ||
		    hi6 == HI6_LWC1 || hi6 == HI6_LWC2 || hi6 == HI6_LWC3 ||
		    hi6 == HI6_LDC1 || hi6 == HI6_LDC2)
			debug("r%i", rt);
		else
			debug("%s", regnames[rt]);

		debug(",%i(%s)", imm, regnames[rs]);

		debug("\t[");

//		debug("0x%016"PRIx64,
//		    (uint64_t) (cpu->cd.mips.gpr[rs] + imm));
//
		if (symbol != NULL)
			debug(" = %s", symbol);

		/*  TODO: In some cases, it is possible to peek into
		    memory, and display that data here, like for the
		    other emulation modes.  */

		debug("]");
		break;

	case HI6_J:
	case HI6_JAL:
		imm = (((instr[3] & 3) << 24) + (instr[2] << 16) +
		    (instr[1] << 8) + instr[0]) << 2;
		addr = (dumpaddr + 4) & ~((1 << 28) - 1);
		addr |= imm;
		symbol = NULL;
		debug("%s\t0x", hi6_names[hi6]);
                debug("%016"PRIx64, (uint64_t) addr);
		if (symbol != NULL)
			debug("\t<%s>", symbol);
		break;

	case HI6_COP0:
	case HI6_COP1:
	case HI6_COP2:
	case HI6_COP3:
		imm = (instr[3] << 24) + (instr[2] << 16) +
		     (instr[1] << 8) + instr[0];
		imm &= ((1 << 26) - 1);

		/*  Call coproc_function(), but ONLY disassembly, no exec:  */
		//coproc_function(cpu, cpu->cd.mips.coproc[hi6 - HI6_COP0],
		//    hi6 - HI6_COP0, imm, 1, running);
		return sizeof(instrword);

	case HI6_CACHE:
		rt   = ((instr[3] & 3) << 3) + (instr[2] >> 5); /*  base  */
		copz = instr[2] & 31;
		imm  = (instr[1] << 8) + instr[0];
		cache_op    = copz >> 2;
		which_cache = copz & 3;
		showtag = 0;
		debug("cache\t0x%02x,0x%04x(%s)", copz, imm, regnames[rt]);
		if (which_cache==0)	debug("  [ primary I-cache");
		if (which_cache==1)	debug("  [ primary D-cache");
		if (which_cache==2)	debug("  [ secondary I-cache");
		if (which_cache==3)	debug("  [ secondary D-cache");
		debug(", ");
		if (cache_op==0)	debug("index invalidate");
		if (cache_op==1)	debug("index load tag");
		if (cache_op==2)	debug("index store tag"), showtag=1;
		if (cache_op==3)	debug("create dirty exclusive");
		if (cache_op==4)	debug("hit invalidate");
		if (cache_op==5)     debug("fill OR hit writeback invalidate");
		if (cache_op==6)	debug("hit writeback");
		if (cache_op==7)	debug("hit set virtual");
		//if (running)
		//	debug(", addr 0x%016"PRIx64,
		//	    (uint64_t)(cpu->cd.mips.gpr[rt] + imm));
		if (showtag)
		//debug(", taghi=%08lx lo=%08lx",
		//    (long)cpu->cd.mips.coproc[0]->reg[COP0_TAGDATA_HI],
		//    (long)cpu->cd.mips.coproc[0]->reg[COP0_TAGDATA_LO]);
		debug(" ]");
		break;

	case HI6_SPECIAL2:
		special6 = instr[0] & 0x3f;
		instrword = (instr[3] << 24) + (instr[2] << 16) +
		    (instr[1] << 8) + instr[0];
		rs = ((instr[3] & 3) << 3) + ((instr[2] >> 5) & 7);
		rt = instr[2] & 31;
		rd = (instr[1] >> 3) & 31;

		if (0/*cpu->cd.mips.cpu_type.rev == MIPS_R5900*/) {
			int c790mmifunc = (instrword >> 6) & 0x1f;
			if (special6 != MMI_MMI0 && special6 != MMI_MMI1 &&
			    special6 != MMI_MMI2 && special6 != MMI_MMI3)
				debug("%s\t", mmi_names[special6]);

			switch (special6) {

			case MMI_MADD:
			case MMI_MADDU:
				if (rd != MIPS_GPR_ZERO) {
					debug("%s,", regnames[rd]);
				}
				debug("%s,%s", regnames[rs], regnames[rt]);
				break;

			case MMI_MMI0:
				debug("%s\t", mmi0_names[c790mmifunc]);
				switch (c790mmifunc) {

				case MMI0_PEXTLB:
				case MMI0_PEXTLH:
				case MMI0_PEXTLW:
				case MMI0_PMAXH:
				case MMI0_PMAXW:
				case MMI0_PPACB:
				case MMI0_PPACH:
				case MMI0_PPACW:
					debug("%s,%s,%s", regnames[rd],
					    regnames[rs], regnames[rt]);
					break;

				default:debug("(UNIMPLEMENTED)");
				}
				break;

			case MMI_MMI1:
				debug("%s\t", mmi1_names[c790mmifunc]);
				switch (c790mmifunc) {

				case MMI1_PEXTUB:
				case MMI1_PEXTUH:
				case MMI1_PEXTUW:
				case MMI1_PMINH:
				case MMI1_PMINW:
					debug("%s,%s,%s", regnames[rd],
					    regnames[rs], regnames[rt]);
					break;

				default:debug("(UNIMPLEMENTED)");
				}
				break;

			case MMI_MMI2:
				debug("%s\t", mmi2_names[c790mmifunc]);
				switch (c790mmifunc) {

				case MMI2_PMFHI:
				case MMI2_PMFLO:
					debug("%s", regnames[rd]);
					break;

				case MMI2_PHMADH:
				case MMI2_PHMSBH:
				case MMI2_PINTH:
				case MMI2_PMADDH:
				case MMI2_PMADDW:
				case MMI2_PMSUBH:
				case MMI2_PMSUBW:
				case MMI2_PMULTH:
				case MMI2_PMULTW:
				case MMI2_PSLLVW:
					debug("%s,%s,%s", regnames[rd],
					    regnames[rs], regnames[rt]);
					break;

				default:debug("(UNIMPLEMENTED)");
				}
				break;

			case MMI_MMI3:
				debug("%s\t", mmi3_names[c790mmifunc]);
				switch (c790mmifunc) {

				case MMI3_PMTHI:
				case MMI3_PMTLO:
					debug("%s", regnames[rs]);
					break;

				case MMI3_PINTEH:
				case MMI3_PMADDUW:
				case MMI3_PMULTUW:
				case MMI3_PNOR:
				case MMI3_POR:
				case MMI3_PSRAVW:
					debug("%s,%s,%s", regnames[rd],
					    regnames[rs], regnames[rt]);
					break;

				default:debug("(UNIMPLEMENTED)");
				}
				break;

			default:debug("(UNIMPLEMENTED)");
			}
			break;
		}

		/*  SPECIAL2:  */
		debug("%s\t", special2_names[special6]);

		switch (special6) {

		case SPECIAL2_MADD:
		case SPECIAL2_MADDU:
		case SPECIAL2_MSUB:
		case SPECIAL2_MSUBU:
			if (rd != MIPS_GPR_ZERO) {
				debug("WEIRD_NONZERO_RD(%s),",
				    regnames[rd]);
			}
			debug("%s,%s", regnames[rs], regnames[rt]);
			break;

		case SPECIAL2_MUL:
			/*  Apparently used both on R5900 and MIPS32:  */
			debug("%s,%s,%s", regnames[rd],
			    regnames[rs], regnames[rt]);
			break;

		case SPECIAL2_CLZ:
		case SPECIAL2_CLO:
		case SPECIAL2_DCLZ:
		case SPECIAL2_DCLO:
			debug("%s,%s", regnames[rd], regnames[rs]);
			break;

		default:
			debug("(UNIMPLEMENTED)");
		}
		break;

	case HI6_REGIMM:
		regimm5 = instr[2] & 0x1f;
		rs = ((instr[3] & 3) << 3) + ((instr[2] >> 5) & 7);
		imm = (instr[1] << 8) + instr[0];
		if (imm >= 32768)               
			imm -= 65536;

		switch (regimm5) {

		case REGIMM_BLTZ:
		case REGIMM_BGEZ:
		case REGIMM_BLTZL:
		case REGIMM_BGEZL:
		case REGIMM_BLTZAL:
		case REGIMM_BLTZALL:
		case REGIMM_BGEZAL:
		case REGIMM_BGEZALL:
			debug("%s\t%s,", regimm_names[regimm5], regnames[rs]);

			addr = (dumpaddr + 4) + (imm << 2);

                        debug("0x%016"PRIx64, (uint64_t) addr);
			break;

		case REGIMM_SYNCI:
			debug("%s\t%i(%s)", regimm_names[regimm5],
			    imm, regnames[rs]);
			break;

		default:
			debug("unimplemented regimm5 = 0x%02x", regimm5);
		}
		break;
	default:
		debug("unimplemented hi6 = 0x%02x", hi6);
	}

disasm_ret:
	//debug("\n");
	return sizeof(instrword);
}
