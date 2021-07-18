; --------- 常量定义
    mem_seg_sel          equ 0x08 ; 内存段选择子 #1描述符
    kernel_stack_seg_sel equ 0x18 ; 内核栈段选择子 #3描述符
    video_ram_seg_sel    equ 0x20 ; VGA 缓冲区选择子 #4描述符
    sys_routine_seg_sel  equ 0x28 ; 系统例程选择子 #5描述符
    kernel_data_seg_sel  equ 0x30 ; 内核数据段选择子 #6描述符
    kernel_code_seg_sel  equ 0x38 ; 内核代码段选择子 #7描述符

    app_start_sector equ 10 ; 用户程序所在逻辑扇区

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

read_hard_disk_0:
    ; 入参
    ; eax = 逻辑扇区号
    ; ds:ebx = 目标缓冲区地址
    ; 返回
    ; ebx = ebx + 512
    push eax
    push ecx
    push edx

    push eax

    mov dx, 0x1f2
    mov al, 1
    out dx, al

    inc dx ; 0x1f3
    pop eax
    out dx, al

    inc dx ; 0x1f4
    mov cl, 8
    shr eax, cl
    out dx, al

    inc dx ; 0x1f5
    shr eax, cl
    out dx, al

    inc dx ; 0x1f6
    shr eax, cl
    or al, 0xe0

    out dx, al

    inc dx ; 0x1f7
    mov al, 0x20
    out dx, al
.waits:
    in al, dx
    and al, 0x88
    cmp al, 0x08
    jnz .waits

    mov ecx, 256
    mov dx, 0x1f0
.readw:
    in ax, dx
    mov [ebx], ax
    add ebx, 2
    loop .readw

    pop edx
    pop ecx
    pop eax

    retf ; 段间返回

allocate_memory: ; 分配内存
    ; 入参
    ; ecx = 请求分配 byte
    ; ecx = 起始线性地址
    push ds
    push eax
    push ebx

    mov eax, kernel_data_seg_sel
    mov ds, eax

    mov eax, [ram_alloc]
    add eax, ecx ; 计算出本次分配完毕后下次分配的起始地址
    ; todo: 检测可用内存数
    mov ecx, [ram_alloc] ; 本次分配起始地址

    ; 复制一份下次分配的起始地址
    mov ebx, eax
    ; 为了避免降低处理器速度，使用 cmovnz 代替判断和条件转移指令
    ; 能被 4 整除的数低 2 bit 为 0
    ; 1100 即 c
    ; 将程序大小的低 2 bit 抹去，使之对齐 4
    and ebx, 0xfffffffc
    ; 然后加上 4 凑整
    add ebx, 4
    ; 判断下次分配起始地址是否刚好能被 4 整除
    test eax, 0x00000003
    ; 如果 test结果不为0
    ; cmovnz 指令会将 ebx 赋值给 eax
    ; eax 保持原值
    cmovnz eax, ebx
    ; 回写下次分配起始地址
    mov [ram_alloc], eax

    pop ebx
    pop eax
    pop ds

    retf

set_up_gdt_descriptor:
    ; 安装新的描述符到 gdt
    ; 入参
    ; edx:eax = 描述符
    ; 返回
    ; cx = 段选择子
    push eax
    push ebx
    push edx

    push ds
    push es

    ; 使用内核数据段
    mov ebx, kernel_data_seg_sel
    mov ds, ebx
    ; sgdt 指令将 gdt 信息保存到 pgdt
    sgdt [pgdt]
    ; es 寄存器使用内存段选择子
    ; 后续用于更改 gdt
    mov ebx, mem_seg_sel
    mov es, ebx

    ; 取 gdt 界限
    ; movzx 指令带 0 扩展
    ; movzx r16, r/m8
    ; movzx r32, r/m8
    ; movzx r32, r/m8
    movzx ebx, word [pgdt]
    inc bx ; 下一个描述符偏移
    ; gdt 起始地址加偏移得到下一个描述符线性地址
    add ebx, [pgdt+2]

    ; 更新 gdt
    mov [es:ebx], eax
    mov [es:ebx+4], edx

    add word [pgdt], 8 ; gdt 增加一个描述符大小

    lgdt [pgdt] ; 重载 gdt

    ; 获取段选择子
    mov ax, [pgdt]
    xor dx, dx
    mov bx, 8
    div bx
    ; 弃余取商就是索引
    mov cx, ax
    ; 段选择子长度为 16 bit, 组成如下：
    ; 13 bit gdt 段描述索引_1 bit 指示器_2 bit 特权级
    ; 0000000000000      _0          _00
    ; 指示器 0-GDT, 1-LDT
    ; 因此这里直接左移 3 bit 得到段选择子
    shl cx, 3

    pop es
    pop ds

    pop edx
    pop ebx
    pop eax

    retf

