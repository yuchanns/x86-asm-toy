EXECUTABLES = $(ASM) $(LD) $(OBJCOPY) $(QEMU)
EXECUTABLES_CHECK := $(foreach exec,$(EXECUTABLES),\
	 	$(if $(shell which $(exec)),some string,$(error "No $(exec) in PATH")))
OS := $(shell uname -s)
ACCELFLAGS :=
ifeq ($(OS),Linux)
	ACCELFLAGS += -accel kvm
else ifeq ($(OS),Darwin)
	ACCELFLAGS += -accel hvf -cpu host
else
    $(error "Not Support on Current OS")
endif

RM = rm

ASM     = nasm
LD      = ld.lld
OBJCOPY = llvm-objcopy
QEMU    = qemu-system-x86_64

ASMBFLAGS    = -f elf -F dwarf -g
LDFLAGS      = --script=linker.ld
OBJCOPYFLAGS = --strip-all -O binary
QEMUFLAGS    = -drive format=raw,file=$(KERNEL_BIN) $(ACCELFLAGS)

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

