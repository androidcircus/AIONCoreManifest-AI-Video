/*
 * cogniforge_drm.h - NVIF ioctl definitions for CogniForge VX virtual GPU
 * Shared header between the kernel DRM driver and the user-space CUDA shim.
 */

#ifndef _COGNIFORGE_DRM_H
#define _COGNIFORGE_DRM_H

#include <linux/types.h>
#include <drm/drm.h>

/* PCI Device ID for CogniForge VX */
#define COGNIFORGE_VENDOR_ID    0x1D0F
#define COGNIFORGE_DEVICE_ID    0xC0DA

/* NVIF Protocol Definitions */
#define NVIF_CLASS_DEVICE          0x00000001
#define NVIF_CLASS_FIFO            0x00000002
#define NVIF_CLASS_GPU             0x00000003
#define NVIF_CLASS_MEM             0x00000004
#define NVIF_DEVICE_V0             0x00000001

/* NVIF ioctl commands */
#define NVIF_IOCTL_DEVICE_INFO     0x00000001
#define NVIF_IOCTL_ALLOC           0x00000002
#define NVIF_IOCTL_FREE            0x00000003
#define NVIF_IOCTL_MAP              0x00000004
#define NVIF_IOCTL_UNMAP            0x00000005
#define NVIF_IOCTL_READ             0x00000006
#define NVIF_IOCTL_WRITE            0x00000007
#define NVIF_IOCTL_EXEC             0x00000008
#define NVIF_IOCTL_QUERY            0x00000009

/* CogniForge-specific ioctl numbers */
#define DRM_COGNIFORGE_NVIF          0x00
#define DRM_COGNIFORGE_ALLOC_VRAM     0x01
#define DRM_COGNIFORGE_FREE_VRAM      0x02
#define DRM_COGNIFORGE_EXEC_MAUD      0x03
#define DRM_COGNIFORGE_RDMA_ATOMIC    0x04
#define DRM_COGNIFORGE_GET_METRICS    0x05

#define DRM_IOCTL_COGNIFORGE_NVIF \
    DRM_IOWR(DRM_COMMAND_BASE + DRM_COGNIFORGE_NVIF, struct drm_cogniforge_nvif)
#define DRM_IOCTL_COGNIFORGE_ALLOC_VRAM \
    DRM_IOWR(DRM_COMMAND_BASE + DRM_COGNIFORGE_ALLOC_VRAM, struct drm_cogniforge_vram_alloc)
#define DRM_IOCTL_COGNIFORGE_FREE_VRAM \
    DRM_IOW(DRM_COMMAND_BASE + DRM_COGNIFORGE_FREE_VRAM, struct drm_cogniforge_vram_free)
#define DRM_IOCTL_COGNIFORGE_EXEC_MAUD \
    DRM_IOW(DRM_COMMAND_BASE + DRM_COGNIFORGE_EXEC_MAUD, struct drm_cogniforge_exec_maud)
#define DRM_IOCTL_COGNIFORGE_RDMA_ATOMIC \
    DRM_IOWR(DRM_COMMAND_BASE + DRM_COGNIFORGE_RDMA_ATOMIC, struct drm_cogniforge_rdma_atomic)
#define DRM_IOCTL_COGNIFORGE_GET_METRICS \
    DRM_IOR(DRM_COMMAND_BASE + DRM_COGNIFORGE_GET_METRICS, struct drm_cogniforge_metrics)

struct drm_cogniforge_nvif {
    __u32 ioctl;
    __u32 handle;
    __u32 pad;
    __u32 size;
    __u64 data;
};

struct drm_cogniforge_vram_alloc {
    __u64 size;
    __u32 flags;
    __u32 pad;
    __u64 handle;
    __u64 offset;
};

struct drm_cogniforge_vram_free {
    __u64 handle;
};

struct drm_cogniforge_exec_maud {
    __u64 maud_handle;
    __u32 grid_dim_x, grid_dim_y, grid_dim_z;
    __u32 block_dim_x, block_dim_y, block_dim_z;
    __u32 shared_mem;
    __u32 num_args;
    __u64 args;
};

struct drm_cogniforge_rdma_atomic {
    __u64 remote_addr;
    __u64 local_handle;
    __u64 local_offset;
    __u32 op;
    __u32 dtype;
    __u64 result;
};

struct drm_cogniforge_metrics {
    __u32 sm_count;
    __u32 active_warps;
    __u32 tensor_tflops;
    __u32 mem_bandwidth;
    __u32 rdma_latency;
    __u32 pad;
};

/* BAR layout */
#define COGNIFORGE_BAR0_SIZE       (256 * 1024 * 1024)
#define COGNIFORGE_BAR1_SIZE       (2ULL * 1024 * 1024 * 1024 * 1024)

/* Doorbell register offsets within BAR0 */
#define COGNIFORGE_DOORBELL_EXEC   0x1000
#define COGNIFORGE_DOORBELL_RDMA   0x1008
#define COGNIFORGE_DOORBELL_IRQ    0x1010
#define COGNIFORGE_DOORBELL_FENCE  0x1018

#endif /* _COGNIFORGE_DRM_H */
