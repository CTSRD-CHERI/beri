#ifndef	OPCODES_MIPS_H
#define	OPCODES_MIPS_H

/*
 *  Copyright (C) 2003-2010  Anders Gavare.  All rights reserved.
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
 *
 *
 *  MIPS opcodes, gathered from various sources.
 *
 *  There are quite a number of different MIPS instruction sets, some are
 *  subsets/supersets of others, but not all of them.
 *
 *  MIPS ISA I, II, III, IV:  Backward-compatible ISAs used in R2000/R3000
 *                            (ISA I), R6000 (ISA II), R4000 (ISA III),
 *                            and R5000/R1x000 (ISA IV).
 *
 *  MIPS ISA V:               Never implemented in hardware?
 *
 *  MIPS32 and MIPS64:        The "modern" version of the ISA. These exist
 *                            in a revision 1, and a revision 2 (the latest
 *                            at the time of writing this).
 *
 *  MIPS16:                   A special encoding form for MIPS32/64 which
 *                            uses 16-bit instruction words instead of
 *                            32-bit.
 *
 *  MDMX:                     MIPS Digital Media Extension.
 *
 *  MIPS 3D:                  3D instructions.
 *
 *  MIPS MT:                  Multi-Threaded stuff.
 */


/*  Opcodes:  */

#define	HI6_NAMES	{	\
	"special", "regimm", "j",    "jal",   "beq",      "bne",   "blez",  "bgtz", 		/*  0x00 - 0x07  */	\
	"addi",    "addiu",  "slti", "sltiu", "andi",     "ori",   "xori",  "lui",		/*  0x08 - 0x0f  */	\
	"cop0",    "cop1",   "cop2", "cop3",  "beql",     "bnel",  "blezl", "bgtzl",		/*  0x10 - 0x17  */	\
	"daddi",   "daddiu", "ldl",  "ldr",   "special2", "hi6_1d","lq" /*mdmx*/, "sq" /*special3*/, /*  0x18 - 0x1f  */\
	"lb",      "lh",     "lwl",  "lw",    "lbu",      "lhu",   "lwr",   "lwu",		/*  0x20 - 0x27  */	\
	"sb",      "sh",     "swl",  "sw",    "sdl",      "sdr",   "swr",   "cache",		/*  0x28 - 0x2f  */	\
	"ll",      "lwc1",   "lwc2", "lwc3",  "lld",      "ldc1",  "ldc2",  "ld",		/*  0x30 - 0x37  */	\
	"sc",      "swc1",   "swc2", "swc3",  "scd",      "sdc1",  "sdc2",  "sd"		/*  0x38 - 0x3f  */	}

#define	REGIMM_NAMES	{	\
	"bltz",      "bgez",      "bltzl",     "bgezl",     "regimm_04", "regimm_05", "regimm_06", "regimm_07",	/*  0x00 - 0x07  */	\
	"tgei",      "tgeiu",     "tlti",      "tltiu",     "teqi",      "regimm_0d", "tnei",      "regimm_0f",	/*  0x08 - 0x0f  */	\
	"bltzal",    "bgezal",    "bltzall",   "bgezall",   "regimm_14", "regimm_15", "regimm_16", "regimm_17",	/*  0x10 - 0x17  */	\
	"mtsab",     "mtsah",     "regimm_1a", "regimm_1b", "regimm_1c", "regimm_1d", "regimm_1e", "synci"	/*  0x18 - 0x1f  */ }

#define	SPECIAL_NAMES	{	\
	"sll",     "special_01", "srl",  "sra",  "sllv",   "special_05", "srlv",   "srav",	/*  0x00 - 0x07  */	\
	"jr",      "jalr",       "movz", "movn", "syscall","break",      "special_0e", "sync",	/*  0x08 - 0x0f  */	\
	"mfhi",    "mthi",       "mflo", "mtlo", "dsllv",  "special_15", "dsrlv",  "dsrav",	/*  0x10 - 0x17  */	\
	"mult",    "multu",      "div",  "divu", "dmult",  "dmultu",     "ddiv",   "ddivu",	/*  0x18 - 0x1f  */	\
	"add",     "addu",       "sub",  "subu", "and",    "or",         "xor",    "nor",	/*  0x20 - 0x27  */	\
	"special_28","special_29","slt", "sltu", "dadd",   "daddu",      "dsub",   "dsubu",	/*  0x28 - 0x2f  */	\
	"tge",     "tgeu",       "tlt",  "tltu", "teq",    "special_35", "tne",    "special_37",/*  0x30 - 0x37  */	\
	"dsll",    "special_39", "dsrl", "dsra", "dsll32", "special_3d", "dsrl32", "dsra32"	/*  0x38 - 0x3f  */	}

/*  SPECIAL opcodes, when the rotate bit is set:  */
#define	SPECIAL_ROT_NAMES	{	\
	"rot_00",  "rot_01",  "ror",     "rot_03",  "rot_04",  "rot_05",  "rorv",   "rot_07",	/*  0x00 - 0x07  */	\
	"rot_08",  "rot_09",  "rot_0a",  "rot_0b",  "rot_0c",  "rot_0d",  "rot_0e", "rot_0f",	/*  0x08 - 0x0f  */	\
	"rot_10",  "rot_11",  "rot_12",  "rot_13",  "rot_14",  "rot_15",  "drorv",  "rot_17",	/*  0x10 - 0x17  */	\
	"rot_18",  "rot_19",  "rot_1a",  "rot_1b",  "rot_1c",  "rot_1d",  "rot_1e",  "rot_1f",	/*  0x18 - 0x1f  */	\
	"rot_20",  "rot_21",  "rot_22",  "rot_23",  "rot_24",  "rot_25",  "rot_26",  "rot_27",	/*  0x20 - 0x27  */	\
	"rot_28",  "rot_29",  "rot_2a",  "rot_2b",  "rot_2c",  "rot_2d",  "rot_2e",  "rot_2f",	/*  0x28 - 0x2f  */	\
	"rot_30",  "rot_31",  "rot_32",  "rot_33",  "rot_34",  "rot_35",  "rot_36",  "rot_37",	/*  0x30 - 0x37  */	\
	"rot_38",  "rot_39",  "dror",    "rot_3b",  "rot_3c",  "rot_3d",  "dror32",  "rot_3f"	/*  0x38 - 0x3f  */	}

