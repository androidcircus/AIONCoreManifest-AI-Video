/*
 * jit_cache.h - JIT compilation cache for CogniForge VX tensor ops.
 * Hash-based lookup of pre-compiled AVX-512 micro-kernels.
 * Avoids recompilation of identical tensor shapes across kernel launches.
 */

#ifndef _JIT_CACHE_H
#define _JIT_CACHE_H

#include <stdint.h>
#include <stddef.h>

#define JIT_CACHE_SIZE 4096
#define JIT_MAX_KERNEL_SIZE (64 * 1024)  /* 64 KB max per compiled kernel */

typedef struct {
    uint64_t key;                    /* hash key: shape + op type */
    void *code;                      /* pointer to JIT'd machine code */
    uint32_t code_size;              /* size of compiled code */
    uint32_t ref_count;              /* how many active kernel launches use this */
    uint8_t  occupied;               /* slot in use */
} JitCacheEntry;

typedef struct {
    JitCacheEntry entries[JIT_CACHE_SIZE];
    uint32_t num_entries;
    uint64_t total_compiles;
    uint64_t total_cache_hits;
} JitCache;

/* Cache operations */
void jit_cache_init(JitCache *cache);
void *jit_cache_lookup(JitCache *cache, uint64_t key, uint32_t *out_size);
int jit_cache_insert(JitCache *cache, uint64_t key, void *code, uint32_t size);
void jit_cache_evict(JitCache *cache, uint64_t key);
void jit_cache_flush(JitCache *cache);
double jit_cache_hit_rate(JitCache *cache);

/* Hash function for tensor op key */
static inline uint64_t jit_hash(uint32_t op, uint32_t m, uint32_t n, uint32_t k,
                                uint32_t dtype, uint32_t flags) {
    uint64_t h = ((uint64_t)op << 56) | ((uint64_t)m << 42) |
                 ((uint64_t)n << 28) | ((uint64_t)k << 14) |
                 ((uint64_t)dtype << 7) | (uint64_t)flags;
    h ^= h >> 33; h *= 0xff51afd7ed558ccdULL;
    h ^= h >> 33; h *= 0xc4ceb9fe1a85ec53ULL;
    h ^= h >> 33;
    return h % JIT_CACHE_SIZE;
}

#endif /* _JIT_CACHE_H */
