ENTRY(_start)

SECTIONS {
    . = 0x7c00;
    .bootloader :
    {
        *(.mbr)
        /* .kernel */
        _kernel_start_addr = .;
        *(.kernel)
        . = ALIGN(512);
        _kernel_end_addr = .;
    }
}