#define	SPECIAL2_NAMES	{	\
	"madd",        "maddu",       "mul",         "special2_03", "msub",        "msubu",       "special2_06", "special2_07", /*  0x00 - 0x07  */	\
	"special2_08", "special2_09", "special2_0a", "special2_0b", "special2_0c", "special2_0d", "special2_0e", "special2_0f",	/*  0x08 - 0x0f  */	\
	"special2_10", "special2_11", "special2_12", "special2_13", "special2_14", "special2_15", "special2_16", "special2_17", /*  0x10 - 0x17  */	\
	"special2_18", "special2_19", "special2_1a", "special2_1b", "special2_1c", "special2_1d", "special2_1e", "special2_1f",	/*  0x18 - 0x1f  */	\
	"clz",         "clo",         "special2_22", "special2_23", "dclz",        "dclo",        "special2_26", "special2_27", /*  0x20 - 0x27  */	\
	"special2_28", "special2_29", "special2_2a", "special2_2b", "special2_2c", "special2_2d", "special2_2e", "special2_2f",	/*  0x28 - 0x2f  */	\
	"special2_30", "special2_31", "special2_32", "special2_33", "special2_34", "special2_35", "special2_36", "special2_37", /*  0x30 - 0x37  */	\
	"special2_38", "special2_39", "special2_3a", "special2_3b", "special2_3c", "special2_3d", "special2_3e", "sdbbp"	/*  0x38 - 0x3f  */  }

/*  MMI (on R5900, TX79/C790) occupies the same space as SPECIAL2  */
#define	MMI_NAMES	{	\
	"madd",   "maddu",  "mmi_02", "mmi_03", "plzcw",  "mmi_05", "mmi_06", "mmi_07", /*  0x00 - 0x07  */	\
	"mmi0",   "mmi2",   "mmi_0a", "mmi_0b", "mmi_0c", "mmi_0d", "mmi_0e", "mmi_0f",	/*  0x08 - 0x0f  */	\
	"mfhi1",  "mthi1",  "mflo1",  "mtlo1",  "mmi_14", "mmi_15", "mmi_16", "mmi_17",	/*  0x10 - 0x17  */	\
	"mult1",  "multu1", "div1",   "divu1",  "mmi_1c", "mmi_1d", "mmi_1e", "mmi_1f",	/*  0x18 - 0x1f  */	\
	"madd1",  "maddu1", "mmi_22", "mmi_23", "mmi_24", "mmi_25", "mmi_26", "mmi_27",	/*  0x20 - 0x27  */	\
	"mmi1",   "mmi3",   "mmi_2a", "mmi_2b", "mmi_2c", "mmi_2d", "mmi_2e", "mmi_2f",	/*  0x28 - 0x2f  */	\
	"pmfhl",  "pmthl",  "mmi_32", "mmi_33", "psllh",  "mmi_35", "psrlh",  "psrah",	/*  0x30 - 0x37  */	\
	"mmi_38", "mmi_39", "mmi_3a", "mmi_3b", "psllw",  "mmi_3d", "psrlw",  "psraw"	/*  0x38 - 0x3f  */	}

#define	MMI0_NAMES	{	\
	"paddw",   "psubw",   "pcgtw",   "pmaxw",	/*  0x00 - 0x03  */	\
	"paddh",   "psubh",   "pcgth",   "pmaxh",	/*  0x04 - 0x07  */	\
	"paddb",   "psubb",   "pcgtb",   "mmi0_0b",	/*  0x08 - 0x0b  */	\
	"mmi0_0c", "mmi0_0d", "mmi0_0e", "mmi0_0f",	/*  0x0c - 0x0f  */	\
	"paddsw",  "psubsw",  "pextlw",  "ppacw",	/*  0x10 - 0x13  */	\
	"paddsh",  "psubsh",  "pextlh",  "ppach",	/*  0x14 - 0x17  */	\
	"paddsb",  "psubsb",  "pextlb",  "ppacb",	/*  0x18 - 0x1b  */	\
	"mmi0_1c", "mmi0_1d", "pext5",   "ppac5"	/*  0x1c - 0x1f  */	}

#define	MMI1_NAMES	{	\
	"mmi1_00", "pabsw",   "pceqw",   "pminw",	/*  0x00 - 0x03  */	\
	"padsbh",  "pabsh",   "pceqh",   "pminh",	/*  0x04 - 0x07  */	\
	"mmi1_08", "mmi1_09", "pceqb",   "mmi1_0b",	/*  0x08 - 0x0b  */	\
	"mmi1_0c", "mmi1_0d", "mmi1_0e", "mmi1_0f",	/*  0x0c - 0x0f  */	\
	"padduw",  "psubuw",  "pextuw",  "mmi1_13",	/*  0x10 - 0x13  */	\
	"padduh",  "psubuh",  "pextuh",  "mmi1_17",	/*  0x14 - 0x17  */	\
	"paddub",  "psubub",  "pextub",  "qfsrv",	/*  0x18 - 0x1b  */	\
	"mmi1_1c", "mmi1_1d", "mmi1_1e", "mmi1_1f"	/*  0x1c - 0x1f  */	}

#define	MMI2_NAMES	{	\
	"pmaddw",  "mmi2_01", "psllvw",  "psrlvw",	/*  0x00 - 0x03  */	\
	"pmsubw",  "mmi2_05", "mmi2_06", "mmi2_07",	/*  0x04 - 0x07  */	\
	"pmfhi",   "pmflo",   "pinth",   "mmi2_0b",	/*  0x08 - 0x0b  */	\
	"pmultw",  "pdivw",   "pcpyld" , "mmi2_0f",	/*  0x0c - 0x0f  */	\
	"pmaddh",  "phmadh",  "pand",    "pxor",	/*  0x10 - 0x13  */	\
	"pmsubh",  "phmsbh",  "mmi2_16", "mmi2_17",	/*  0x14 - 0x17  */	\
	"mmi2_18", "mmi2_19", "pexeh",   "prevh",	/*  0x18 - 0x1b  */	\
	"pmulth",  "pdivbw",  "pexew",   "prot3w"	/*  0x1c - 0x1f  */	}

