    kernel_base_addr    equ 0x00040000 ; 内核加载的物理地址
    kernel_start_sector equ 1 ; 内核存在的逻辑扇区号

    mov ax, cs
    mov ss, ax
    mov sp, 0x7c00 ; 栈顶设置在 mbr 载入的位置，向下扩展

    ; 计算 gdt 逻辑段位置 eax/16
    mov eax, [cs:pgdt+0x7c00+0x02] ; 偏移 2 byte 跳过描述符表界限
    xor edx, edx
    mov ebx, 16
    div ebx
    mov ds, eax ; 指向 gdt 段地址
    mov ebx, edx ; 段内偏移地址

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

    ; gdt 中每个描述符占8 byte = double word = 64 bit
    ; #0描述符必须是空描述符，全部是0
    mov dword [ebx+0x00], 0x00000000
    mov dword [ebx+0x04], 0x00000000

    ; #1描述符为数据段描述符
    ; 基地址为 0x00000000
    ; 段粒度为 4kb (G=1)
    ; 长度为整个32 bit 处理器可以访问的内存所以界限为 0xfffff
    ; 属于数据段(S=1)
    ; 是32 bit 的段(D=1)
    ; 位于内存中(P=1)
    ; 特权级别是0(DPL=00)
    ; 可读写，向上扩展(TYPE=0010)
    ; 综上，低32 bit 转为16进制的值为 0x0000_ffff
    ; 高32 bit 转为16进制的值为 0x00cf_9200
    mov dword [ebx+0x08], 0x0000ffff
    mov dword [ebx+0x0c], 0x00cf9200

    ; #2描述符为代码段描述符，指向了本段引导程序
    ; 基地址为 0x00007c00
    ; 段粒度为 byte (G=0)
    ; 本段引导程序长度为512 byte 所以界限为 0x001ff
    ; 属于代码段(S=1)
    ; 是32 bit 的段(D=1)
    ; 位于内存中(P=1)
    ; 特权级别是0(DPL=00)
    ; 只能执行，不可从低级调用，不可被其他代码段读(TYPE=1000)
    ; 综上，低32 bit 转为16进制的值为 0x7c00_01ff
    ; 高32 bit 转为16进制的值为 0x0040_9800
    mov dword [ebx+0x10], 0x7c0001ff
    mov dword [ebx+0x14], 0x00409800

    ; #3描述符为栈段描述符
    ; 基地址从 0x00007c00 开始
    ; 段粒度为 4kb (G=1)
    ; 界限值为 0xffffe
    ; 属于数据段(S=1)
    ; 是32 bit 的段(D=1)
    ; 位于内存中(P=1)
    ; 特权级别是0(DPL=00)
    ; 可读写，向下扩展(TYPE=0110)
    ; 综上，低32 bit 转为16进制的值为 0x7c00fffe
    ; 高32 bit 转为16进制的值为 0x00cf9600
    mov dword [ebx+0x18], 0x7c00fffe
    mov dword [ebx+0x1c], 0x00cf9600

    ; #4描述符为 VGA 缓冲区描述符
    ; 基地址从 0x000b8000 开始
    ; 段粒度为 bit (G=0)
    ; 界限值为 0x07fff
    ; 属于数据段(S=1)
    ; 是32 bit 的段(D=1)
    ; 位于内存中(P=1)
    ; 特权级别是0(DPL=00)
    ; 可读写，向上扩展(TYPE=0010)
    ; 综上，低32 bit 转为16进制的值为 0x80007fff
    ; 高32 bit 转为16进制的值为 0x0040920b
    mov dword [ebx+0x20], 0x80007fff
    mov dword [ebx+0x24], 0x0040920b

    ; 记录描述符表的界限
    ; 因为引导程序被加载到0x7c00，所以手动补正偏移地址加上0x7c00
    mov word [cs:pgdt+0x7c00], 39

    ; 加载描述附表的线性基地址和界限到 gdtr
    ; lgdt 的操作数是 48 bit 正好是 gdt_size+gdt_base(dw+dd=3word=6byte=48bit)
    lgdt [cs:pgdt+0x7c00]

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
    jmp dword 0x0010:flush

    [bits 32] ; 指示编译器下面的代码编译成 32 bit 指令

