; 先以实模式加载本段程序, 然后再通过保护模式加载本段程序
; 保护模式需要定义 gdt, 描述代码段、数据段和栈段（特殊数据段）
section .mbr
global _start
[bits 16]
_start:
    mov ax, cs
    mov ss, ax
    ; 栈指针设置在本段程序被加载的位置，向低地址扩展
    ; 从 0x0000 到 0x7c00 之间还存在 IVT ，其数据可能被栈破坏
    mov sp, 0x7c00

clean_screen:
    mov ax, 0xb800
    mov es, ax
    mov si, 0x00 ; 循环清空屏幕
    .loop:
        mov byte [es:si], ' '
        ; 连续增加两次地址，跳过颜色位
        inc si
        ; 注意避免超出 vga 缓冲区的界限
        cmp si, 0x0ffff
        je .done
        inc si
        jmp .loop
    .done:

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
    ; 加上偏移地址(标号)就组成了 32 bit 下的物理地址
	; 注意因为 linker.ld 定义了地址为 0x7c00 
	; 所以标号 flush 要手动减掉 0x7c00
    jmp dword 0x0010:flush-0x7c00

    [bits 32] ; 指示编译器下面的代码编译成 32 bit 指令

flush:
    ; 引导程序别名数据段描述符索引为#3, 在 gdt 中, 特权级为 0
    ; 所以段选择子为 0000000000011_0_00 转为16进制的值为 0x0018
    mov eax, 0x0018
    mov ds, eax

    ; 加载#1描述符即数据段 4GB 的选择子
    mov eax, 0x0008
    mov es, eax
    mov fs, eax
    mov gs, eax

    ; 加载#4描述符堆栈选择子
    mov eax, 0x0020
    mov ss, eax
    xor esp, esp

    ; 在屏幕上显示文字，使用段选择子 es
    mov byte [es:0x0b8000+0x7c0], 'P'
    mov byte [es:0x0b8000+0x7c2], 'r'
    mov byte [es:0x0b8000+0x7c4], 'o'
    mov byte [es:0x0b8000+0x7c6], 't'
    mov byte [es:0x0b8000+0x7c8], 'e'
    mov byte [es:0x0b8000+0x7ca], 'c'
    mov byte [es:0x0b8000+0x7cc], 't'
    mov byte [es:0x0b8000+0x7ce], ' '
    mov byte [es:0x0b8000+0x7d0], 'm'
    mov byte [es:0x0b8000+0x7d2], 'o'
    mov byte [es:0x0b8000+0x7d4], 'd'
    mov byte [es:0x0b8000+0x7d6], 'e'
    mov byte [es:0x0b8000+0x7d8], ' '
    mov byte [es:0x0b8000+0x7da], 'O'
    mov byte [es:0x0b8000+0x7dc], 'K'
    mov byte [es:0x0b8000+0x7de], '.'

ghalt:
    hlt ; 中断被关闭，不会唤醒

    gdtinfo:
		dw gdt_end - gdt_start - 1
        dd gdt_start
	gdt_start:
		dq 0
	datadesc:
		dd 0x0000ffff
		dd 0x00cf9200
	codedesc:
		dd 0x7c0001ff
		dd 0x00409800
	aliascodedesc:
		dd 0x7c0001ff
		dd 0x00409200
	stackdesc:
		dd 0x00007a00
		dd 0x00409600
	gdt_end:
		 

    times 510-($-$$) db 0
	dw 0xaa55

