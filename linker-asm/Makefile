RM = rm

ASM     = nasm
LD      = ld.lld
OBJCOPY = llvm-objcopy
QEMU    = qemu-system-x86_64

ASMBFLAGS    = -f elf
LDFLAGS      = --script=linker.ld
OBJCOPYFLAGS = -O binary
QEMUFLAGS    = -drive format=raw,file=$(KERNEL_BIN) -accel hvf -cpu Nehalem

KERNEL_OBJS :=
KERNEL_OBJS += mbr.o app.o
KERNEL_ELF  = kernel.elf
KERNEL_BIN  = kernel.bin

.PHONY : build clean all link bin qemu

all: clean build link bin qemu

clean:
	$(RM) -rf *.o *.bin *.elf

build: $(KERNEL_OBJS)

link: $(KERNEL_ELF)
$(KERNEL_ELF): $(KERNEL_OBJS)
	$(LD) $(LDFLAGS) -o $@ $(KERNEL_OBJS)

bin: $(KERNEL_BIN)
$(KERNEL_BIN): $(KERNEL_ELF)	
	$(OBJCOPY) $(OBJCOPYFLAGS) $< $@

qemu:
	$(QEMU) $(QEMUFLAGS)	

%.o : %.asm
	$(ASM) $(ASMBFLAGS) -o $@ $<