make_seg_descriptor:
    ; 该过程动态生成 gdt 描述符
    ; 入参
    ; eax 段基地址
    ; ebx 段界限
    ; ecx 段属性
    ; 返回 edx:eax

    ; 把基地址移动到 edx 作备份
    mov edx, eax
    ; 低 32 bit 描述符中，高 16 bit 是基地址的低 16 bit
    ; 所以基地址左移16位
    shl eax, 16
    ; 低 16 bit 是段界限的低 16 bit
    ; 所以将段界限低16 bit 拼接到 ax 上
    ; 于是构成了描述符低 32 bit
    or ax, bx
    ; 清除基地址低 16 bit
    and edx, 0xffff0000
    ; rol 指令 让 edx 高 16 bit 分散到 edx 两端
    ; 其中低 8 bit 移动到 edx 的左端
    ; 高 8 bit 移动到 edx 的右端
    rol edx, 8
    ; bswap 指令让两端的字节互换
    bswap edx
    ; 因为段界限总共只用到了 ebx 20 bit ，所以需要清除低 16 bit 以及高 12 bit
    and ebx, 0x000f0000
    ; 然后拼接到 edx 的对应位置
    or edx, ebx
    ; 然后把段属性拼接到对应位置
    or edx, ecx

    retf ; 段间返回

SECTION kernel_data vstart=0
    pgdt dw 0 ; 用于设置和修改 gdt
         dd 0

    ram_alloc dd 0x00100000 ; 内存分配起始地址，默认从 0x00100000 开始

symbol_address_lookup_table:
    ; 符号地址检索表格式
    ; 256 byte 描述例程名称
    ; 4 byte 入口地址
    ; 2 byte 段选择子
    ; 表项长度固定为 256 + 4 + 2 = 262
    salt_print_string db '@PrintString'
        times 256-($-salt_print_string) db 0
        dd put_string
        dw sys_routine_seg_sel
    salt_read_disk_data db '@ReadDiskData'
        times 256-($-salt_read_disk_data) db 0
        dd read_hard_disk_0
        dw sys_routine_seg_sel
    salt_terminate_program db '@TerminateProgram'
        times 256-($-salt_terminate_program) db 0
        dd return_point
        dw kernel_code_seg_sel

    salt_item_len equ $-salt_terminate_program
    salt_items equ ($-symbol_address_lookup_table)/salt_item_len

    message_protect_mode_on db '  If you seen this message, that means we'
                            db 'are now in protect mode, and the system'
                            db 'core is loaded, and the video display'
                            db 'routine works perfectly.', 0x0d, 0x0a, 0

    message_load_app_start db '  Loading user program...', 0
    message_load_app_done  db 'Done.', 0x0d, 0x0a, 0

    message_app_terminated db 0x0d,  0x0a, 0x0d, 0x0a, 0x0d, 0x0a
                           db '  User program terminated, control returned', 0

    kernel_buf times 2048 db 0

    esp_pointer dd 0 ; 内核栈指针临时存放点

    cpu_brnd0 db 0x0d, 0x0a, '  ', 0
    cpu_brand times 52 db 0
    cpu_brnd1 db 0x0d, 0x0a, 0x0d, 0x0a, 0

