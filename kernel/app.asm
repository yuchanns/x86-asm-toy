disk_data_sector equ 100

SECTION header vstart=0
    dd program_end ; 程序总长度 0x00
    dd header_end ; 程序头部长度 加载后回填为选择子 0x04
    stack_seg dd 0 ; 栈段选择子序号 0x08
    stack_len dd 1 ; 堆栈大小 (单位 4kb) 0x0c
    dd start ; 程序入口 0x10
    dd section.code.start ; 代码段 加载后回填为选择子 0x14
    dd code_end ; 代码段长度 0x18
    data_seg dd section.data.start ; 数据段 加载后回填为选择子 0x1c
    data_len dd data_end ; 数据段长度 0x20

    ; 符号地址检索表项数，用于存放操作系统 api
    dd (header_end-symbol_address_lookup_table)/256 ; 0x24

symbol_address_lookup_table: ; 0x28
    ; 系统 api 内存地址占位，长度固定为 256 byte 用 0 填充
    ; 加载后被内核替换成系统 api 内存地址
    PrintString db '@PrintString'
        times 256-($-PrintString) db 0
    TerminateProgram db '@TerminateProgram'
        times 256-($-TerminateProgram) db 0
    ReadDiskData db '@ReadDiskData'
        times 256-($-ReadDiskData) db 0
header_end:

SECTION data vstart=0
    buffer times 1024 db 0

    message_1 db 0x0d, 0x0a, 0x0d, 0x0a
              db '**********User program is runing**********'
              db 0x0d, 0x0a, 0
    message_2 db '  Disk data:', 0x0d, 0x0a, 0

data_end:

    [bits 32]
SECTION code vstart=0
start:
    ; 通过 fs 使用头部段选择子
    mov eax, ds
    mov fs, eax
    ; 设置用户程序栈
    mov eax, [stack_seg]
    mov ss, eax
    mov esp, 0
    ; 通过 ds 使用 数据段选择子
    mov eax, [data_seg]
    mov ds, eax

    mov ebx, message_1
    ; 通过头部段选择子远程调用内核例程
    call far [fs:PrintString]

    ; 读取其他扇区的内容并放到缓冲区
    mov eax, disk_data_sector
    mov ebx, buffer
    ; 显示读取到的扇区内容
    call far [fs:ReadDiskData]
    mov ebx, message_2
    call far [fs:PrintString]
    mov ebx, buffer
    call far [fs:PrintString]

    ; 调用内核停机过程
    call far [fs:TerminateProgram]

code_end:

SECTION trail
program_end: