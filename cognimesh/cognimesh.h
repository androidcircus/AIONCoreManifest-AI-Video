/*
 * cognimesh.h - CogniMesh fabric definitions.
 * RDMA-based mesh interconnect using InfiniBand verbs for
 * inter-VM atomic operations (atomicAdd, atomicMin, atomicMax).
 */

#ifndef _COGNIMESH_H
#define _COGNIMESH_H

#include <stdint.h>
#include <infiniband/verbs.h>
#include <pthread.h>

#define COGNIMESH_MAX_NODES      100
#define COGNIMESH_MAX_QPS       256
#define COGNIMESH_ATOMIC_TIMEOUT 5000  /* ms */
#define COGNIMESH_MAX_MR_SIZE   (2ULL << 40)  /* 2 TB */

typedef enum {
    COGNIMESH_OP_ATOMIC_ADD = 0,
    COGNIMESH_OP_ATOMIC_MIN = 1,
    COGNIMESH_OP_ATOMIC_MAX = 2,
} CogniMeshAtomicOp;

typedef enum {
    COGNIMESH_DTYPE_F32 = 0,
    COGNIMESH_DTYPE_F16 = 1,
    COGNIMESH_DTYPE_I32 = 2,
} CogniMeshDType;

typedef struct {
    uint32_t node_id;
    uint32_t num_qps;
    uint32_t max_wrs;
    struct ibv_context *ib_ctx;
    struct ibv_pd *pd;
    struct ibv_mr *mr;             /* memory region for VRAM */
    struct ibv_cq *cq;
    struct ibv_qp **qps;           /* QP per remote node */
    void *vram_ptr;               /* local VRAM buffer */
    uint64_t vram_size;
    pthread_mutex_t lock;
} CogniMeshNode;

int cognimesh_init(CogniMeshNode *node, uint32_t node_id, const char *ib_dev_name);
int cognimesh_connect(CogniMeshNode *node, uint32_t remote_id, const char *remote_addr);
int cognimesh_atomic_add(CogniMeshNode *node, uint32_t remote_id,
                         uint64_t remote_offset, float value, float *result);
int cognimesh_atomic_min(CogniMeshNode *node, uint32_t remote_id,
                         uint64_t remote_offset, float value, float *result);
int cognimesh_atomic_max(CogniMeshNode *node, uint32_t remote_id,
                         uint64_t remote_offset, float value, float *result);
void cognimesh_shutdown(CogniMeshNode *node);

#endif /* _COGNIMESH_H */
