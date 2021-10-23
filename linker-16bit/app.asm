SECTION .bootloadersec
GLOBAL bootloader
extern _memory_map
USE16
do_e820:
    lea di, [_memory_map]
    xor ebx, ebx
    xor bp, bp
    mov edx, 0x0534D4150
    mov eax, 0xe820
    mov [es:di + 20], dword 1
    mov ecx, 24
    int 0x15
    jc short .failed
    mov edx, 0x0534D4150
    cmp eax, edx
    jne short .failed
    test ebx, ebx
    je short .failed
    jmp short .jmpin
.e820lp:
    mov eax, 0xe820
    mov [es:di + 20], dword 1
    mov ecx, 24
    int 0x15
    jc short .e820f
    mov edx, 0x0534D4150
.jmpin:
    jcxz .skipent
    cmp cl, 20
    jbe short .notext
    test byte [es:di + 20], 1
    je short .skipent
.notext:
    mov ecx, [es:di + 8]
    or ecx, [es:di + 12]
    jz .skipent
    inc bp
    add di, 24
.skipent:
    test ebx, ebx
    jne short .e820lp
.e820f:
    mov [mmap_ent], bp
    clc
    ret
.failed:
    stc
    ret
mmap_ent: dw 0
bootloader:
	xor ax, ax
	mov ax, 0xb800
	mov ds, ax
    call do_e820
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