#define	MMI3_NAMES	{	\
	"pmadduw",  "mmi3_01", "mmi3_02", "psravw",	/*  0x00 - 0x03  */	\
	"mmi3_04",  "mmi3_05", "mmi3_06", "mmi3_07",	/*  0x04 - 0x07  */	\
	"pmthi",    "pmtlo",   "pinteh",  "mmi3_0b",	/*  0x08 - 0x0b  */	\
	"pmultuw",  "pdivuw",  "pcpyud" , "mmi3_0f",	/*  0x0c - 0x0f  */	\
	"mmi3_10",  "mmi3_11", "por",     "pnor",	/*  0x10 - 0x13  */	\
	"mmi3_14",  "mmi3_15", "mmi3_16", "mmi3_17",	/*  0x14 - 0x17  */	\
	"mmi3_18",  "mmi3_19", "pexch",   "pcpyh",	/*  0x18 - 0x1b  */	\
	"mmi3_1c",  "mmi3_1d", "pexcw",   "mmi3_1f"	/*  0x1c - 0x1f  */	}

#define	SPECIAL3_NAMES	{	\
	"ext",         "dextm",       "dextu",       "dext",        "ins",         "dinsm",       "dinsu",       "dins",	/*  0x00 - 0x07  */	\
	"special3_08", "special3_09", "special3_0a", "special3_0b", "special3_0c", "special3_0d", "special3_0e", "special3_0f",	/*  0x08 - 0x0f  */	\
	"special3_10", "special3_11", "special3_12", "special3_13", "special3_14", "special3_15", "special3_16", "special3_17", /*  0x10 - 0x17  */	\
	"special3_18", "special3_19", "special3_1a", "special3_1b", "special3_1c", "special3_1d", "special3_1e", "special3_1f",	/*  0x18 - 0x1f  */	\
	"bshfl",       "special3_21", "special3_22", "special3_23", "dbshfl",      "special3_25", "special3_26", "special3_27", /*  0x20 - 0x27  */	\
	"special3_28", "special3_29", "special3_2a", "special3_2b", "special3_2c", "special3_2d", "special3_2e", "special3_2f",	/*  0x28 - 0x2f  */	\
	"special3_30", "special3_31", "special3_32", "special3_33", "special3_34", "special3_35", "special3_36", "special3_37", /*  0x30 - 0x37  */	\
	"special3_38", "special3_39", "special3_3a", "rdhwr",       "special3_3c", "special3_3d", "special3_3e", "special3_3f"	/*  0x38 - 0x3f  */  }

#define	HI6_SPECIAL			0x00	/*  000000  */
#define	    SPECIAL_SLL			    0x00    /*  000000  */	/*  MIPS I  */
/*					    0x01	000001  */
#define	    SPECIAL_SRL			    0x02    /*	000010  */	/*  MIPS I  */
#define	    SPECIAL_SRA			    0x03    /*  000011  */	/*  MIPS I  */
#define	    SPECIAL_SLLV		    0x04    /*  000100  */	/*  MIPS I  */
/*					    0x05	000101  */
#define	    SPECIAL_SRLV		    0x06    /*  000110  */
#define	    SPECIAL_SRAV		    0x07    /*  000111  */	/*  MIPS I  */
#define	    SPECIAL_JR			    0x08    /*  001000  */	/*  MIPS I  */
#define	    SPECIAL_JALR		    0x09    /*  001001  */	/*  MIPS I  */
#define	    SPECIAL_MOVZ		    0x0a    /*	001010  */	/*  MIPS IV  */
#define	    SPECIAL_MOVN		    0x0b    /*	001011  */	/*  MIPS IV  */
#define	    SPECIAL_SYSCALL		    0x0c    /*	001100  */	/*  MIPS I  */
#define	    SPECIAL_BREAK		    0x0d    /*	001101  */	/*  MIPS I  */
/*					    0x0e	001110  */
#define	    SPECIAL_SYNC		    0x0f    /*	001111  */	/*  MIPS II  */
#define	    SPECIAL_MFHI		    0x10    /*  010000  */	/*  MIPS I  */
#define	    SPECIAL_MTHI		    0x11    /*	010001  */	/*  MIPS I  */
#define	    SPECIAL_MFLO		    0x12    /*  010010  */	/*  MIPS I  */
#define	    SPECIAL_MTLO		    0x13    /*	010011  */	/*  MIPS I  */
#define	    SPECIAL_DSLLV		    0x14    /*	010100  */
/*					    0x15	010101  */
#define	    SPECIAL_DSRLV		    0x16    /*  010110  */	/*  MIPS III  */
#define	    SPECIAL_DSRAV		    0x17    /*  010111  */	/*  MIPS III  */
#define	    SPECIAL_MULT		    0x18    /*  011000  */	/*  MIPS I  */
#define	    SPECIAL_MULTU		    0x19    /*	011001  */	/*  MIPS I  */
#define	    SPECIAL_DIV			    0x1a    /*  011010  */	/*  MIPS I  */
#define	    SPECIAL_DIVU		    0x1b    /*	011011  */	/*  MIPS I  */
#define	    SPECIAL_DMULT		    0x1c    /*  011100  */	/*  MIPS III  */
#define	    SPECIAL_DMULTU		    0x1d    /*  011101  */	/*  MIPS III  */
#define	    SPECIAL_DDIV		    0x1e    /*  011110  */	/*  MIPS III  */
#define	    SPECIAL_DDIVU		    0x1f    /*  011111  */	/*  MIPS III  */
#define	    SPECIAL_ADD			    0x20    /*	100000  */	/*  MIPS I  */
#define	    SPECIAL_ADDU		    0x21    /*  100001  */	/*  MIPS I  */
#define	    SPECIAL_SUB			    0x22    /*  100010  */	/*  MIPS I  */
#define	    SPECIAL_SUBU		    0x23    /*  100011  */	/*  MIPS I  */
#define	    SPECIAL_AND			    0x24    /*  100100  */	/*  MIPS I  */
#define	    SPECIAL_OR			    0x25    /*  100101  */	/*  MIPS I  */
#define	    SPECIAL_XOR			    0x26    /*  100110  */	/*  MIPS I  */
#define	    SPECIAL_NOR			    0x27    /*  100111  */	/*  MIPS I  */
#define	    SPECIAL_MFSA		    0x28    /*  101000  */  	/*  R5900/TX79/C790  */
#define	    SPECIAL_MTSA		    0x29    /*  101001  */  	/*  R5900/TX79/C790  */
#define	    SPECIAL_SLT			    0x2a    /*  101010  */	/*  MIPS I  */
#define	    SPECIAL_SLTU		    0x2b    /*  101011  */	/*  MIPS I  */
#define	    SPECIAL_DADD		    0x2c    /*  101100  */	/*  MIPS III  */
#define	    SPECIAL_DADDU		    0x2d    /*	101101  */	/*  MIPS III  */
#define	    SPECIAL_DSUB		    0x2e    /*	101110  */
#define	    SPECIAL_DSUBU		    0x2f    /*	101111  */	/*  MIPS III  */
#define	    SPECIAL_TGE			    0x30    /*	110000  */
#define	    SPECIAL_TGEU		    0x31    /*	110001  */
#define	    SPECIAL_TLT			    0x32    /*	110010  */
#define	    SPECIAL_TLTU		    0x33    /*	110011  */
#define	    SPECIAL_TEQ			    0x34    /*	110100  */
/*					    0x35	110101  */
#define	    SPECIAL_TNE			    0x36    /*	110110  */
/*					    0x37	110111  */
#define	    SPECIAL_DSLL		    0x38    /*  111000  */	/*  MIPS III  */
/*					    0x39	111001  */
#define	    SPECIAL_DSRL		    0x3a    /*  111010  */	/*  MIPS III  */
#define	    SPECIAL_DSRA		    0x3b    /*  111011  */	/*  MIPS III  */
#define	    SPECIAL_DSLL32		    0x3c    /*  111100  */	/*  MIPS III  */
/*					    0x3d	111101  */
#define	    SPECIAL_DSRL32		    0x3e    /*  111110  */	/*  MIPS III  */
#define	    SPECIAL_DSRA32		    0x3f    /*  111111  */	/*  MIPS III  */