SECTION kernel_code vstart=0
load_relocate_program:
    ; 入参
    ; esi = 用户程序所在硬盘扇区
    ; 返回
    ; ax = 用户头部程序段选择子
    push ebx
    push ecx
    push edx
    push esi
    push edi

    push ds
    push es

    mov eax, kernel_data_seg_sel
    mov ds, eax

    ; 读取用户程序第一扇内容加载到 kernel_buf 里
    mov eax, esi
    mov ebx, kernel_buf
    call sys_routine_seg_sel:read_hard_disk_0

    ; 判断程序大小
    mov eax, [kernel_buf] ; 0x00 保存了用户程序的大小
    mov ebx, eax ; 复制一份用户程序大小值
    ; 为了避免降低处理器速度，使用 cmovnz 代替判断和条件转移指令
    ; 能被 512 整除的数低 9 bit 都是 0
    ; 1110_0000_0000 即 e00
    ; 将程序大小的低 9 bit 抹去，使之对齐 512
    and ebx, 0xfffffe00
    ; 然后再加上 512 达到凑整的目的
    add ebx, 512
    ; 但这样存在一个问题如果程序大小刚好是能被 512 整除
    ; 上面的指令就会导致计算结果比实际多一个扇区
    ; 因此判断 eax 的低 9 bit 是否全为 0 即是否刚好被 512 整除
    test eax, 0x000001ff
    ; 如果 test结果不为0
    ; cmovnz 指令会将 ebx 赋值给 eax
    ; eax 保持原值
    cmovnz eax, ebx

    ; 申请内存用于加载程序
    mov ecx, eax
    call sys_routine_seg_sel:allocate_memory
    mov ebx, ecx
    push ebx ; 将申请到的内存起始地址保存到栈上

    ; eax / ecx 获取需要加载的扇区数量
    xor edx, edx
    mov ecx, 512
    div ecx
    mov ecx, eax

    ; 切换到内存段选择子方便访问整个 4g 内存
    mov eax, mem_seg_sel
    mov ds, eax
    ; 加载用户程序起始扇区号
    mov eax, esi
.b1:
    call sys_routine_seg_sel:read_hard_disk_0
    inc eax
    loop .b1 ; 循环直到读完 (exc 为 0)

    ; 将申请到的内存起始地址弹出到 edi 上
    pop edi

    ; 创建头部段描述符
    ; 获取用户程序头部段起始地址
    mov eax, edi
    ; 获取用户程序头部段长度
    mov ebx, [edi+0x04]
    ; 段界限为长度减去 1
    dec ebx
    ; 头部段的属性是
    ; 段粒度为 byte (G=0)
    ; 属于数据段(S=1)
    ; 是32 bit 的段(D=1)
    ; 位于内存中(P=1)
    ; 特权级别是0(DPL=00)
    ; 不能执行，向上扩展，看写入(TYPE=0010)
    ; 所以在高 32 bit 中除去基地址和界限以外的值为 0x00409200
    mov ecx, 0x00409200
    call sys_routine_seg_sel:make_seg_descriptor
    ; 重载 gdt 并生成段选择子
    call sys_routine_seg_sel:set_up_gdt_descriptor
    ; 头部段选择子回填到用户程序头部段
    mov [edi+0x04], cx

    ; 创建代码段描述符
    mov eax, edi
    ; 获取代码段起始地址
    add eax, [edi+0x14]
    ; 获取代码段长度
    mov ebx, [edi+0x18]
    ; 段界限为长度减去 1
    dec ebx
    ; 用户代码段的属性是
    ; 段粒度为 byte (G=0)
    ; 属于代码段(S=1)
    ; 是32 bit 的段(D=1)
    ; 位于内存中(P=1)
    ; 特权级别是0(DPL=00)
    ; 只能执行，不可从低级调用，不可被其他代码段读(TYPE=1000)
    ; 所以在高 32 bit 中除去基地址和界限以外的值为 0x00409800
    mov ecx, 0x00409800
    call sys_routine_seg_sel:make_seg_descriptor
    ; 重载 gdt 并生成段选择子
    call sys_routine_seg_sel:set_up_gdt_descriptor
    ; 代码段选择子回填到用户程序代码段
    mov [edi+0x14], cx

    ; 创建数据段描述符
    mov eax, edi
    ; 获取数据段起始地址
    add eax, [edi+0x1c]
    ; 获取数据段长度
    mov ebx, [edi+0x20]
    ; 段界限为长度减去 1
    dec ebx
    ; 不能执行，向上扩展，看写入(TYPE=0010)
    mov ecx, 0x00409200
    call sys_routine_seg_sel:make_seg_descriptor
    ; 重载 gdt 并生成段选择子
    call sys_routine_seg_sel:set_up_gdt_descriptor
    ; 数据段选择子回填到用户程序数据段
    mov [edi+0x1c], cx

    ; 创建堆栈段描述符
    ; 堆栈由内核动态分配
    ; 获取用户程序建议的堆栈段大小 4k 倍率
    add ecx, [edi+0x1c]
    ; 获取堆栈段长度
    mov ebx, 0x000fffff
    ; 得到段界限
    sub ebx, ecx
    ; 计算出堆栈的大小
    mov eax, 4096
    mul dword [edi+0x0c]
    mov ecx, eax
    ; 栈段的属性是
    ; 段粒度为 4kb (G=1)
    ; 属于数据段(S=1)
    ; 是32 bit 的段(D=1)
    ; 位于内存中(P=1)
    ; 特权级别是0(DPL=00)
    ; 不可执行，向下扩展，可写入(TYPE=0110)
    ; 所以在高 32 bit 中除去基地址和界限以外的值为 0x00c09600
    mov ecx, 0x00c09600
    call sys_routine_seg_sel:make_seg_descriptor
    ; 重载 gdt 并生成段选择子
    call sys_routine_seg_sel:set_up_gdt_descriptor
    ; 堆栈段选择子回填到用户程序堆栈段
    mov [edi+0x08], cx

    ; 重定位符号检索表
    ; 通过 es 使用头部段选择子
    mov eax, [edi+0x04]
    mov es, eax
    ; 通过 ds 使用内核数据段选择子
    mov eax, kernel_data_seg_sel
    mov ds, eax

    cld ; 清除标志位

    ; 三层循环
    ; 第一层循环用户程序符号检索表需要的例程名称
    ; 第二层循环内核符号检索表提供的例程名称
    ; 第三层逐双字循环对比两者名称是否相同
    ; 相同时写入内核例程入口地址和段选择子

    ; 获取符号检索表条数
    mov ecx, [es:0x24]
    ; edi 保存用户符号检索表起始地址
    mov edi, 0x28
