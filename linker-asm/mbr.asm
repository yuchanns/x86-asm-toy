SECTION .mbr
USE16
GLOBAL _start

extern _bootloader_start_addr
extern _bootloader_end_addr
extern bootloader

_start:
	xor ax, ax
	mov ds, ax
	mov es, ax
	mov ss, ax
	mov fs, ax
	mov gs, ax

	cld

	mov sp, 0x7c00

load_bootloader_from_disk:
	lea eax, _bootloader_start_addr
	mov ebx, eax
	shr ebx, 4
	mov [dap_buffer_seg], bx

	shl ebx, 4
	sub eax, ebx
	mov [dap_buffer_addr], ax

	lea eax, _bootloader_start_addr
	lea ebx, _bootloader_end_addr
	sub ebx, eax
	shr ebx, 9
	mov [dap_blocks], bx

	lea ebx, _start
	sub eax, ebx
	shr eax, 9
	mov [dap_start_lba], eax

	lea si, dap
	mov ah, 0x42
	int 0x13
	
	mov word [dap_buffer_seg], 0

	lea eax, [bootloader]
	jmp eax

dap:
	db 0x10
	db 0
dap_blocks:
	dw 0
dap_buffer_addr:
	dw 0
dap_buffer_seg:
	dw 0
dap_start_lba:
	dq 0

times 510 - ($-$$) db 0
dw 0xaa55