#define	HI6_REGIMM			0x01	/*  000001  */
#define	    REGIMM_BLTZ			    0x00    /*  00000  */	/*  MIPS I  */
#define	    REGIMM_BGEZ			    0x01    /*  00001  */	/*  MIPS I  */
#define	    REGIMM_BLTZL		    0x02    /*  00010  */	/*  MIPS II  */
#define	    REGIMM_BGEZL		    0x03    /*  00011  */	/*  MIPS II  */
#define	    REGIMM_TGEI			    0x08    /*  01000  */
#define	    REGIMM_TGEIU		    0x09    /*  01001  */
#define	    REGIMM_TLTI			    0x0a    /*  01010  */
#define	    REGIMM_TLTIU		    0x0b    /*  01011  */
#define	    REGIMM_TEQI			    0x0c    /*  01100  */
#define	    REGIMM_TNEI			    0x0e    /*  01110  */
#define	    REGIMM_BLTZAL		    0x10    /*  10000  */
#define	    REGIMM_BGEZAL		    0x11    /*  10001  */
#define	    REGIMM_BLTZALL		    0x12    /*  10010  */
#define	    REGIMM_BGEZALL		    0x13    /*  10011  */
#define	    REGIMM_MTSAB		    0x18    /*  11000  */	/*  R5900/TX79/C790  */
#define	    REGIMM_MTSAH		    0x19    /*  11001  */	/*  R5900/TX79/C790  */
#define	    REGIMM_SYNCI		    0x1f    /*  11111  */
/*  regimm ...............  */

#define	HI6_J				0x02	/*  000010  */	/*  MIPS I  */
#define	HI6_JAL				0x03	/*  000011  */	/*  MIPS I  */
#define	HI6_BEQ				0x04	/*  000100  */	/*  MIPS I  */
#define	HI6_BNE				0x05	/*  000101  */
#define	HI6_BLEZ			0x06	/*  000110  */	/*  MIPS I  */
#define	HI6_BGTZ			0x07	/*  000111  */	/*  MIPS I  */
#define	HI6_ADDI			0x08	/*  001000  */	/*  MIPS I  */
#define	HI6_ADDIU			0x09	/*  001001  */	/*  MIPS I  */
#define	HI6_SLTI			0x0a	/*  001010  */	/*  MIPS I  */
#define	HI6_SLTIU			0x0b	/*  001011  */	/*  MIPS I  */
#define	HI6_ANDI			0x0c	/*  001100  */	/*  MIPS I  */
#define	HI6_ORI				0x0d	/*  001101  */	/*  MIPS I  */
#define	HI6_XORI			0x0e    /*  001110  */	/*  MIPS I  */
#define	HI6_LUI				0x0f	/*  001111  */	/*  MIPS I  */
#define	HI6_COP0			0x10	/*  010000  */
#define	    COPz_MFCz			    0x00    /*  00000  */
#define	    COPz_DMFCz			    0x01    /*  00001  */
#define	    COPz_MTCz			    0x04    /*  00100  */
#define	    COPz_DMTCz			    0x05    /*  00101  */
/*
 *  For cop1 (the floating point coprocessor), if bits 25..21 are
 *  a valid format, then bits 5..0 are the math opcode.
 *
 *  Otherwise, bits 25..21 are the main coprocessor opcode.
 */
