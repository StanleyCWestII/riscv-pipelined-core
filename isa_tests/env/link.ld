/* Harvard layout matching pipelined.sv: InstrMem and DataMem both start at
   byte address 0 and are 64 KiB each. Bit 16 of a data address selects the
   memory-mapped peripherals, so nothing in .data may cross 0x10000. */
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
        KEEP(*(.text.init))
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
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
    } > DMEM

    /DISCARD/ :
    {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.riscv.attributes)
    }
}

ASSERT(SIZEOF(.text) <= LENGTH(IMEM), "test does not fit in InstrMem")
ASSERT((ADDR(.bss) + SIZEOF(.bss)) <= (ORIGIN(DMEM) + LENGTH(DMEM)),
       "test data does not fit in DataMem")
