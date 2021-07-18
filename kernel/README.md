![](./kernel.png)

```sh
nasm -f bin mbr.asm -o mbr.bin 
nasm -f bin kernel.asm -o kernel.bin
nasm -f bin app.asm -o app.bin

dd if=mbr.bin of=kernel.img seek=0 bs=512 count=1
dd if=kernel.bin of=kernel.img seek=1 bs=512 
dd if=app.bin of=kernel.img seek=10 bs=512 
dd if=diskdata.txt of=kernel.img seek=100 bs=512 

qemu-system-x86_64 -drive format=raw,file=kernel.img -accel hvf -cpu host
```