#define	    COPz_CFCz			    0x02    /*  00010  */  /*  MIPS I  */
#define	    COPz_CTCz			    0x06    /*  00110  */  /*  MIPS I  */
#define	    COPz_BCzc			    0x08    /*  01000  */
#define	    COPz_MFMCz			    0x0b    /*  01011  */
#define	    COP1_FMT_S			    0x10    /*  10000  */
#define	    COP1_FMT_D			    0x11    /*  10001  */
#define	    COP1_FMT_W			    0x14    /*  10100  */
#define	    COP1_FMT_L			    0x15    /*  10101  */
#define	    COP1_FMT_PS			    0x16    /*  10110  */
/*  COP0 opcodes = bits 7..0 (only if COP0 and CO=1):  */
#define	    COP0_TLBR			    0x01    /*  000001  */
#define	    COP0_TLBWI			    0x02    /*  000010  */
#define	    COP0_TLBWR			    0x06    /*  000110  */
#define	    COP0_TLBP			    0x08    /*  001000  */
#define	    COP0_RFE			    0x10    /*  010000  */
#define	    COP0_ERET			    0x18    /*  011000  */
#define	    COP0_DERET			    0x1f    /*  011111  */  /*  EJTAG  */
#define	    COP0_WAIT			    0x20    /*  100000  */  /*  MIPS32/64  */
#define	    COP0_STANDBY		    0x21    /*  100001  */
#define	    COP0_SUSPEND		    0x22    /*  100010  */
#define	    COP0_HIBERNATE		    0x23    /*  100011  */
#define	    COP0_EI			    0x38    /*  111000  */  /*  R5900/TX79/C790  */
#define	    COP0_DI			    0x39    /*  111001  */  /*  R5900/TX79/C790  */
#define	HI6_COP1			0x11	/*  010001  */
#define	HI6_COP2			0x12	/*  010010  */
#define	HI6_COP3			0x13	/*  010011  */
#define	HI6_BEQL			0x14	/*  010100  */	/*  MIPS II  */
#define	HI6_BNEL			0x15	/*  010101  */
#define	HI6_BLEZL			0x16	/*  010110  */	/*  MIPS II  */
#define	HI6_BGTZL			0x17	/*  010111  */	/*  MIPS II  */
#define	HI6_DADDI			0x18	/*  011000  */	/*  MIPS III  */
#define	HI6_DADDIU			0x19	/*  011001  */	/*  MIPS III  */
#define	HI6_LDL				0x1a	/*  011010  */	/*  MIPS III  */
#define	HI6_LDR				0x1b	/*  011011  */	/*  MIPS III  */
#define	HI6_SPECIAL2			0x1c	/*  011100  */
#define	    SPECIAL2_MADD		    0x00    /*  000000  */  /*  MIPS32 (?) TODO  */
#define	    SPECIAL2_MADDU		    0x01    /*  000001  */  /*  MIPS32 (?) TODO  */
#define	    SPECIAL2_MUL		    0x02    /*  000010  */  /*  MIPS32 (?) TODO  */
#define	    SPECIAL2_MSUB		    0x04    /*  000100  */  /*  MIPS32 (?) TODO  */
#define	    SPECIAL2_MSUBU		    0x05    /*  000001  */  /*  MIPS32 (?) TODO  */
#define	    SPECIAL2_CLZ		    0x20    /*  100100  */  /*  MIPS32  */
#define	    SPECIAL2_CLO		    0x21    /*  100101  */  /*  MIPS32  */
#define	    SPECIAL2_DCLZ		    0x24    /*  100100  */  /*  MIPS64  */
#define	    SPECIAL2_DCLO		    0x25    /*  100101  */  /*  MIPS64  */
#define	    SPECIAL2_SDBBP		    0x3f    /*  111111  */  /*  EJTAG (?)  TODO  */
/*  MMI (R5900, TX79/C790) occupies the same opcode space as SPECIAL2:  */
#define	    MMI_MADD			    0x00
#define	    MMI_MADDU			    0x01
#define	    MMI_PLZCW			    0x04
#define	    MMI_MMI0			    0x08
#define		MMI0_PADDW			0x00
#define		MMI0_PSUBW			0x01
#define		MMI0_PCGTW			0x02
#define		MMI0_PMAXW			0x03
#define		MMI0_PADDH			0x04
#define		MMI0_PSUBH			0x05
#define		MMI0_PCGTH			0x06
#define		MMI0_PMAXH			0x07
#define		MMI0_PADDB			0x08
#define		MMI0_PSUBB			0x09
#define		MMI0_PCGTB			0x0a
#define		MMI0_PADDSW			0x10
#define		MMI0_PSUBSW			0x11
#define		MMI0_PEXTLW			0x12
#define		MMI0_PPACW			0x13
#define		MMI0_PADDSH			0x14
#define		MMI0_PSUBSH			0x15
#define		MMI0_PEXTLH			0x16
#define		MMI0_PPACH			0x17
#define		MMI0_PADDSB			0x18
#define		MMI0_PSUBSB			0x19
#define		MMI0_PEXTLB			0x1a
#define		MMI0_PPACB			0x1b
#define		MMI0_PEXT5			0x1e
#define		MMI0_PPAC5			0x1f
#define	    MMI_MMI2			    0x09
#define		MMI2_PMADDW			0x00
#define		MMI2_PSLLVW			0x02
#define		MMI2_PSRLVW			0x03
#define		MMI2_PMSUBW			0x04
#define		MMI2_PMFHI			0x08
#define		MMI2_PMFLO			0x09
#define		MMI2_PINTH			0x0a
#define		MMI2_PMULTW			0x0c
#define		MMI2_PDIVW			0x0d
#define		MMI2_PCPYLD			0x0e
#define		MMI2_PMADDH			0x10
#define		MMI2_PHMADH			0x11
#define		MMI2_PAND			0x12
#define		MMI2_PXOR			0x13
#define		MMI2_PMSUBH			0x14
#define		MMI2_PHMSBH			0x15
#define		MMI2_PEXEH			0x1a
#define		MMI2_PREVH			0x1b
#define		MMI2_PMULTH			0x1c
#define		MMI2_PDIVBW			0x1d
#define		MMI2_PEXEW			0x1e
#define		MMI2_PROT3W			0x1f
#define	    MMI_MFHI1			    0x10
#define	    MMI_MTHI1			    0x11
#define	    MMI_MFLO1			    0x12
#define	    MMI_MTLO1			    0x13
#define	    MMI_MULT1			    0x18
#define	    MMI_MULTU1			    0x19
#define	    MMI_DIV1			    0x1a
#define	    MMI_DIVU1			    0x1b
#define	    MMI_MADD1			    0x20
#define	    MMI_MADDU1			    0x21
#define	    MMI_MMI1			    0x28
#define		MMI1_PABSW			0x01
#define		MMI1_PCEQW			0x02
#define		MMI1_PMINW			0x03
#define		MMI1_PADSBH			0x04
#define		MMI1_PABSH			0x05
#define		MMI1_PCEQH			0x06
#define		MMI1_PMINH			0x07
#define		MMI1_PCEQB			0x0a
#define		MMI1_PADDUW			0x10
#define		MMI1_PSUBUW			0x11
#define		MMI1_PEXTUW			0x12
#define		MMI1_PADDUH			0x14
#define		MMI1_PSUBUH			0x15
#define		MMI1_PEXTUH			0x16
#define		MMI1_PADDUB			0x18
#define		MMI1_PSUBUB			0x19
#define		MMI1_PEXTUB			0x1a
#define		MMI1_QFSRV			0x1b
#define	    MMI_MMI3			    0x29
#define		MMI3_PMADDUW			0x00
#define		MMI3_PSRAVW			0x03
#define		MMI3_PMTHI			0x08
#define		MMI3_PMTLO			0x09
#define		MMI3_PINTEH			0x0a
#define		MMI3_PMULTUW			0x0c
#define		MMI3_PDIVUW			0x0d
#define		MMI3_PCPYUD			0x0e
#define		MMI3_POR			0x12
#define		MMI3_PNOR			0x13
#define		MMI3_PEXCH			0x1a
#define		MMI3_PCPYH			0x1b
#define		MMI3_PEXCW			0x1e
#define	    MMI_PMFHL			    0x30
#define	    MMI_PMTHL			    0x31
#define	    MMI_PSLLH			    0x34
#define	    MMI_PSRLH			    0x36
#define	    MMI_PSRAH			    0x37
#define	    MMI_PSLLW			    0x3c
#define	    MMI_PSRLW			    0x3e
#define	    MMI_PSRAW			    0x3f
/*	JALX (TODO)			0x1d	    011101  */
#define	HI6_LQ_MDMX			0x1e	/*  011110  */	/*  lq on R5900, MDMX on others?  */
/*  TODO: MDMX opcodes  */
#define	HI6_SQ_SPECIAL3			0x1f	/*  011111  */	/*  sq on R5900, SPECIAL3 on MIPS32/64 rev 2  */
#define	    SPECIAL3_EXT		    0x00    /*  000000  */
#define	    SPECIAL3_DEXTM		    0x01    /*  000001  */
#define	    SPECIAL3_DEXTU		    0x02    /*  000010  */
#define	    SPECIAL3_DEXT		    0x03    /*  000011  */
#define	    SPECIAL3_INS		    0x04    /*  000100  */
#define	    SPECIAL3_DINSM		    0x05    /*  000101  */
#define	    SPECIAL3_DINSU		    0x06    /*  000110  */
#define	    SPECIAL3_DINS		    0x07    /*  000111  */
#define	    SPECIAL3_BSHFL		    0x20    /*  100000  */
#define	        BSHFL_WSBH			0x002	/*  00000..00010  */
#define	        BSHFL_SEB			0x010	/*  00000..10000  */
#define	        BSHFL_SEH			0x018	/*  00000..11000  */
#define	    SPECIAL3_DBSHFL		    0x24    /*  100100  */
#define	        BSHFL_DSBH			0x002	/*  00000..00010  */
#define	        BSHFL_DSHD			0x005	/*  00000..00101  */
#define	    SPECIAL3_RDHWR		    0x3b    /*  111011  */
#define	HI6_LB				0x20	/*  100000  */	/*  MIPS I  */
#define	HI6_LH				0x21	/*  100001  */	/*  MIPS I  */
#define	HI6_LWL				0x22	/*  100010  */	/*  MIPS I  */
#define	HI6_LW				0x23	/*  100011  */	/*  MIPS I  */
#define	HI6_LBU				0x24	/*  100100  */	/*  MIPS I  */
#define	HI6_LHU				0x25	/*  100101  */	/*  MIPS I  */
#define	HI6_LWR				0x26	/*  100110  */	/*  MIPS I  */
#define	HI6_LWU				0x27	/*  100111  */	/*  MIPS III  */
#define	HI6_SB				0x28	/*  101000  */	/*  MIPS I  */
#define	HI6_SH				0x29	/*  101001  */	/*  MIPS I  */
#define	HI6_SWL				0x2a	/*  101010  */	/*  MIPS I  */
#define	HI6_SW				0x2b	/*  101011  */	/*  MIPS I  */
#define	HI6_SDL				0x2c	/*  101100  */	/*  MIPS III  */
#define	HI6_SDR				0x2d	/*  101101  */	/*  MIPS III  */
#define	HI6_SWR				0x2e	/*  101110  */	/*  MIPS I  */
#define	HI6_CACHE			0x2f	/*  101111  */	/*  ??? R4000  */
#define	HI6_LL				0x30	/*  110000  */	/*  MIPS II  */
#define	HI6_LWC1			0x31	/*  110001  */	/*  MIPS I  */
#define	HI6_LWC2			0x32	/*  110010  */	/*  MIPS I  */
#define	HI6_LWC3			0x33	/*  110011  */	/*  MIPS I  */
#define	HI6_LLD				0x34	/*  110100  */	/*  MIPS III  */
#define	HI6_LDC1			0x35	/*  110101  */	/*  MIPS II  */
#define	HI6_LDC2			0x36	/*  110110  */	/*  MIPS II  */
#define	HI6_LD				0x37	/*  110111  */	/*  MIPS III  */
#define	HI6_SC				0x38	/*  111000  */	/*  MIPS II  */
#define	HI6_SWC1			0x39	/*  111001  */	/*  MIPS I  */
#define	HI6_SWC2			0x3a	/*  111010  */	/*  MIPS I  */
#define	HI6_SWC3			0x3b	/*  111011  */	/*  MIPS I  */
#define	HI6_SCD				0x3c	/*  111100  */	/*  MIPS III  */
#define	HI6_SDC1			0x3d	/*  111101  */  /*  MIPS II  */
#define	HI6_SDC2			0x3e	/*  111110  */  /*  MIPS II  */
#define	HI6_SD				0x3f	/*  111111  */	/*  MIPS III  */

