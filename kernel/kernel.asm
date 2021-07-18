; --------- 常量定义
    mem_seg_sel          equ 0x08 ; 内存段选择子 #1描述符
    kernel_stack_seg_sel equ 0x18 ; 内核栈段选择子 #3描述符
    video_ram_seg_sel    equ 0x20 ; VGA 缓冲区选择子 #4描述符
    sys_routine_seg_sel  equ 0x28 ; 系统例程选择子 #5描述符
    kernel_data_seg_sel  equ 0x30 ; 内核数据段选择子 #6描述符
    kernel_code_seg_sel  equ 0x38 ; 内核代码段选择子 #7描述符

    app_start_sector equ 20 ; 用户程序所在逻辑扇区
    tcb_size equ 0x46 ; 任务控制块大小
    ldt_size equ 160 ; ldt 描述符
    tss_size equ 104

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

make_gate_descriptor:
    ; 构造门的描述符
    ; 入参
    ; eax = 门段内偏移地址
    ; bx = 门的段选择子
    ; cx = 门属性
    ; 返回
    ; edx:eax = 门描述符
    push ebx
    push ecx

    mov edx, eax
    ; 门描述符的高 32 bit 是 高 16 bit 偏移地址 + 低 16 bit 门属性
    and edx, 0xffff0000 ; 获取高 16 bit 的偏移地址
    or dx, cx ; 将门属性拼到低 16 bit

    and eax, 0x0000ffff ; 获取低 16 bit 的偏移地址
    ; 门描述符的低 32 bit 是 高 16 bit 段选择子 + 低 16 bit 的偏移地址
    ; 所以左移16次将段选择子放到高 16 bit
    shl ebx, 16
    ; 将段选择子拼到高 16 bit
    or eax, ebx

    pop ecx
    pop ebx

    retf

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

    message_call_gate_mount db '  System wide CALL-GATE mounted', 0x0d, 0x0a, 0

    message_load_app_start db '  Loading user program...', 0
    message_load_app_done  db 'Done.', 0x0d, 0x0a, 0

    message_app_terminated db 0x0d,  0x0a, 0x0d, 0x0a, 0x0d, 0x0a
                           db '  User program terminated, control returned', 0

    kernel_buf times 2048 db 0

    esp_pointer dd 0 ; 内核栈指针临时存放点

    cpu_brnd0 db 0x0d, 0x0a, '  ', 0
    cpu_brand times 52 db 0
    cpu_brnd1 db 0x0d, 0x0a, 0x0d, 0x0a, 0

    ; 任务控制块链表
    ; todo 注释 tcb 结构
    tcb_chain dd 0

SECTION kernel_code vstart=0
fill_descriptor_in_ldt:
    ; 安装描述符到 ldt
    ; 入参
    ; edx:eax = 描述符
    ; ebx = tcb 基地址
    ; 返回
    ; cx = 描述符的段选择子
    push eax
    push edx
    push edi
    push ds

    mov ecx, mem_seg_sel
    mov ds, ecx

    ; 获取 tcb 中 ldt 的基地址
    mov edi, [ebx+0x0c]
    xor ecx, ecx
    ; 获取 tcb 中 ldt 的界限
    mov cx, [ebx+0x0a]
    inc cx ; 获取 ldt 中新的描述符偏移地址
    ; 在界限边缘往后安装新的描述符
    mov [edi+ecx+0x00], eax
    mov [edi+ecx+0x04], edx
    ; 获取新的界限值
    add cx, 8
    dec cx
    ; 更新 tcb 上 ldt 界限值
    mov [ebx+0x0a], cx
    ; 获取当前描述符的索引号
    mov ax, cx
    xor dx, dx
    mov cx, 8
    div cx
    ; 将索引号左移 3 次
    mov cx, ax
    shl cx, 3
    ; 拼接成段选择子
    ; 描述符在 ldt 中，所以 ti 为 1
    ; 特权级默认为 0
    or cx, 0000_0000_0000_0100B

    pop ds
    pop edi
    pop edx
    pop eax

    ret
load_relocate_program:
    ; 入参
    ; 栈 push 逻辑扇区号
    ; 栈 push tcb 基地址
    pushad

    push ds
    push es

    mov ebp, esp

    mov ecx, mem_seg_sel
    mov es, ecx
    ; 从栈中取参数 tcb 基地址
    ; 不是通过 pop 取，而是计算刚才压入的参数长度，偏移取
    mov esi, [ebp+11*4]
    ; 申请 ldt 内存
    mov ecx, ldt_size
    call sys_routine_seg_sel:allocate_memory
    ; ldt 起始基地址记录到 tcb 中
    mov [es:esi+0x0c], ecx
    ; ldt 初始界限记录到 tcb 中
    mov word [es:esi+0x0a], 0xffff

    ; 加载用户程序
    mov eax, kernel_data_seg_sel
    mov ds, eax
    ; 读取用户程序第一扇内容加载到 kernel_buf 里
    mov eax, [ebp+12*4]
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
    ; 程序加载的基地址记录到 tcb 中
    mov [es:esi+0x06], ecx

    mov ebx, ecx
    ; eax / ecx 获取需要加载的扇区数量
    xor edx, edx
    mov ecx, 512
    div ecx
    mov ecx, eax

    ; 切换到内存段选择子方便访问整个 4g 内存
    mov eax, mem_seg_sel
    mov ds, eax
    ; 加载用户程序起始扇区号
    mov eax, [ebp+12*4]
