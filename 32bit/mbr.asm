; 先以实模式加载本段程序, 然后再通过保护模式加载本段程序
; 保护模式需要定义 gdt, 描述代码段、数据段和栈段（特殊数据段）
SECTION mbr vstart=0
    mov ax, cs
    mov ss, ax
    ; 栈指针设置在本段程序被加载的位置，向低地址扩展
    ; 从 0x0000 到 0x7c00 之间还存在 IVT ，其数据可能被栈破坏
    mov sp, 0x7c00

    ; 计算 gdt 的起始逻辑地址和偏移地址
    ; 因为引导程序被加载到0x7c00，所以手动补正偏移地址加上0x7c00
    mov ax, [cs:gdt_base+0x7c00]
    mov dx, [cs:gdt_base+0x7c00+0x02]
    mov bx, 16
    div bx ; dx:ax / bx 表示右移去掉一个0
    mov ds, ax ; 逻辑段地址
    mov bx, dx ; 偏移段地址

    ; gdt 中每个描述符占8 byte = double word = 64 bit
    ; #0描述符必须是空描述符，全部是0
    mov dword [bx+0x00], 0x00
    mov dword [bx+0x04], 0x00

    ; gdt 描述符组成释义
    ; G: 0 - byte, 1 - 4KB; D: 0 - 16bit, 1 - 32bit; P: 0 - 在硬盘, 1 - 在内存
    ; S: 0 - 系统段, 1 - 数据段或代码段; DPL: 特权级别 0、1、2、3
    ; TYPE: 数据段 执行(0-不可, 1-可)_扩展方向(0-向上, 1-向下)_写入(0-不可, 1-可)_最近是否被访问
    ; TYPE: 代码段 执行(0-不可, 1-可)_特权级依从(0-从相同级别调用或通过门调用, 1-从低特权转移到该段执行)_可读(0-不可, 1-可)_最近是否被访问
    ; 高32 bit:
    ; 2个16进制  _G+D+L+无用位组成1个16进制          _1个16进制  _P+DPL+S 组成1个16进制         _1个16进制 _2个16进制
    ; 段基址31~24_段粒度G_段位数D_64位代码段标志L_无用位_段界限19~16_是否位于内存P_特权级别DPL_段类型S_段类别TYPE_段基址23~16
    ; 00000000  _0    _0     _0            _0    _0000     _0          _00       _0     _0000     _00000000
    ; 低32 bit:
    ; 4个16进制        _4个16进制
    ; 段基址15~0       _段界限15~0
    ; 0000000000000000_0000000000000000

    ; #1描述符为代码段描述符，指向了本段引导程序
    ; 基地址为 0x00007c00 32
    ; 段粒度为 byte (G=0)
    ; 本段引导程序长度为512 byte 所以界限为 0x001ff
    ; 属于代码段(S=1)
    ; 是32 bit 的段(D=1)
    ; 位于内存中(P=1)
    ; 特权级别是0(DPL=00)
    ; 只能执行，不可从低级调用，不可被其他代码段读(TYPE=1000)
    ; 综上，低32 bit 转为16进制的值为 0x7c00_01ff
    ; 高32 bit 转为16进制的值为 0x0040_9800
    mov dword [bx+0x08], 0x7c0001ff
    mov dword [bx+0x0c], 0x00409800

    ; #2描述符为数据段描述符，用于存放在32 bit 屏幕上显示的数据
    ; 所以把数据段设置显存映射的物理地址，即基地址为 0x000b8000
    ; 段粒度为 byte (G=0)
    ; 32 bit 下 VGA 的缓冲区长度为64 kB, 即65536 byte，即（从 0x00000 开始算） 0x0ffff
    ; 属于数据段(S=1)
    ; 是32 bit 的段(D=1)
    ; 位于内存中(P=1)
    ; 特权级别是0(DPL=00)
    ; 可读写，向上扩展(TYPE=0010)
    ; 综上，低32 bit 转为16进制的值为 0x8000_ffff
    ; 高32 bit 转为16进制的值为 0x0040_920b
    mov dword [bx+0x10], 0x8000ffff
    mov dword [bx+0x14], 0x0040920b

    ; #3描述符为栈段描述符
    ; 基地址从 0x00000000 开始
    ; 段粒度为 byte (G=0)
    ; esp 允许的最小值是 0x07a01 所以界限值为 0x07a00
    ; 属于数据段(S=1)
    ; 是32 bit 的段(D=1)
    ; 位于内存中(P=1)
    ; 特权级别是0(DPL=00)
    ; 可读写，向下扩展(TYPE=0110)
    ; 综上，低32 bit 转为16进制的值为 0x00007a00
    ; 高32 bit 转为16进制的值为 0x00409600
    mov dword [bx+0x18], 0x00007a00
    mov dword [bx+0x1c], 0x00409600

    ; 记录描述符表的界限
    ; 因为引导程序被加载到0x7c00，所以手动补正偏移地址加上0x7c00
    mov word [cs:gdt_size+0x7c00], 31

    ; 加载描述附表的线性基地址和界限到 gdtr
    ; lgdt 的操作数是 48 bit 正好是 gdt_size+gdt_base(dw+dd=3word=6byte=48bit)
    lgdt [cs:gdt_size+0x7c00]

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
    ; 代码段描述符索引为#1, 在 gdt 中, 特权级为 0
    ; 所以段选择子为 0000000000001_0_00 转为16进制的值为 0x0008
    ; 加上偏移地址(标号)就组成了 32 bit 下的物理地址
    jmp dword 0x0008:flush

    [bits 32] ; 指示编译器下面的代码编译成 32 bit 指令

