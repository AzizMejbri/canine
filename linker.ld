ENTRY(_start)

SECTIONS
{
    . = 1M;
    . = ALIGN(8);

    /* .multiboot : */
    /* { */
    /*     *(.multiboot) */
    /* } */

    __kernel_mem_start = .;

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

    . = ALIGN(4096);
    __kernel_mem_end = .;
}