.b1:
    call sys_routine_seg_sel:read_hard_disk_0
    inc eax
    loop .b1 ; 循环直到读完 (exc 为 0)

    ; 获取申请到的程序加载内存起始地址
    mov edi, [es:esi+0x06]

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
    ; 特权级别是3(DPL=11)
    ; 不能执行，向上扩展，可写入(TYPE=0010)
    ; 所以在高 32 bit 中除去基地址和界限以外的值为 0x0040f200
    mov ecx, 0x0040f200
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx, esi
    ; 生成段选择子载入到 ldt 中
    call fill_descriptor_in_ldt
    ; 设置选择子的特权级为 3
    or cx, 0000_0000_0000_0011B
    ; 头部段选择子记录到 tcb 中
    mov [es:esi+0x44], cx
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
    ; 特权级别是3(DPL=11)
    ; 只能执行，不可从低级调用，不可被其他代码段读(TYPE=1000)
    ; 所以在高 32 bit 中除去基地址和界限以外的值为 0x0040f800
    mov ecx, 0x0040f800
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx, esi
    ; 生成段选择子载入到 ldt 中
    call fill_descriptor_in_ldt
    ; 设置选择子的特权级为 3
    or cx, 0000_0000_0000_0011B
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
    ; 特权级别是3(DPL=11)
    ; 不能执行，向上扩展，可写入(TYPE=0010)
    mov ecx, 0x0040f200
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx, esi
    ; 生成段选择子载入到 ldt 中
    call fill_descriptor_in_ldt
    ; 设置选择子的特权级为 3
    or cx, 0000_0000_0000_0011B
    ; 数据段选择子回填到用户程序数据段
    mov [edi+0x1c], cx

    ; 创建堆栈段描述符
    ; 堆栈由内核动态分配
    ; 获取用户程序建议的堆栈段大小 4k 倍率
    add ecx, [edi+0x0c]
    ; 获取堆栈段长度
    mov ebx, 0x000fffff
    ; 得到段界限
    sub ebx, ecx
    ; 计算出堆栈的大小
    mov eax, 4096
    mul ecx
    mov ecx, eax
    call sys_routine_seg_sel:allocate_memory
    ; 获得堆栈的高端物理地址
    add eax, ecx
    ; 栈段的属性是
    ; 段粒度为 4kb (G=1)
    ; 属于数据段(S=1)
    ; 是32 bit 的段(D=1)
    ; 位于内存中(P=1)
    ; 特权级别是3(DPL=11)
    ; 不可执行，向下扩展，可写入(TYPE=0110)
    ; 所以在高 32 bit 中除去基地址和界限以外的值为 0x00c0f600
    mov ecx, 0x00c0f600
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx, esi
    ; 生成段选择子载入到 ldt 中
    call fill_descriptor_in_ldt
    ; 设置选择子的特权级为 3
    or cx, 0000_0000_0000_0011B
    ; 堆栈段选择子回填到用户程序堆栈段
    mov [edi+0x08], cx

    ; 重定位符号检索表
    ; 头部段未生效，只能通过内存段选择子来访问用户程序头部
    mov eax, mem_seg_sel
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
    mov ecx, [es:edi+0x24]
    ; 偏移地址
    add edi, 0x28
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
    ; 门选择子设置为 3 级特权
    or ax, 0000_0000_0000_0011B
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

    ; 从堆栈中取得 tcb 的基地址
    mov esi, [ebp+11*4]

    ; 创建 0 特权级堆栈
    mov ecx, 4096
    mov eax, ecx
    mov [es:esi+0x1a], ecx
    ; tcb 记录 堆栈尺寸
    shr dword [es:esi+0x1a], 12
    call sys_routine_seg_sel:allocate_memory
    ; 获取堆栈高地址
    add eax, ecx
    ; 记录到 tcb 中
    mov [es:esi+0x1e], eax
    ; 段界限
    mov ebx, 0xffffe
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
    mov ebx, esi
    ; 生成段选择子载入到 ldt 中
    call fill_descriptor_in_ldt
    ; 0 级堆栈选择子记录到 tcb 中
    mov [es:esi+0x22], cx
    ; tcb 记录初始 0 级堆栈 esp
    mov dword [es:esi+0x24], 0

    ; 创建 1 特权级堆栈
    mov ecx, 4096
    mov eax, ecx
    mov [es:esi+0x28], ecx
    ; tcb 记录 堆栈尺寸
    shr dword [es:esi+0x28], 12
    call sys_routine_seg_sel:allocate_memory
    ; 获取堆栈高地址
    add eax, ecx
    ; 记录到 tcb 中
    mov [es:esi+0x2c], eax
    ; 段界限
    mov ebx, 0xffffe
    ; 栈段的属性是
    ; 段粒度为 4kb (G=1)
    ; 属于数据段(S=1)
    ; 是32 bit 的段(D=1)
    ; 位于内存中(P=1)
    ; 特权级别是1(DPL=01)
    ; 不可执行，向下扩展，可写入(TYPE=0110)
    ; 所以在高 32 bit 中除去基地址和界限以外的值为 0x00c0b600
    mov ecx, 0x00c0b600
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx, esi
    ; 生成段选择子载入到 ldt 中
    call fill_descriptor_in_ldt
    ; 设置特权级为 1
    or cx, 0000_0000_0000_0001
    ; 1 级堆栈选择子记录到 tcb 中
    mov [es:esi+0x30], cx
    ; tcb 记录初始 1 级堆栈 esp
    mov dword [es:esi+0x32], 0

    ; 创建 2 特权级堆栈
    mov ecx, 4096
    mov eax, ecx
    mov [es:esi+0x36], ecx
    ; tcb 记录 堆栈尺寸
    shr dword [es:esi+0x36], 12
    call sys_routine_seg_sel:allocate_memory
    ; 获取堆栈高地址
    add eax, ecx
    ; 记录到 tcb 中
    mov [es:esi+0x3a], eax
    ; 段界限
    mov ebx, 0xffffe
    ; 栈段的属性是
    ; 段粒度为 4kb (G=1)
    ; 属于数据段(S=1)
    ; 是32 bit 的段(D=1)
    ; 位于内存中(P=1)
    ; 特权级别是2(DPL=10)
    ; 不可执行，向下扩展，可写入(TYPE=0110)
    ; 所以在高 32 bit 中除去基地址和界限以外的值为 0x00c0d600
    mov ecx, 0x00c0d600
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx, esi
    ; 生成段选择子载入到 ldt 中
    call fill_descriptor_in_ldt
    ; 设置特权级为 2
    or cx, 0000_0000_0000_0010
    ; 2 级堆栈选择子记录到 tcb 中
    mov [es:esi+0x3e], cx
    ; tcb 记录初始 2 级堆栈 esp
    mov dword [es:esi+0x40], 0

    ; 在 gdt 里记录 ldt 描述符
    ; 起始线性地址
    mov eax, [es:esi+0x0c]
    ; 段界限
    movzx ebx, word [es:esi+0x0a]
    ; todo 注释属性
    mov ecx, 0x00408200
    call sys_routine_seg_sel:make_seg_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    ; 记录 ldt 选择子 到 tcb 中
    mov [es:esi+0x10], cx

    ; 创建用户程序的 tss 任务状态段
    mov ecx, tss_size
    ; tcb 记录 tss 界限值
    mov [es:esi+0x12], cx
    dec word [es:esi+0x12]
    call sys_routine_seg_sel:allocate_memory
    ; tcb 记录申请到的 tss 内存起始基地址
    mov [es:esi+0x14], ecx

    ; tss 内容
    ; todo 注释 tss 结构
    mov word [es:ecx+0], 0 ; 反向链
     ; tss 记录 0 特权级堆栈初始 esp
    mov edx, [es:esi+0x24]
    mov [es:ecx+4], edx
    ; tss 记录 0 特权级堆栈选择子
    mov dx, [es:esi+0x22]
    mov [es:ecx+8], dx

    ; tss 记录 1 特权级堆栈信息
    mov edx, [es:esi+0x32]
    mov [es:ecx+12], edx
    mov dx, [es:esi+0x30]
    mov [es:ecx+16], dx

    ; tss 记录 2 特权级堆栈信息
    mov edx, [es:esi+0x40]
    mov [es:ecx+20], edx
    mov dx, [es:esi+0x3e]
    mov [es:ecx+24], dx

    ; tss 记录 ldt 选择子
    mov dx, [es:esi+0x10]
    mov [es:ecx+96], dx

    ; tss 记录 i/o 位图偏移
    mov dx, [es:esi+0x12]
    mov [es:ecx+102], dx

    mov word [es:ecx+100], 0

    ; 在 gdt 记录 tss 描述符
    mov eax, [es:esi+0x14]
    movzx ebx, word [es:esi+0x12]
    ; 特权级为 0
    mov ecx, 0x00408900
    call sys_routine_seg_sel:make_seg_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    ; tcb 记录 tss 选择子
    mov [es:esi+0x18], cx

    pop es
    pop ds

    popad

    ret 8 ; 丢弃调用前压入的参数

