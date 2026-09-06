// Replacement for riscv-tests env/p/riscv_test.h, for a core with no CSRs.
//
// The upstream environment sets up mtvec, delegation, PMP and reports
// pass/fail through an ecall into a trap handler that writes `tohost`.
// This core has none of that, so:
//
//   PASS  a0 = 1, then ebreak
//   FAIL  a0 = 0, then ebreak; gp (TESTNUM) still holds the failing case
//
// tb_isa.sv treats ebreak with an empty pipeline as completion and reads
// a0 and gp straight out of the register file.
//
// The nop before every ebreak matters: a trap decoded while the previous
// instruction is still in Execute squashes that instruction on this core
// (see C_test/start.S). `li` is safe, but keep the guard anyway.

#ifndef _ENV_PIPELINED_TEST_H
#define _ENV_PIPELINED_TEST_H

#define RVTEST_RV32U
#define RVTEST_RV64U

#define TESTNUM gp

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align  2;                                                      \
        .globl _start;                                                  \
_start:                                                                 \
        lui   sp, 0x10;                                                 \
        li    TESTNUM, 0;

#define RVTEST_CODE_END                                                 \
        nop;                                                            \
        nop;                                                            \
1:      j 1b;

#define RVTEST_PASS                                                     \
        fence;                                                          \
        li    a0, 1;                                                    \
        nop;                                                            \
        ebreak

#define RVTEST_FAIL                                                     \
        fence;                                                          \
        li    a0, 0;                                                    \
        nop;                                                            \
        ebreak

#define RVTEST_DATA_BEGIN                                               \
        .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END                                                 \
        .align 4; .global end_signature; end_signature:

#endif