/*  TODO:  Coproc registers are actually CPU dependent, so an R4000
	has other bits/registers than an R3000...
    TODO 2: CPUs like the R10000 are probably even a bit more different.  */

/*  Coprocessor 0's registers' names: (max 8 characters long)  */
#define	COP0_NAMES	{ \
	"index", "random", "entrylo0", "entrylo1", \
	"context", "pagemask", "wired", "reserv7", \
	"badvaddr", "count", "entryhi", "compare", \
	"status", "cause", "epc", "prid", \
	"config", "lladdr", "watchlo", "watchhi", \
	"xcontext", "reserv21", "reserv22", "debug", \
	"depc", "perfcnt", "errctl", "cacheerr", \
	"tagdatlo", "tagdathi", "errorepc", "desave" }

#define	COP0_INDEX		0
#define	   INDEX_P		    0x80000000UL	/*  Probe failure bit. Set by tlbp  */
#define	   INDEX_MASK		    0x3f
#define	   R2K3K_INDEX_P	    0x80000000UL
#define	   R2K3K_INDEX_MASK	    0x3f00
#define	   R2K3K_INDEX_SHIFT	    8
#define	COP0_RANDOM		1
#define	   RANDOM_MASK		    0x3f
#define	   R2K3K_RANDOM_MASK	    0x3f00
#define	   R2K3K_RANDOM_SHIFT	    8
#define	COP0_ENTRYLO0		2
#define	COP0_ENTRYLO1		3
/*  R4000 ENTRYLO:  */
#define	   ENTRYLO_PFN_MASK	    0x3fffffc0
#define	   ENTRYLO_PFN_SHIFT	    6
#define	   ENTRYLO_C_MASK	    0x00000038		/*  Coherency attribute  */
#define	   ENTRYLO_C_SHIFT	    3
#define	   ENTRYLO_D		    0x04		/*  Dirty bit  */
#define	   ENTRYLO_V		    0x02		/*  Valid bit  */
#define	   ENTRYLO_G		    0x01		/*  Global bit  */
/*  R2000/R3000 ENTRYLO:  */
#define	   R2K3K_ENTRYLO_PFN_MASK   0xfffff000UL
#define	   R2K3K_ENTRYLO_PFN_SHIFT  12
#define	   R2K3K_ENTRYLO_N	    0x800
#define	   R2K3K_ENTRYLO_D	    0x400
#define	   R2K3K_ENTRYLO_V	    0x200
#define	   R2K3K_ENTRYLO_G	    0x100
#define	COP0_CONTEXT		4
#define	   CONTEXT_BADVPN2_MASK	    0x007ffff0
#define	   CONTEXT_BADVPN2_MASK_R4100	    0x01fffff0
#define	   CONTEXT_BADVPN2_SHIFT    4
#define	   R2K3K_CONTEXT_BADVPN_MASK	 0x001ffffc
#define	   R2K3K_CONTEXT_BADVPN_SHIFT    2
#define	COP0_PAGEMASK		5
#define	   PAGEMASK_MASK	    0x01ffe000
#define	   PAGEMASK_SHIFT	    13
#define	   PAGEMASK_MASK_R4100	    0x0007f800	/*  TODO: At least VR4131,  */
						/*  how about others?  */