append_to_tcb_link:
    ; 追加 tcb 链表
    ; 入参
    ; ecx = tcb 线性基地址
    push eax
    push edx
    push ds
    push es

    ; ds 指向内核数据段选择子
    mov eax, kernel_data_seg_sel
    mov ds, eax
    ; es 指向内存段选择子
    mov eax, mem_seg_sel
    mov es, eax

    mov dword [es:ecx+0x00], 0 ; 初始化 tcb
    mov eax, [tcb_chain] ; 获取 tcb 链表头指针
    or eax, eax ; 检查链表是否为空
    jz .notcb
.search:
    ; edx 复制表头指针
    mov edx, eax
    ; eax 指向下一个 tcb 指针
    mov eax, [es:edx+0x00]
    ; 检查是否为空指针
    or eax, eax
    jnz .search
    ; 为空，填入当前申请到的 tcb 指针线性基地址
    mov [es:edx+0x00], ecx
    jmp .retpc
.notcb:
    ; 如果表为空，直接填入当前 tcb 指针线性基地址
    mov [tcb_chain], ecx
.retpc:
    pop es
    pop ds
    pop edx
    pop eax

    ret

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

    ; 安装调用门
    mov edi, symbol_address_lookup_table
    ; 循环安装
    mov ecx, salt_items
