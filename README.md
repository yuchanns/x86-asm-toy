# x86-asm-toy
Practise of the Book [《x86汇编：从实模式到保护模式》](https://book.douban.com/subject/20492528//)

## Convert Img File
```sh
dd if=/dev/zero of=kernel.img bs=512 count=3
dd if=mbr.bin of=kernel.img bs=512 count=1
dd if=kernel.bin of=kernel.img seek=1 bs=512 count=2
qemu-system-x86_64 -drive format=raw,file=kernel.img
```

