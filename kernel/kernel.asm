; --------- 常量定义
    mem_seg_sel          equ 0x08 ; 内存段选择子 #1描述符
    kernel_stack_seg_sel equ 0x18 ; 内核栈段选择子 #3描述符
    video_ram_seg_sel    equ 0x20 ; VGA 缓冲区选择子 #4描述符
    sys_routine_seg_sel  equ 0x28 ; 系统例程选择子 #5描述符
    kernel_data_seg_sel  equ 0x30 ; 内核数据段选择子 #6描述符
    kernel_code_seg_sel  equ 0x38 ; 内核代码段选择子 #7描述符

; --------- header 用于在创建内核描述符时定位每个段的长度
    dd kernel_end ; 内核总长度 0x00
    dd section.sys_routine.start ; 系统例程 0x04
    dd section.kernel_data.start ; 内核数据段 0x08
    dd section.kernel_code.start ; 内核代码段 0x0c

    dd start ; 内核代码段入口偏移值 0x10
    dw kernel_code_seg_sel ; 内核代码段选择子（对应 16 bit 下的绝对物理地址） 0x14

    [bits 32]
SECTION sys_routine vstart=0
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
    retf ; 可以被跨段调用，所以需要使用远返回
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
    mov eax, video_ram_seg_sel ; vga 段选择子
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
    mov eax, video_ram_seg_sel
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

SECTION kernel_data vstart=0
    message_1 db '  If you seen this message, that means we'
              db ' are now in protect mode, and the system'
              db ' core is loaded, and the video display'
              db ' routine works perfectly.', 0x0d, 0x0a, 0

SECTION kernel_code vstart=0
start:
    ; 指向内核数据段
    mov ecx, kernel_data_seg_sel
    mov ds, ecx
    ; 调用例程打印
    mov ebx, message_1
    call sys_routine_seg_sel:put_string

    hlt

SECTION kernel_trail
kernel_end:
