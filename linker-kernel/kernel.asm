section .kernel
[bits 32]
global _kernel_start
global vga_desc_sel
global code_desc_sel
global data_desc_sel
global stack_desc_sel

; -- data --
	msg_protect_mode_on: db '  If you seen this message, that means we'
						 db ' are now in protect mode, and the system'
						 db ' kernel is loaded, and the video display'
						 db ' routine works perfectly', 0x0d, 0x0a, 0
	cpu_brnd0 db 0x0d, 0x0a, '  ', 0
	cpu_brand times 52 db 0
	cpu_brnd1 db 0x0d, 0x0a, 0x0d, 0x0a, 0
	
; -- segment selector --	
	code_desc_sel:   dw 0
	data_desc_sel:   dw 0
	vga_desc_sel:    dw 0
	stack_desc_sel:  dw 0
	
; -- routine --
put_string:
	push ecx
.getc:
    mov cl, [ebx] ; 使用 ebx 装载字符串
    or cl, cl ; 末尾为0结束打印
    jz .exit
    call put_char
    inc ebx
    jmp .getc
.exit:
    pop ecx
    ret
put_char:
    ; 光标处显示字符，并推进光标
    pushad
    ; 取光标位置
    mov dx, 0x3d4
    mov al, 0x0e
    out dx, al
    inc dx
    in al, dx
    mov ah, al

    dec dx
    mov al, 0x0f
    out dx, al
    inc dx
    in al, dx
    mov bx, ax

    cmp cl, 0x0d ; 判断是否为回车符
    jnz .put_0a
    mov ax, bx
    mov bl, 80
    div bl
    mul bl
    mov bx, ax
    jmp .set_cursor
.put_0a:
    cmp cl, 0x0a ; 判断是否为换行符
    jnz .put_other
    add bx, 80 ; 增加一行
    jmp .roll_screen
.put_other:
    push es
    mov eax, [vga_desc_sel] ; vga 段选择子
    mov es, eax
    shl bx, 1
    mov [es:bx], cl
    pop es
    ; 在光标位置推进
    shr bx, 1
    inc bx
.roll_screen:
    cmp bx, 2000 ; 判断光标是否超出屏幕，是则需要滚屏
    jl .set_cursor ; jump less than 2000

    push ds
    push es
    mov eax, [vga_desc_sel]
    mov ds, eax
    mov es, eax
    cld
    ; 从 esi 传输双字数据到 edi
    mov esi, 0xa0
    mov edi, 0x00
    mov ecx, 1920
    rep movsd ; 重复执行直到 ecx 为 0
    mov bx, 3840
    mov ecx, 80
.cls:
    mov word [es:bx], 0x0720
    add bx, 2
    loop .cls

    pop es
    pop ds

    mov bx, 1920
.set_cursor:
    mov dx, 0x3d4
    mov al, 0x0e
    out dx, al
    inc dx
    mov al, bh
    out dx, al
    dec dx
    mov al, 0x0f
    out dx, al
    inc dx
    mov al, bl
    out dx, al

    popad
    ret ; 仅限段内调用
_kernel_start:
	mov eax, [data_desc_sel]
	mov ds, eax
	mov es, eax
	mov fs, eax
	mov gs, eax

	mov eax, [stack_desc_sel]
	mov ss, eax
	xor esp, esp

	mov ebx, msg_protect_mode_on
	call put_string

	; cpu info
	mov eax, 0x80000002
	cpuid
	mov [cpu_brand + 0x00], eax
	mov [cpu_brand + 0x04], ebx
	mov [cpu_brand + 0x08], ecx
    mov [cpu_brand + 0x0c], edx
    mov eax, 0x80000003
    cpuid
    mov [cpu_brand + 0x10], eax
    mov [cpu_brand + 0x14], ebx
    mov [cpu_brand + 0x18], ecx
    mov [cpu_brand + 0x1c], edx
    mov eax, 0x80000004
    cpuid
    mov [cpu_brand + 0x20], eax
    mov [cpu_brand + 0x24], ebx
    mov [cpu_brand + 0x28], ecx
    mov [cpu_brand + 0x2c], edx
	mov ebx, cpu_brnd0
	call put_string
	mov ebx, cpu_brand
	call put_string
	mov ebx, cpu_brnd1
	call put_string

ghalt:
	hlt

