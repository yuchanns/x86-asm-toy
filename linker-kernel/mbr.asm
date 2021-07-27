; 先以实模式加载本段程序, 然后再通过保护模式加载本段程序
; 保护模式需要定义 gdt, 描述代码段、数据段和栈段（特殊数据段）
section .mbr
global _start
extern _kernel_start_addr
extern _kernel_end_addr
extern _kernel_start
extern code_desc_sel
extern data_desc_sel
extern vga_desc_sel
extern stack_desc_sel
[bits 16]
_start:
    mov ax, cs
    mov ss, ax
    ; 栈指针设置在本段程序被加载的位置，向低地址扩展
    ; 从 0x0000 到 0x7c00 之间还存在 IVT ，其数据可能被栈破坏
    mov sp, 0x7c00

load_kernel_from_disk:
    lea eax, _kernel_start_addr
    mov ebx, eax
    shr ebx, 4
    mov [dap_buffer_seg], bx

    shl ebx, 4
    sub eax, ebx
    mov [dap_buffer_addr], ax

    lea eax, _kernel_start_addr
    lea ebx, _kernel_end_addr
    sub ebx, eax
    shr ebx, 9
    mov [dap_blocks], bx

    lea ebx, _start
    sub eax, ebx
    shr eax, 9 ; 512
    mov [dap_start_lba], eax

    ; int32 42h
    lea si, dap
    mov ah, 0x42
    int 0x13

    mov word [dap_buffer_seg], 0
	

    lgdt [cs:gdtinfo]

    ; A20 Line 默认是关闭的，需要通过 Fast A20 手动打开
    ; 对应的端口是 0x92 , 读取原数据后将第二位改成1再写回
    in al, 0x92
    or al, 0000_0010B
    out 0x92, al

    cli ; 关中断，因为进入保护模式需要重建中断处理机制

    ; cr0 中 32 bit 数据的第1位是 PE 位, 决定是否开启保护模式
    ; 设置为 1 开启保护模式
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; 进入保护模式之后，前缀不再是逻辑地址，而是段选择子
    ; 段选择子长度为 16 bit, 组成如下：
    ; 13 bit gdt 段描述索引_1 bit 指示器_2 bit 特权级
    ; 0000000000000      _0          _00
    ; 指示器 0-GDT, 1-LDT
    ; 同时可以通过 jmp 指令快速清空段选择器和高速缓存器中的内容
    ; 代码段描述符索引为#2, 在 gdt 中, 特权级为 0
    ; 所以段选择子为 0000000000010_0_00 转为16进制的值为 0x0010
    jmp dword 0x0010:flush

    [bits 32] ; 指示编译器下面的代码编译成 32 bit 指令

flush:
    ; 加载#1描述符即数据段 4GB 的选择子
    mov eax, 0x0008
	mov ds, eax
    mov es, eax
    mov fs, eax
    mov gs, eax
	mov word [data_desc_sel], ax

	; 加载#2描述符即代码段的选择子
	mov eax, 0x0010
	mov word [code_desc_sel], ax

    ; 加载#3描述符堆栈选择子
    mov eax, 0x0018
    mov ss, eax
	mov word [stack_desc_sel], ax
    xor esp, esp

	; 填充#4 vga 选择子
	mov word [vga_desc_sel], 0x0020

	jmp dword 0x0010:_kernel_start

gdtinfo:
	dw gdt_end - gdt_start - 1
	dd gdt_start
gdt_start:
	dq 0
datadesc:
	dd 0x0000ffff
	dd 0x00cf9200
codedesc:
	dd 0x0000ffff
	dd 0x00cf9a00
stackdesc:
	dd 0x7c00fffe
	dd 0x00cf9600
vgadesc:
	dd 0x80007fff
	dd 0x0040920b
gdt_end:

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

times 510-($-$$) db 0
dw 0xaa55