flush:
    ; 加载#1描述符即数据段 4GB 的选择子, 在 gdt 中, 特权级为 0
    ; 所以段选择子为 0000000000001_0_00 即 0x0008
    mov eax, 0x0008
    mov ds, eax

    ; 引导程序别名数据段描述符索引为#3, 在 gdt 中, 特权级为 0
    ; 所以段选择子为 0000000000011_0_00 即 0x0018
    mov eax, 0x0018
    mov ss, eax
    xor esp, esp

    ; 开始加载内核
    mov edi, kernel_base_addr
    mov eax, kernel_start_sector
    mov ebx, edi
    call read_hard_disk_0 ; 读取内核第一个扇区，获取大小信息

    mov eax, [edi] ; ds:kernel_base_addr
    xor edx, edx
    mov ecx, 512
    div ecx
    ; 内核长度有三种结果
    or edx, edx
    ; 1. 有商 eax 和余数 edx ，所以实际扇区数 eax+1 。因为已经读取了一扇，所以剩余未读扇区数 eax
    jnz @1
    ; 2. 有商 eax 余数 edx 为 0 ，所以实际扇区数为 eax 。因为已经读取了一扇，所以剩余未读扇区数为 eax -1
    dec eax
@1:
    ; 3. 商 eax 为 0 ，即长度不足一扇，读取直接完毕
    ; 同时如果是第2种结果且刚好一扇这里 eax 也变成0，也直接读取完毕
    or eax, eax
    jz setup

    ; 循环读剩余扇区
    mov ecx, eax
    mov eax, kernel_start_sector
    inc eax
@2:
    call read_hard_disk_0
    inc eax
    loop @2
setup:
    ; 载入内核后，改写 gdt 将内核描述符加入然后重载 gdtr
    mov esi, [pgdt+0x7c00+0x02] ; 代码段无法直接更改 gdt 需要通过 4 gb 数据段访问 pgdt
    ; TODO: 可以优化创建 gdt 描述符的逻辑，复用重复代码，自动计算界限
    mov eax, [edi+0x04] ; 例程代码段起始地址偏移值
    mov ebx, [edi+0x08] ; 内核数据段起始地址偏移值
    ; 内核数据段起始地址-例程代码段起始地址-1=例程代码段界限
    sub ebx, eax
    dec ebx

    add eax, edi ; 段地址偏移值加上载入地址获取例程代码段的的真实段地址

    ; 例程代码段的属性是
    ; 段粒度为 byte (G=0)
    ; 属于代码段(S=1)
    ; 是32 bit 的段(D=1)
    ; 位于内存中(P=1)
    ; 特权级别是0(DPL=00)
    ; 只能执行，不可从低级调用，不可被其他代码段读(TYPE=1000)
    ; 所以在高 32 bit 中除去基地址和界限以外的值为 0x00409800
    mov ecx, 0x00409800

    ; 动态生成例程代码段的 gdt 描述符 edx:eax
    call make_gdt_descriptor
    ; 创建#5描述符
    mov [esi+0x28], eax
    mov [esi+0x2c], edx

    ; 为内核数据段创建#6描述符
    mov eax, [edi+0x08]
    mov ebx, [edi+0x0c]
    sub ebx, eax
    dec ebx
    add eax, edi
    ; 代码属性 TYPE=0010
    mov ecx, 0x00409200
    call make_gdt_descriptor
    mov [esi+0x30], eax
    mov [esi+0x34], edx

    ; 为内核代码段创建#7描述符
    mov eax, [edi+0x0c]
    mov ebx, [edi+0x00]
    sub ebx, eax
    dec ebx
    add eax, edi
    mov ecx, 0x00409800
    call make_gdt_descriptor
    mov [esi+0x38], eax
    mov [esi+0x3c], edx

    mov word [pgdt+0x7c00], 63 ; 更新界限

    lgdt [pgdt+0x7c00]

    jmp far [edi+0x10] ; 跳转到内核的代码入口

read_hard_disk_0:
    ; TODO: 补充详细读硬盘逻辑注释
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

    ret

make_gdt_descriptor:
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

    ret

    pgdt dw 0 ; 描述符表界限
         dd 0x00007e00 ; gdt 物理地址 设置在 mbr(512byte) 之后，正好是 0x7c00+0x200=0x7e00
    times 510-($-$$) db 0
                     db 0x55, 0xaa
