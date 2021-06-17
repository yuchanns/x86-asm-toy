SECTION header vstart=0
    dd program_end ; 记录程序长度

    dw start ; 程序入口的相对偏移
    dd section.code.start ; 程序入口的绝对偏移
    dw (header_end-code_segment)/4 ; 段重定位表长度

    code_segment dd section.code.start ; 记录代码段位置
    data_segment dd section.data.start ; 记录数据段位置
    stack_segment dd section.stack.start ; 记录栈位置

header_end:

;---------------- code section -------------
SECTION code align=16 vstart=0

clean_screen:
    mov cl, 25 ; 设置循环25次，充满80x25的屏幕
    @loop: ; 循环点
        call print_line
    loop @loop
    ret
print_line:
    mov al, 13 ; 对应 ASCII 表上的 \r
    call print_char
    mov al, 10 ; 对应 ASCII 表上的 \n
    jmp print_char
print:
    pushf ; 将状态寄存器的数据压入栈，因为接下来的操作会覆盖上下文的状态寄存器的值，需要保存，使用完之后进行恢复
    cld ; 清零方向标志位，为后面递增地址读取 si 寄存器的内容做准备
.loop:
    lodsb ; 读取 si 寄存器保存的地址指向的字节内容到 al 寄存器，并把 si 寄存器保存的地址移动一位
    cmp al, 0 ; 对比 al 寄存器和0是否一致
    je .done ; 如果一致，说明打印结束，跳转到结束标号
    cmp al, 0x0a ; 对比 al 寄存器和 0x0a 是否一致
    jne .continue ; 不一致则进行打印
    call print_line ; 否则打印换行
    jmp .loop
.continue:
    call print_char ; 进行打印 al 寄存器的内容
    jmp .loop ; 循环读取 si 寄存器保存的地址指向的内容
.done:
    popf ; 将压入栈的状态值恢复到状态寄存器里
    ret ; 返回

print_char:
    pusha ; 将通用寄存器的值全部压入栈中，保存上下文，避免下面的覆盖使用造成丢失
    mov bx, 7 ; 闪烁终端窗口，对应 ASCII 中的 BEL
    mov ah, 0x0e ; 使用 teletype 模式
    int 0x10 ; 使用中断打印 al 寄存器中的内容
    popa ; 恢复通用寄存器的上下文
    ret

start:
    mov ax, [stack_segment]
    mov ss, ax
    mov sp, stack_end

    mov ax, [data_segment]
    mov ds, ax

    mov ax, [es:code_segment]
    push ax
    push word .greet
    retf

.greet:
    call clean_screen
    mov si, msg
    call print
    call print_line
.hlt_loop: ; 避免 cpu 空转
    hlt
    jmp .hlt_loop

;---------------- data section -------------
SECTION data align=16 vstart=0
    msg db ' Hello World!', 0x0a
        db ' Successfully Read Data from Hard Disk!', 0x0a
        db ' Example Code in NASM:', 0x0a
        db '    SECTION .text vstart=0x7c00', 0x0a
        db '        xor ax, ax', 0x0a
        db '        mov ds, ax', 0x0a
        db '        mov es, ax', 0x0a
        db '        mov ss, ax', 0x0a, 0x0a
        db '        mov sp, 0x7c00', 0x0a, 0x0a
        db '        mov si, msg', 0x0a
        db '        call print', 0x0a
        db '        call print_line', 0x0a, 0x0a
        db '        %include "print.s"', 0x0a, 0x0a
        db '        msg: db "Hello Yuchanns!", 0', 0x0a, 0x0a
        db '        times 510 - ($-$$) db 0', 0x0a
        db '                           dw 0xaa55', 0x0a, 0x0a
        db ' Written by yuchanns at 2021-06-17 23:53:00.', 0

;---------------- stack section -------------
SECTION stack align=16 vstart=0
    resb 256
stack_end:

SECTION trail align=16
program_end: