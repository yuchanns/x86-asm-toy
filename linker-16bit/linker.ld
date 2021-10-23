ENTRY(_start)

SECTIONS {
    . = 0x500;
    _memory_map = .;
    . += 0x1000;
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
