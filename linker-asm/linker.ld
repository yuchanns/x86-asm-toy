ENTRY(_start)

SECTIONS {

    . = 0x7c00;
    .bootloader :
    {
        *(.mbr)
        /* .bootloader */
        _bootloader_start_addr = .;
        *(.bootloadersec)
        . = ALIGN(512);
        _bootloader_end_addr = .;
    }
}
