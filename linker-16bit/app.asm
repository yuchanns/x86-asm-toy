SECTION .bootloadersec
GLOBAL bootloader
USE16
bootloader:
	xor ax, ax
	mov ax, 0xb800
	mov ds, ax
	mov byte [0x7c0], 'H'
	mov byte [0x7c1], 0x04
	mov byte [0x7c2], 'E'
	mov byte [0x7c4], 'L'
	mov byte [0x7C6], 'L'
	mov byte [0x7C8], 'O'
	mov byte [0x7CA], ' '
	mov byte [0x7CC], ' '
	mov byte [0x7CE], 'Y'
	mov byte [0x7CF], 0x03
	mov byte [0x7D0], 'U'
	mov byte [0x7D2], 'C'
	mov byte [0x7D4], 'H'
	mov byte [0x7D6], 'A'
	mov byte [0x7D8], 'N'
	mov byte [0x7DA], 'N'
	mov byte [0x7DC], 'S'
hltloop:
	hlt
	jmp hltloop

