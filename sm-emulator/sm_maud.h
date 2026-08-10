/*
 * sm_maud.h - Virtual SM definitions for CogniForge VX MAUD execution.
 * Each SM maintains 32 warp slots, a register file, and executes
 * MAUD (Prometheus ISA) binary instructions from pisa_compiler.
 */

#ifndef _SM_MAUD_H
#define _SM_MAUD_H

#include <stdint.h>
#include <pthread.h>

#define MAX_WARPS_PER_SM      32
#define MAX_THREADS_PER_WARP  32
#define MAX_REGS_PER_THREAD   256
#define MAX_SHARED_MEM_BYTES  49152
#define MAX_MAUD_INSTRUCTIONS  65536

/* MAUD Opcodes (MIAOW-based Prometheus ISA) */
enum MaudOpcode {
    MAUD_S_MOV_B32     = 0x01000000,
    MAUD_S_MOV_B64     = 0x01000001,
    MAUD_S_ADD_F32     = 0x02000000,
    MAUD_S_MUL_F32     = 0x02000001,
    MAUD_S_MAD_F32     = 0x02000002,
    MAUD_S_DIV_F32     = 0x02000003,
    MAUD_S_ADD_I32     = 0x03000000,
    MAUD_S_MUL_I32     = 0x03000001,
    MAUD_S_MAD_I32     = 0x03000002,
    MAUD_S_MIN_I32     = 0x03000003,
    MAUD_S_MAX_I32     = 0x03000004,
    MAUD_S_AND_B32     = 0x04000000,
    MAUD_S_OR_B32      = 0x04000001,
    MAUD_S_XOR_B32     = 0x04000002,
    MAUD_S_SHL_B32     = 0x04000003,
    MAUD_S_SHR_B32     = 0x04000004,
    MAUD_S_LOAD_F32    = 0x05000000,
    MAUD_S_STORE_F32   = 0x05000001,
    MAUD_S_LOAD_SHARED = 0x05000002,
    MAUD_S_STORE_SHARED= 0x05000003,
    MAUD_S_ATOMIC_ADD  = 0x06000000,
    MAUD_S_ATOMIC_MIN  = 0x06000001,
    MAUD_S_ATOMIC_MAX  = 0x06000002,
    MAUD_S_TENSOR_MMA  = 0x07000000,
    MAUD_S_TENSOR_CONV = 0x07000001,
    MAUD_S_TENSOR_REDUCE=0x07000002,
    MAUD_S_BAR_SYNC    = 0x08000000,
    MAUD_S_EXIT        = 0xFFFFFFFF,
};

typedef struct __attribute__((packed)) {
    uint32_t opcode;
    uint8_t  dst_reg;
    uint8_t  src_reg_a;
    uint8_t  src_reg_b;
    uint8_t  src_reg_c;
    uint32_t immediate;
    uint32_t flags;
} MaudInstruction;

typedef struct {
    uint32_t warp_id;
    uint32_t active_mask;
    uint32_t pc;
    uint32_t regs[MAX_THREADS_PER_WARP][MAX_REGS_PER_THREAD];
    uint8_t  active;
    uint32_t block_idx_x, block_idx_y, block_idx_z;
    uint32_t thread_idx;
} WarpState;

typedef struct {
    uint32_t sm_id;
    WarpState warps[MAX_WARPS_PER_SM];
    uint32_t active_warp_count;
    uint8_t  shared_mem[MAX_SHARED_MEM_BYTES];
    MaudInstruction *program;
    uint32_t program_size;
    uint32_t grid_dim_x, grid_dim_y, grid_dim_z;
    uint32_t block_dim_x, block_dim_y, block_dim_z;
    uint64_t vram_base;
    pthread_mutex_t lock;
} SMState;

void sm_init(SMState *sm, uint32_t sm_id);
void sm_load_program(SMState *sm, MaudInstruction *program, uint32_t size);
void sm_launch_kernel(SMState *sm,
                      uint32_t gx, uint32_t gy, uint32_t gz,
                      uint32_t bx, uint32_t by, uint32_t bz,
                      uint64_t vram_base);
void sm_execute(SMState *sm);
void sm_reset(SMState *sm);
uint32_t sm_get_active_warps(SMState *sm);
void warp_step(SMState *sm, uint32_t warp_idx);

#endif /* _SM_MAUD_H */