#define	   PAGEMASK_SHIFT_R4100	    11
#define	COP0_WIRED		6
#define	COP0_RESERV7		7
#define	COP0_BADVADDR		8
#define	COP0_COUNT		9
#define	COP0_ENTRYHI		10
/*  R4000 ENTRYHI:  */
#define	   ENTRYHI_R_MASK	    0xc000000000000000ULL
#define	   ENTRYHI_R_XKPHYS	    0x8000000000000000ULL
#define	   ENTRYHI_R_SHIFT	    62
#define	   ENTRYHI_VPN2_MASK_R10K   0x00000fffffffe000ULL
#define	   ENTRYHI_VPN2_MASK	    0x000000ffffffe000ULL
#define	   ENTRYHI_VPN2_SHIFT	    13
#define	   ENTRYHI_ASID		    0xff
#define	   TLB_G		    (1 << 12)
/*  R2000/R3000 ENTRYHI:  */
#define	   R2K3K_ENTRYHI_VPN_MASK   0xfffff000UL
#define	   R2K3K_ENTRYHI_VPN_SHIFT  12
#define	   R2K3K_ENTRYHI_ASID_MASK  0xfc0
#define	   R2K3K_ENTRYHI_ASID_SHIFT 6
#define	COP0_COMPARE		11
#define	COP0_STATUS		12
#define	   STATUS_CU_MASK	    0xf0000000UL	/*  coprocessor usable bits  */
#define	   STATUS_CU_SHIFT	    28
#define	   STATUS_RP		    0x08000000		/*  reduced power  */
#define	   STATUS_FR		    0x04000000		/*  1=32 float regs, 0=16  */
#define	   STATUS_RE		    0x02000000		/*  reverse endian bit  */
#define	   STATUS_BEV		    0x00400000		/*  boot exception vectors (?)  */
/*  STATUS_DS: TODO  */
#define	   STATUS_IM_MASK	    0xff00
#define	   STATUS_IM_SHIFT	    8
#define	   STATUS_KX		    0x80
#define	   STATUS_SX		    0x40
#define	   STATUS_UX		    0x20
#define	   STATUS_KSU_MASK	    0x18
#define	   STATUS_KSU_SHIFT	    3
#define	   STATUS_ERL		    0x04
#define	   STATUS_EXL		    0x02
#define	   STATUS_IE		    0x01
#define	   R5900_STATUS_EDI	    0x20000		/*  EI/DI instruction enable  */
#define	   R5900_STATUS_EIE	    0x10000		/*  Enable Interrupt Enable  */
#define	COP0_CAUSE		13
#define	   CAUSE_BD		    0x80000000UL	/*  branch delay flag  */
#define	   CAUSE_CE_MASK	    0x30000000		/*  which coprocessor  */
#define	   CAUSE_CE_SHIFT	    28
#define	   CAUSE_IV		    0x00800000UL	/*  interrupt vector at offset 0x200 instead of 0x180  */
#define	   CAUSE_WP		    0x00400000UL	/*  watch exception ...  */
#define	   CAUSE_IP_MASK	    0xff00		/*  interrupt pending  */
#define	   CAUSE_IP_SHIFT	    8
#define    CAUSE_EXCCODE_MASK	    0x7c		/*  exception code  */
#define    R2K3K_CAUSE_EXCCODE_MASK 0x3c
#define	   CAUSE_EXCCODE_SHIFT	    2
#define	COP0_EPC		14
#define	COP0_PRID		15
#define	COP0_CONFIG		16
#define	COP0_LLADDR		17
#define	COP0_WATCHLO		18
#define	COP0_WATCHHI		19
#define	COP0_XCONTEXT		20
#define	   XCONTEXT_R_MASK          0x180000000ULL
#define	   XCONTEXT_R_SHIFT         31
#define	   XCONTEXT_BADVPN2_MASK    0x7ffffff0
#define	   XCONTEXT_BADVPN2_SHIFT   4
#define	COP0_FRAMEMASK		21		/*  R10000  */
#define	COP0_RESERV22		22
#define	COP0_DEBUG		23
#define	COP0_DEPC		24
#define	COP0_PERFCNT		25
#define	COP0_ERRCTL		26
#define	COP0_CACHEERR		27
#define	COP0_TAGDATA_LO		28
#define	COP0_TAGDATA_HI		29
#define	COP0_ERROREPC		30
#define	COP0_DESAVE		31

/*  Coprocessor 1's registers:  */
#define	COP1_REVISION		0
#define	  COP1_REVISION_MIPS3D	    0x80000		/*  MIPS3D support  */
#define	  COP1_REVISION_PS	    0x40000		/*  Paired-single support  */
#define	  COP1_REVISION_DOUBLE	    0x20000		/*  double precision support  */
#define	  COP1_REVISION_SINGLE	    0x10000		/*  single precision support  */
#define	COP1_CONTROLSTATUS	31

