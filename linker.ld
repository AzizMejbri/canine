ENTRY(_start)

SECTIONS
{
    . = 1M;
    . = ALIGN(8);

    /* .multiboot : */
    /* { */
    /*     *(.multiboot) */
    /* } */

    .multiboot2 : ALIGN(8)
    {
        KEEP(*(.multiboot2))
    }


    .text :
    {
        *(.text*)
    }

    .rodata :
    {
        *(.rodata*)
    }

    .data :
    {
        *(.data*)
    }

    .bss :
    {
        *(.bss*)
    }
}
