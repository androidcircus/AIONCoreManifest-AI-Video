/*
 * cognimesh_atomic.c - RDMA atomic operations via InfiniBand verbs.
 * Implements cross-VM atomicAdd/atomicMin/atomicMax for gradient
 * accumulation and distributed reduction in the CogniForge fabric.
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>
#include "cognimesh.h"

static int post_atomic(CogniMeshNode *node, uint32_t remote_id,
                       uint64_t remote_offset, uint64_t swap_val,
                       CogniMeshAtomicOp op, float *result) {
    struct ibv_qp *qp = node->qps[remote_id];
    if (!qp) return -1;

    struct ibv_send_wr wr, *bad_wr;
    struct ibv_sge sge;
    struct ibv_wc wc;

    memset(&wr, 0, sizeof(wr));
    wr.wr_id = remote_id;
    wr.sg_list = &sge;
    wr.num_sge = 1;
    wr.send_flags = IBV_SEND_SIGNALED;

    /* Use IBV_WR_ATOMIC_FETCH_AND_ADD for atomicAdd */
    if (op == COGNIMESH_OP_ATOMIC_ADD) {
        wr.opcode = IBV_WR_ATOMIC_FETCH_AND_ADD;
        wr.wr.atomic.remote_addr = remote_offset;
        wr.wr.atomic.compare_add = swap_val;
    } else {
        /* atomicMin/Max use CMP_SWAP with expected value 0 trick */
        wr.opcode = IBV_WR_ATOMIC_CMP_AND_SWAP;
        wr.wr.atomic.remote_addr = remote_offset;
        wr.wr.atomic.compare_add = 0;
        wr.wr.atomic.swap = swap_val;
    }

    sge.addr = (uintptr_t)node->vram_ptr;
    sge.length = sizeof(float);
    sge.lkey = node->mr->lkey;

    pthread_mutex_lock(&node->lock);

    if (ibv_post_send(qp, &wr, &bad_wr)) {
        fprintf(stderr, "cognimesh: ibv_post_send failed: %s\n", strerror(errno));
        pthread_mutex_unlock(&node->lock);
        return -1;
    }

    /* Wait for completion */
    int ne;
    do {
        ne = ibv_poll_cq(node->cq, 1, &wc);
    } while (ne == 0);

    pthread_mutex_unlock(&node->lock);

    if (ne < 0) {
        fprintf(stderr, "cognimesh: poll CQ error\n");
        return -1;
    }
    if (wc.status != IBV_WC_SUCCESS) {
        fprintf(stderr, "cognimesh: WC error: %s\n", ibv_wc_status_str(wc.status));
        return -1;
    }

    if (result) {
        memcpy(result, node->vram_ptr, sizeof(float));
    }

    return 0;
}

int cognimesh_atomic_add(CogniMeshNode *node, uint32_t remote_id,
                         uint64_t remote_offset, float value, float *result) {
    uint64_t val;
    memcpy(&val, &value, sizeof(float));
    return post_atomic(node, remote_id, remote_offset, val,
                      COGNIMESH_OP_ATOMIC_ADD, result);
}

int cognimesh_atomic_min(CogniMeshNode *node, uint32_t remote_id,
                         uint64_t remote_offset, float value, float *result) {
    uint64_t val;
    memcpy(&val, &value, sizeof(float));
    return post_atomic(node, remote_id, remote_offset, val,
                      COGNIMESH_OP_ATOMIC_MIN, result);
}

int cognimesh_atomic_max(CogniMeshNode *node, uint32_t remote_id,
                         uint64_t remote_offset, float value, float *result) {
    uint64_t val;
    memcpy(&val, &value, sizeof(float));
    return post_atomic(node, remote_id, remote_offset, val,
                      COGNIMESH_OP_ATOMIC_MAX, result);
}