/*  CP0's STATUS KSU values:  */
#define	KSU_KERNEL		0
#define	KSU_SUPERVISOR		1
#define	KSU_USER		2

#define	EXCEPTION_NAMES		{ \
	"INT", "MOD", "TLBL", "TLBS", "ADEL", "ADES", "IBE", "DBE",	\
	"SYS", "BP", "RI", "CPU", "OV", "TR", "VCEI", "FPE",		\
	"16?", "17?", "C2E", "19?", "20?", "21?", "MDMX", "WATCH",	\
	"MCHECK", "25?", "26?", "27?", "28?", "29?", "CACHEERR", "VCED" }

/*  CP0's CAUSE exception codes:  */
#define	EXCEPTION_INT		0	/*  Interrupt  */
#define	EXCEPTION_MOD		1	/*  TLB modification exception  */
#define	EXCEPTION_TLBL		2	/*  TLB exception (load or instruction fetch)  */
#define	EXCEPTION_TLBS		3	/*  TLB exception (store)  */
#define	EXCEPTION_ADEL		4	/*  Address Error Exception (load/instr. fetch)  */
#define	EXCEPTION_ADES		5	/*  Address Error Exception (store)  */
#define	EXCEPTION_IBE		6	/*  Bus Error Exception (instruction fetch)  */
#define	EXCEPTION_DBE		7	/*  Bus Error Exception (data: load or store)  */
#define	EXCEPTION_SYS		8	/*  Syscall  */
#define	EXCEPTION_BP		9	/*  Breakpoint  */
#define	EXCEPTION_RI		10	/*  Reserved instruction  */
#define	EXCEPTION_CPU		11	/*  CoProcessor Unusable  */
#define	EXCEPTION_OV		12	/*  Arithmetic Overflow  */
#define	EXCEPTION_TR		13	/*  Trap exception  */
#define	EXCEPTION_VCEI		14	/*  Virtual Coherency Exception, Instruction  */
#define	EXCEPTION_FPE		15	/*  Floating point exception  */
/*  16..17: Available for "implementation dependent use"  */
#define	EXCEPTION_C2E		18	/*  MIPS64 C2E (precise coprocessor 2 exception)  */
/*  19..21: Reserved  */
#define	EXCEPTION_MDMX		22	/*  MIPS64 MDMX unusable  */
#define	EXCEPTION_WATCH		23	/*  Reference to WatchHi/WatchLo address  */
#define	EXCEPTION_MCHECK	24	/*  MIPS64 Machine Check  */
/*  25..29: Reserved  */
#define	EXCEPTION_CACHEERR	30	/*  MIPS64 Cache Error  */
#define	EXCEPTION_VCED		31	/*  Virtual Coherency Exception, Data  */

#define MIPS_REGISTER_NAMES	{ \
	"zr", "at", "v0", "v1", "a0", "a1", "a2", "a3", \
	"t0", "t1", "t2", "t3", "t4", "t5", "t6", "t7", \
	"s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7", \
	"t8", "t9", "k0", "k1", "gp", "sp", "fp", "ra"  }

#define	MIPS_GPR_ZERO		0		/*  zero  */
#define	MIPS_GPR_AT		1		/*  at  */
#define	MIPS_GPR_V0		2		/*  v0  */
#define	MIPS_GPR_V1		3		/*  v1  */
#define	MIPS_GPR_A0		4		/*  a0  */
#define	MIPS_GPR_A1		5		/*  a1  */
#define	MIPS_GPR_A2		6		/*  a2  */
#define	MIPS_GPR_A3		7		/*  a3  */
#define	MIPS_GPR_T0		8		/*  t0  */
#define	MIPS_GPR_T1		9		/*  t1  */
#define	MIPS_GPR_T2		10		/*  t2  */
#define	MIPS_GPR_T3		11		/*  t3  */
#define	MIPS_GPR_T4		12		/*  t4  */
#define	MIPS_GPR_T5		13		/*  t5  */
#define	MIPS_GPR_T6		14		/*  t6  */
#define	MIPS_GPR_T7		15		/*  t7  */
#define	MIPS_GPR_S0		16		/*  s0  */
#define	MIPS_GPR_S1		17		/*  s1  */
#define	MIPS_GPR_S2		18		/*  s2  */
#define	MIPS_GPR_S3		19		/*  s3  */
#define	MIPS_GPR_S4		20		/*  s4  */
#define	MIPS_GPR_S5		21		/*  s5  */
#define	MIPS_GPR_S6		22		/*  s6  */
#define	MIPS_GPR_S7		23		/*  s7  */
#define	MIPS_GPR_T8		24		/*  t8  */
#define	MIPS_GPR_T9		25		/*  t9  */
#define	MIPS_GPR_K0		26		/*  k0  */
#define	MIPS_GPR_K1		27		/*  k1  */
#define	MIPS_GPR_GP		28		/*  gp  */
#define	MIPS_GPR_SP		29		/*  sp  */
#define	MIPS_GPR_FP		30		/*  fp  */
#define	MIPS_GPR_RA		31		/*  ra  */

#define	N_HI6			64
#define	N_SPECIAL		64
#define	N_REGIMM		32


/*  An "impossible" paddr:  */
#define	IMPOSSIBLE_PADDR		0x1212343456566767ULL

#define	DEFAULT_PCACHE_SIZE		15	/*  32 KB  */
#define	DEFAULT_PCACHE_LINESIZE		5	/*  32 bytes  */

#define	R3000_TAG_VALID		1
#define	R3000_TAG_DIRTY		2


#define	MIPS_IC_ENTRIES_SHIFT		10

#define	MIPS_N_IC_ARGS			3
#define	MIPS_INSTR_ALIGNMENT_SHIFT	2
#define	MIPS_IC_ENTRIES_PER_PAGE	(1 << MIPS_IC_ENTRIES_SHIFT)
#define	MIPS_PC_TO_IC_ENTRY(a)		(((a)>>MIPS_INSTR_ALIGNMENT_SHIFT) \
					& (MIPS_IC_ENTRIES_PER_PAGE-1))
#define	MIPS_ADDR_TO_PAGENR(a)		((a) >> (MIPS_IC_ENTRIES_SHIFT \
					+ MIPS_INSTR_ALIGNMENT_SHIFT))

#define	MIPS_L2N		17
#define	MIPS_L3N		18

#define	MIPS_MAX_VPH_TLB_ENTRIES	192

#endif	/*  OPCODES_MIPS_H  */