.b5:
    ; 要用到 cx 所以先把循环次数入栈保存
    push ecx
    mov eax, [edi+256]
    mov bx, [edi+260]
    ; 调用门描述符组成释义
    ; P: 有效位 0-调用产生异常中断 1-正常调用 异常中断可用于计算门调用次数
    ; DPL: 特权级别 0、1、2、3
    ; TYPE: 门类型 1100 - 调用门
    ; 高 32 bit
    ; 4个16进制   _P+DPL+无用位组成1个16进制 _1个16进制 _2个16进制
    ; 段内偏移31~16_有效位P_特权级别DPL_无用位_门类型TYPE_无用位7~5_参数个数4~0
    ; 低 32 bit
    ; 4个16进制     _4个16进制
    ; 例程选择子32~16_段内偏移量15~0
    ; 调用门需要被所有程序使用，所以特权级为3级即 DPL 为 11
    ; 使用寄存器传参所以参数个数为0
    ; 所以在高 32 bit 中除去段内偏移的值为 1_11_0_1100_000_00000B
    mov cx, 1_11_0_1100_000_00000B
    ; 构造门描述符并安装 gdt
    call sys_routine_seg_sel:make_gate_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    ; 256 byte 描述例程名称 + 4 byte 入口 + 2 byte 选择子
    mov [edi+260], cx ; 回填门描述符的选择子
    add edi, salt_item_len ; 指向下一个条目
    ; 取回循环次数
    pop ecx
    loop .b5

    ; 测试门
    mov ebx, message_call_gate_mount
    ; 通过门调用
    ; 处理器会使用该选择子访问 gdt / ldt 确定是否为门描述符
    ; call far 会把 cs:eip 设置成门地址的段选择子:32 bit 偏移量
    ; 但是门调用会忽略 32 bit 偏移量
    ; 因为偏移地址已经包含在门描述符中
    call far [salt_print_string+256]

    ; 加载用户程序，完毕后提示
    mov ebx, message_load_app_start
    call sys_routine_seg_sel:put_string

    ; 创建 tcb
    ; 首先申请内存
    mov ecx, tcb_size
    call sys_routine_seg_sel:allocate_memory
    ; 然后将内存首地址追加到 tcb 链表
    call append_to_tcb_link
    ; 将用户逻辑扇区和 tcb 线性基地址压入栈
    push dword app_start_sector
    push ecx

    call load_relocate_program

    mov ebx, message_load_app_done
    call sys_routine_seg_sel:put_string

    mov eax, mem_seg_sel
    mov ds, eax

    ltr [ecx+0x18] ; 加载 tss
    lldt [ecx+0x10] ; 加载 ldt
    ; 通过 tcb 获取用户程序头部段
    mov eax, [ecx+0x44]
    mov ds, eax

    ; fake
    push dword [0x08]
    push dword 0

    push dword [0x14]
    push dword [0x10]

    retf

return_point:
    ; 用户程序返回内核
    ; 数据段恢复为内核数据段
    mov eax, kernel_data_seg_sel
    mov ds, eax

    ; 打印返回内核提示
    mov ebx, message_app_terminated
    call sys_routine_seg_sel:put_string

    hlt

SECTION kernel_trail
kernel_end:
