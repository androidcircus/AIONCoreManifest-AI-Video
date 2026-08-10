/*
 * sm_maud.c - Virtual SM execution engine for CogniForge VX.
 * Executes MAUD binary instructions on virtual warp slots.
 * In the full implementation, tensor ops dispatch to the AVX-512 JIT.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <pthread.h>
#include "sm_maud.h"

void sm_init(SMState *sm, uint32_t sm_id) {
    memset(sm, 0, sizeof(SMState));
    sm->sm_id = sm_id;
    pthread_mutex_init(&sm->lock, NULL);
}

void sm_load_program(SMState *sm, MaudInstruction *program, uint32_t size) {
    sm->program = program;
    sm->program_size = size;
}

void sm_launch_kernel(SMState *sm,
                      uint32_t gx, uint32_t gy, uint32_t gz,
                      uint32_t bx, uint32_t by, uint32_t bz,
                      uint64_t vram_base) {
    sm->grid_dim_x = gx; sm->grid_dim_y = gy; sm->grid_dim_z = gz;
    sm->block_dim_x = bx; sm->block_dim_y = by; sm->block_dim_z = bz;
    sm->vram_base = vram_base;

    /* Calculate total blocks and assign warps */
    uint32_t total_blocks = gx * gy * gz;
    uint32_t blocks_per_warp = 1;
    uint32_t warps_needed = (total_blocks + blocks_per_warp - 1) / blocks_per_warp;

    if (warps_needed > MAX_WARPS_PER_SM)
        warps_needed = MAX_WARPS_PER_SM;

    pthread_mutex_lock(&sm->lock);
    for (uint32_t i = 0; i < warps_needed; i++) {
        sm->warps[i].warp_id = i;
        sm->warps[i].pc = 0;
        sm->warps[i].active = 1;
        sm->warps[i].active_mask = (1u << bx * by * bz) - 1;
        sm->warps[i].block_idx_x = (i % gx);
        sm->warps[i].block_idx_y = ((i / gx) % gy);
        sm->warps[i].block_idx_z = (i / (gx * gy));
        sm->warps[i].thread_idx = 0;
        memset(sm->warps[i].regs, 0, sizeof(sm->warps[i].regs));
    }
    sm->active_warp_count = warps_needed;
    pthread_mutex_unlock(&sm->lock);
}

static float reg_f32(uint32_t *r) { float f; memcpy(&f, r, 4); return f; }
static void set_f32(uint32_t *r, float v) { memcpy(r, &v, 4); }

void warp_step(SMState *sm, uint32_t warp_idx) {
    WarpState *w = &sm->warps[warp_idx];
    if (!w->active || w->pc >= sm->program_size) return;

    MaudInstruction *inst = &sm->program[w->pc];

    for (int t = 0; t < MAX_THREADS_PER_WARP; t++) {
        if (!((w->active_mask >> t) & 1)) continue;
        uint32_t *r = w->regs[t];

        switch (inst->opcode) {
        case MAUD_S_MOV_B32:
            r[inst->dst_reg] = inst->immediate;
            break;
        case MAUD_S_ADD_F32: {
            float a = reg_f32(&r[inst->src_reg_a]);
            float b = reg_f32(&r[inst->src_reg_b]);
            set_f32(&r[inst->dst_reg], a + b);
            break;
        }
        case MAUD_S_MUL_F32: {
            float a = reg_f32(&r[inst->src_reg_a]);
            float b = reg_f32(&r[inst->src_reg_b]);
            set_f32(&r[inst->dst_reg], a * b);
            break;
        }
        case MAUD_S_MAD_F32: {
            float a = reg_f32(&r[inst->src_reg_a]);
            float b = reg_f32(&r[inst->src_reg_b]);
            float c = reg_f32(&r[inst->src_reg_c]);
            set_f32(&r[inst->dst_reg], a * b + c);
            break;
        }
        case MAUD_S_ADD_I32:
            r[inst->dst_reg] = r[inst->src_reg_a] + r[inst->src_reg_b];
            break;
        case MAUD_S_MUL_I32:
            r[inst->dst_reg] = r[inst->src_reg_a] * r[inst->src_reg_b];
            break;
        case MAUD_S_LOAD_F32:
            /* In full impl: read from vram_base + inst->immediate */
            r[inst->dst_reg] = inst->immediate;
            break;
        case MAUD_S_STORE_F32:
            /* In full impl: write r[src_reg_a] to vram_base + inst->immediate */
            break;
        case MAUD_S_ATOMIC_ADD:
            /* In full impl: dispatch to cognimesh atomic via RDMA */
            break;
        case MAUD_S_TENSOR_MMA:
            /* In full impl: dispatch to tensor JIT AVX-512 backend */
            break;
        case MAUD_S_BAR_SYNC:
            /* Wait for all threads in warp to reach barrier */
            break;
        case MAUD_S_EXIT:
            w->active = 0;
            break;
        default:
            break;
        }
    }

    if (w->active) w->pc++;
}

void sm_execute(SMState *sm) {
    pthread_mutex_lock(&sm->lock);
    while (sm->active_warp_count > 0) {
        for (uint32_t i = 0; i < MAX_WARPS_PER_SM; i++) {
            if (sm->warps[i].active) {
                warp_step(sm, i);
                if (!sm->warps[i].active) {
                    sm->active_warp_count--;
                }
            }
        }
    }
    pthread_mutex_unlock(&sm->lock);
}

void sm_reset(SMState *sm) {
    pthread_mutex_lock(&sm->lock);
    memset(sm->warps, 0, sizeof(sm->warps));
    sm->active_warp_count = 0;
    sm->program = NULL;
    sm->program_size = 0;
    pthread_mutex_unlock(&sm->lock);
}

uint32_t sm_get_active_warps(SMState *sm) {
    return sm->active_warp_count;
}