.b2:
    push ecx
    push edi
    ; 获取内核数据段中的符号检索表条数
    mov ecx, salt_items
    ; esi 保存内核符号检索表起始地址
    mov esi, symbol_address_lookup_table
.b3:
    push edi
    push esi
    push ecx
    ; 每次比较双字，即 4 byte
    ; 所以 256 byte 的例程名称需要比较 256 / 4 = 64 次
    mov ecx, 64
    ; repe 指令当比较结果相同时继续比较，直到 ecx 为 0
    ; cmpsd 逐双字比较 edi 和 esi
    repe cmpsd
    jnz .b4 ; 不相同，立即停止第三层的循环比较
    ; 否则比较完毕，完全相同
    mov eax, [esi]
    ; 因为比较完 edi 已经递增到用户当前例程地址结尾
    ; 所以需要减去 256 回到起始地址
    ; 而 eax 此时正好指向了匹配的内核例程的入口地址
    ; 将匹配的内核例程入口地址替换到用户当前例程地址开头
    mov [es:edi-256], eax
    ; 然后再把匹配的内核例程的选择子写到用户当前例程地址开头偏移 4 byte 位置
    mov ax, [esi+4]
    mov [es:edi-252], ax
.b4:
    pop ecx
    pop esi
    ; 跳到下一个内核例程项，进行新的第三层对比
    add esi, salt_item_len
    pop edi
    loop .b3

    ; 跳到下一个用户例程项，进行新的第二层对比
    ; 因此需要重制用户例程项
    pop edi
    ; 然后加 256 跳到下一个用户例程项
    add edi, 256
    pop ecx
    loop .b2

    ; 返回用户程序头部段选择子
    mov ax, [es:0x04]

    pop es
    pop ds

    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx

    ret ; 段内调用

start:
    ; 指向内核数据段
    mov ecx, kernel_data_seg_sel
    mov ds, ecx
    ; 调用例程打印提示信息
    mov ebx, message_protect_mode_on
    call sys_routine_seg_sel:put_string

    ; 打印处理器信息
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
    call sys_routine_seg_sel:put_string
    mov ebx, cpu_brand
    call sys_routine_seg_sel:put_string
    mov ebx, cpu_brnd1
    call sys_routine_seg_sel:put_string

    ; 加载用户程序，完毕后提示
    mov ebx, message_load_app_start
    call sys_routine_seg_sel:put_string

    mov esi, app_start_sector
    call load_relocate_program

    mov ebx, message_load_app_done
    call sys_routine_seg_sel:put_string

    mov [esp_pointer], esp ; 保存内核堆栈指针
    ; 使用用户程序头部段选择子
    mov ds, ax

    jmp far [0x10] ; 跳转到用户程序入口

return_point:
    ; 用户程序返回内核
    ; 数据段恢复为内核数据段
    mov eax, kernel_data_seg_sel
    mov ds, eax
    ; 恢复内核栈指针
    mov esp, [esp_pointer]
    ; 打印返回内核提示
    mov ebx, message_app_terminated
    call sys_routine_seg_sel:put_string

    hlt

SECTION kernel_trail
kernel_end:
