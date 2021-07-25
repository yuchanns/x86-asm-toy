**REQUIRE** `binutils` for llvm and `qemu-system-x86_64` installed

short command:
```sh
make all
```
or complex:
```sh
nasm -f elf mbr.asm
ld.lld --script=linker.ld mbr.o -o mbr.elf
llvm-objcopy -O binary mbr.elf mbr.bin
qemu-system-x86_64 -drive format=raw,file=mbr.bin -accel hvf -cpu Nehalem
```

