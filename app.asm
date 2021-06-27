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

int_handler_70H:
    pusha
    push es

    mov al, 0x80
    out 0x70, al
    in al, 0x71 ; 读秒
    push ax

    mov al, 0x82
    out 0x70, al
    in al, 0x71 ; 读分
    push ax

    mov al, 0x84
    out 0x70, al
    in al, 0x71 ; 读时
    push ax

    mov al, 0x0c
    out 0x70, al
    in al, 0x71 ; 清空 RTC 寄存器 C 复位

    mov ax, 0xb800
    mov es, ax ; 准备写显存
    mov bx, 12*160 + 36*2 ; 从第12行36列开始

    pop ax ; 弹出时
    call bcd_to_ascii
    mov [es:bx], ah
    mov [es:bx+2], al
    mov byte [es:bx+4], ':'
    not byte [es:bx+5] ; 反色

    pop ax ; 弹出分
    call bcd_to_ascii
    mov [es:bx+6], ah
    mov [es:bx+8], al
    mov byte [es:bx+10], ':'
    not byte [es:bx+11] ; 反色

    pop ax ; 弹出秒
    call bcd_to_ascii
    mov [es:bx+12], ah
    mov [es:bx+14], al

    mov al, 0x20 ; 发送中断结束
    out 0xa0, al ; 从片
    out 0x20, al ; 主片

    pop es
    popa

    iret

bcd_to_ascii:
    mov ah, al
    and al, 0x0f
    add al, 0x30

    shr ah, 4
    and ah, 0x0f
    add ah, 0x30

    ret

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
    mov si, init_msg
    call print

.install_interrupt:
    mov si, inst_msg
    call print
    mov al, 0x70
    mov bl, 4
    mul bl
    mov bx, ax ; 计算中断默认地址 0x70 在 IVT 的偏移

    cli ; 关中断

    push es
    mov ax, 0x0000 ; IVT 的地址
    mov es, ax
    mov word [es:bx], int_handler_70H ; 写入0x70中断处理器的偏移地址
    mov word [es:bx+2], cs ; 写入0x70中断处理器的段地址
    pop es

    mov al, 0x8b
    out 0x70, al ; 访问 RTC 寄存器 B 阻断 NMI
    mov al, 0x12
    out 0x71, al ; 禁止周期中断，允许更新结束后中断，BCD 码，24小时

    mov al, 0x0c
    out 0x70, al
    in al, 0x71 ; 读取 RTC 寄存器 C 进行复位

    in al, 0xa1 ; 读取 IMR 从片
    and al, 0xfe ; 遮蔽从片其他中断，只允许时间中断 11111110
    out 0xa1, al

    sti ; 开中断

    mov si, done_msg
    call print

    mov si, tips_msg
    call print

.hlt_loop: ; 避免 cpu 空转
    hlt
    jmp .hlt_loop

;---------------- data section -------------
SECTION data align=16 vstart=0
    init_msg db ' Hello World!', 0x0a
             db ' Successfully Read Data from Hard Disk!', 0x0a, 0x0a, 0
    inst_msg db ' Installing a interrupt handler 70H...', 0x0a, 0
    done_msg db ' Done.', 0x0a, 0x0a, 0
    tips_msg db ' Clock is now working.', 0

;---------------- stack section -------------
SECTION stack align=16 vstart=0
    resb 256
stack_end:

SECTION trail align=16
program_end:
