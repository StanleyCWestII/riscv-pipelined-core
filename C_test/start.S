.section .text.start
.globl _start
.type _start, @function

_start:
    # Data memory occupies byte addresses 0x00000000 through 0x0000ffff.
    # The first stack access decrements sp, so 0x00010000 itself is not accessed.
    lui sp, 0x10

    # Zero the C .bss section for uninitialized global/static variables.
    la t0, __bss_start
    la t1, __bss_end
1:
    bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b

2:
    call main

    # Keep ebreak out of Decode while the call's jalr is still in Execute.
    # This core's trap stall otherwise squashes that immediately preceding jump.
    nop

    # main's return value is now in a0. The testbench recognizes ebreak as
    # program completion and checks a0.
    ebreak

    # A delayed sequential fetch can still arrive after the call redirects.
    # Keep that slot harmless instead of placing the parking jump there.
    nop
3:
    j 3b

.size _start, .-_start
