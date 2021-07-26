ENTRY(_start)

SECTIONS {
    . = 0x7c00;
    .mbr :
    {
        *(.mbr)
    }
}
