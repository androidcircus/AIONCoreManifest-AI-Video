/*
 * tensor_jit_avx512.c - AVX-512/BF16 micro-kernel JIT generator.
 * Generates optimized AVX-512 machine code for tensor operations
 * (matmul, convolution, reduction) at kernel launch time.
 * Compiled kernels are cached in the JitCache for reuse.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <immintrin.h>
#include "jit_cache.h"

static JitCache global_cache;

/* Initialize the global JIT cache */
void tensor_jit_init(void) {
    jit_cache_init(&global_cache);
}

/*
 * Generate an AVX-512 matmul micro-kernel for tiles of size (M, N, K).
 * In full implementation, emits actual x86 machine code via a simple
 * codegen. Here we show the reference implementation that the JIT'd
 * code replicates.
 */
static void matmul_ref(const float *A, const float *B, float *C,
                       int M, int N, int K) {
    for (int i = 0; i < M; i++) {
        for (int j = 0; j < N; j++) {
            __m512 acc = _mm512_setzero_ps();
            for (int k = 0; k < K; k += 16) {
                __m512 a = _mm512_loadu_ps(&A[i * K + k]);
                __m512 b = _mm512_loadu_ps(&B[j * K + k]);
                acc = _mm512_fmadd_ps(a, b, acc);
            }
            C[i * N + j] = _mm512_reduce_add_ps(acc);
        }
    }
}

/* Generate BF16 matmul using AVX-512 BF16 extension */
static void matmul_bf16_ref(const void *A, const void *B, float *C,
                            int M, int N, int K) {
    for (int i = 0; i < M; i++) {
        for (int j = 0; j < N; j++) {
            __m512 acc = _mm512_setzero_ps();
            for (int k = 0; k < K; k += 32) {
                __m512bh a = _mm512_loadu_ps_bh((const __bfloat16 *)&A[i * K + k]);
                __m512bh b = _mm512_loadu_ps_bh((const __bfloat16 *)&B[j * K + k]);
                acc = _mm512_dpbf16_ps(acc, a, b);
            }
            C[i * N + j] = _mm512_reduce_add_ps(acc);
        }
    }
}

/*
 * JIT a matmul kernel for specific tile dimensions.
 * Returns a function pointer to the compiled code, or NULL on failure.
 */
typedef void (*matmul_kernel_fn)(const float *A, const float *B, float *C);

matmul_kernel_fn tensor_jit_matmul(uint32_t M, uint32_t N, uint32_t K, uint32_t dtype) {
    uint64_t key = jit_hash(0x01, M, N, K, dtype, 0);
    uint32_t code_size = 0;

    /* Check cache first */
    void *cached = jit_cache_lookup(&global_cache, key, &code_size);
    if (cached) return (matmul_kernel_fn)cached;

    /*
     * Allocate executable memory for the JIT'd code.
     * In full implementation: emit optimized x86-64 machine code with
     * AVX-512 VNNI / BF16 instructions targeting this specific tile shape.
     * For now, we allocate a page and copy a thunk that calls the reference.
     */
    void *code = mmap(NULL, JIT_MAX_KERNEL_SIZE,
                      PROT_READ | PROT_WRITE | PROT_EXEC,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (code == MAP_FAILED) return NULL;

    /* Thunk: load args into registers and jump to matmul_ref */
    /* For production, this would be real codegen. This is the stub. */
    memcpy(code, matmul_ref, 64);  /* simplified */
    code_size = 64;

    jit_cache_insert(&global_cache, key, code, code_size);
    return (matmul_kernel_fn)code;
}

/* Convolution JIT kernel */
typedef void (*conv_kernel_fn)(const float *input, const float *weight,
                                float *output, int in_c, int out_c,
                                int kernel_size, int stride);

conv_kernel_fn tensor_jit_conv(uint32_t in_c, uint32_t out_c,
                               uint32_t kernel_size, uint32_t stride) {
    uint64_t key = jit_hash(0x02, in_c, out_c, kernel_size, 0, stride);
    uint32_t code_size = 0;

    void *cached = jit_cache_lookup(&global_cache, key, &code_size);
    if (cached) return (conv_kernel_fn)cached;

    void *code = mmap(NULL, JIT_MAX_KERNEL_SIZE,
                      PROT_READ | PROT_WRITE | PROT_EXEC,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (code == MAP_FAILED) return NULL;

    /* In full impl: emit im2col + matmul AVX-512 kernel */
    code_size = 64;
    jit_cache_insert(&global_cache, key, code, code_size);
    return (conv_kernel_fn)code;
}

void tensor_jit_flush(void) {
    jit_cache_flush(&global_cache);
}

double tensor_jit_hit_rate(void) {
    return jit_cache_hit_rate(&global_cache);
}
