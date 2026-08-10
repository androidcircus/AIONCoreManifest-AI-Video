/*
 * cognimesh_init.c - CogniMesh fabric initialization.
 * Sets up InfiniBand context, protection domain, memory region,
 * completion queue, and queue pairs for inter-VM communication.
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>
#include "cognimesh.h"

int cognimesh_init(CogniMeshNode *node, uint32_t node_id, const char *ib_dev_name) {
    memset(node, 0, sizeof(CogniMeshNode));
    node->node_id = node_id;
    node->num_qps = COGNIMESH_MAX_NODES;
    pthread_mutex_init(&node->lock, NULL);

    /* Open InfiniBand device */
    struct ibv_device **dev_list;
    struct ibv_device *dev = NULL;

    dev_list = ibv_get_device_list(NULL);
    if (!dev_list) {
        fprintf(stderr, "cognimesh: no IB devices found\n");
        return -1;
    }

    if (ib_dev_name) {
        for (int i = 0; dev_list[i]; i++) {
            if (strcmp(ibv_get_device_name(dev_list[i]), ib_dev_name) == 0) {
                dev = dev_list[i];
                break;
            }
        }
    } else {
        dev = dev_list[0];  /* use first available */
    }

    if (!dev) {
        fprintf(stderr, "cognimesh: IB device not found\n");
        ibv_free_device_list(dev_list);
        return -1;
    }

    node->ib_ctx = ibv_open_device(dev);
    ibv_free_device_list(dev_list);
    if (!node->ib_ctx) {
        fprintf(stderr, "cognimesh: failed to open IB device\n");
        return -1;
    }

    /* Allocate protection domain */
    node->pd = ibv_alloc_pd(node->ib_ctx);
    if (!node->pd) {
        fprintf(stderr, "cognimesh: ibv_alloc_pd failed\n");
        goto err_close;
    }

    /* Allocate VRAM memory region */
    node->vram_size = COGNIMESH_MAX_MR_SIZE;
    /* In production: use huge pages or memfd for 2TB VRAM */
    node->vram_ptr = calloc(1, 4096);  /* placeholder: real impl uses mmap */
    if (!node->vram_ptr) {
        fprintf(stderr, "cognimesh: VRAM alloc failed\n");
        goto err_pd;
    }

    /* Register memory region */
    node->mr = ibv_reg_mr(node->pd, node->vram_ptr, 4096,
                          IBV_ACCESS_LOCAL_WRITE |
                          IBV_ACCESS_REMOTE_WRITE |
                          IBV_ACCESS_REMOTE_ATOMIC);
    if (!node->mr) {
        fprintf(stderr, "cognimesh: ibv_reg_mr failed\n");
        goto err_vram;
    }

    /* Create completion queue */
    node->cq = ibv_create_cq(node->ib_ctx, 1024, NULL, NULL, 0);
    if (!node->cq) {
        fprintf(stderr, "cognimesh: ibv_create_cq failed\n");
        goto err_mr;
    }

    /* Allocate QP array */
    node->qps = calloc(node->num_qps, sizeof(struct ibv_qp *));
    if (!node->qps) {
        fprintf(stderr, "cognimesh: QP alloc failed\n");
        goto err_cq;
    }

    /* Create QPs (one per potential remote node) */
    struct ibv_qp_init_attr qp_attr = {
        .send_cq = node->cq,
        .recv_cq = node->cq,
        .qp_type = IBV_QPT_RC,
        .cap = { .max_send_wr = 256, .max_recv_wr = 256,
                 .max_send_sge = 1, .max_recv_sge = 1 },
    };

    for (uint32_t i = 0; i < node->num_qps; i++) {
        node->qps[i] = ibv_create_qp(node->pd, &qp_attr);
        if (!node->qps[i]) {
            fprintf(stderr, "cognimesh: QP %u creation failed\n", i);
            break;
        }
    }

    printf("cognimesh: initialized node %u on %s\n", node_id, ibv_get_device_name(dev));
    return 0;

err_cq:
    ibv_destroy_cq(node->cq);
err_mr:
    ibv_dereg_mr(node->mr);
err_vram:
    free(node->vram_ptr);
err_pd:
    ibv_dealloc_pd(node->pd);
err_close:
    ibv_close_device(node->ib_ctx);
    return -1;
}

int cognimesh_connect(CogniMeshNode *node, uint32_t remote_id, const char *remote_addr) {
    /* In full implementation: exchange QP info via out-of-band channel
     * (e.g. TCP socket) and modify QP state to RTR/RTS.
     * This requires RDMA CM or manual QP state transitions. */
    printf("cognimesh: connecting node %u -> %s (remote_id=%u)\n",
           node->node_id, remote_addr, remote_id);
    /* TODO: ibv_modify_qp to INIT -> RTR -> RTS */
    return 0;
}

void cognimesh_shutdown(CogniMeshNode *node) {
    if (node->qps) {
        for (uint32_t i = 0; i < node->num_qps; i++) {
            if (node->qps[i]) ibv_destroy_qp(node->qps[i]);
        }
        free(node->qps);
    }
    if (node->cq) ibv_destroy_cq(node->cq);
    if (node->mr) ibv_dereg_mr(node->mr);
    if (node->vram_ptr) free(node->vram_ptr);
    if (node->pd) ibv_dealloc_pd(node->pd);
    if (node->ib_ctx) ibv_close_device(node->ib_ctx);
    pthread_mutex_destroy(&node->lock);
}
