# CogniForge VX Build System
CC      = gcc
CXX     = clang++
CFLAGS  = -O3 -Wall -fPIC -mavx512f -mavx512bw -mavx512bf16
LLVM_FLAGS = $(shell llvm-config --cxxflags --ldflags --libs core irreader passes 2>/dev/null || echo "")

.PHONY: all compiler drivers sm-emulator tensor-jit cognimesh qemu-device clean test

all: compiler sm-emulator tensor-jit cognimesh drivers qemu-device

# MAUD Compiler (LLVM-based C++)
compiler:
	$(CXX) -O3 -o compiler/pisa_compiler compiler/pisa_compiler.cpp $(LLVM_FLAGS)

# SM Emulator
sm-emulator:
	$(CC) $(CFLAGS) -c sm-emulator/sm_maud.c -o sm-emulator/sm_maud.o

# Tensor JIT (AVX-512)
tensor-jit:
	$(CC) $(CFLAGS) -c tensor-jit/tensor_jit_avx512.c -o tensor-jit/tensor_jit_avx512.o

# CogniMesh (InfiniBand RDMA)
cognimesh: cognimesh/cognimesh_init.c cognimesh/cognimesh_atomic.c
	$(CC) $(CFLAGS) -c cognimesh/cognimesh_init.c -o cognimesh/cognimesh_init.o
	$(CC) $(CFLAGS) -c cognimesh/cognimesh_atomic.c -o cognimesh/cognimesh_atomic.o

# DRM Kernel Driver
drivers:
	$(MAKE) -C drivers/linux M=$(CURDIR)/drivers/linux modules

# QEMU PCI Device
qemu-device:
	@echo "Build QEMU device in QEMU source tree: copy qemu-device/cogniforge-vx.c to qemu/hw/display/"
	@echo "Then rebuild QEMU: cd qemu && ./configure --target-list=x86_64-softmmu && make -j$(nproc)"

# CUDA Kernel to MAUD pipeline
maud-compile: kernel/video_gen.cu
	clang -x cuda --cuda-gpu-arch=sm_80 -emit-llvm -c kernel/video_gen.cu -o kernel/video_gen.bc
	./compiler/pisa_compiler kernel/video_gen.bc -o kernel/video_gen.maud

clean:
	rm -f compiler/pisa_compiler
	rm -f sm-emulator/*.o tensor-jit/*.o cognimesh/*.o drivers/linux/*.o
	rm -f kernel/*.bc kernel/*.maud