clean_screen:
    mov si, 0x00 ; 循环清空屏幕
    .loop:
        mov byte [si], ' '
        ; 连续增加两次地址，跳过颜色位
        inc si
        ; 注意避免超出数据段的界限
        cmp si, 0x0ffff
        je .done
        inc si
        jmp .loop
    .done:
        ret

flush:
    ; 在屏幕上打印文字，需要选中数据段
    ; 数据段描述符索引为#2, 在 gdt 中, 特权级为 0
    ; 所以段选择子为 0000000000010_0_00 转为16进制的值为 0x0010
    mov cx, 0x0010
    mov ds, cx
    call clean_screen

    ; 在屏幕上显示文字，默认使用段选择子 ds
    mov byte [0x7c0], 'P'
    mov byte [0x7c2], 'r'
    mov byte [0x7c4], 'o'
    mov byte [0x7c6], 't'
    mov byte [0x7c8], 'e'
    mov byte [0x7ca], 'c'
    mov byte [0x7cc], 't'
    mov byte [0x7ce], ' '
    mov byte [0x7d0], 'm'
    mov byte [0x7d2], 'o'
    mov byte [0x7d4], 'd'
    mov byte [0x7d6], 'e'
    mov byte [0x7d8], ' '
    mov byte [0x7da], 'O'
    mov byte [0x7dc], 'K'

    ; 使用栈段
    ; 栈段描述符索引为#3, 在 gdt 中, 特权级为 0
    ; 所以段选择子为 0000000000011_0_00 转为16进制的值为 0x0018
    mov cx, 0x0018
    mov ss, cx
    mov esp, 0x7c00

    mov ebp, esp
    push byte '.'

    ; 校验一下压入一个立即数 esp 是否减 4
    sub ebp, 4
    cmp ebp, esp
    jnz ghalt

    pop eax
    mov [0x7de], al
ghalt:
    hlt ; 中断被关闭，不会唤醒

    gdt_size dw 0
    gdt_base dd 0x00007e00 ; 32 bit / 8 = 4 byte

    times 510-($-$$) db 0
                     db 0x55, 0xaa