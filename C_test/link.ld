OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    DMEM (rw)  : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        KEEP(*(.text.start))
        *(.text.startup*)
        *(.text*)
    } > IMEM

    .data : AT(0x00010000)
    {
        *(.rodata*)
        *(.srodata*)
        *(.data*)
        *(.sdata*)
    } > DMEM

    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > DMEM

    /DISCARD/ :
    {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.riscv.attributes)
    }

    __stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
}

ASSERT(SIZEOF(.text) <= LENGTH(IMEM), "program does not fit in InstrMem")
ASSERT((ADDR(.bss) + SIZEOF(.bss)) <= (ORIGIN(DMEM) + LENGTH(DMEM)),
       "program data does not fit in DataMem")
