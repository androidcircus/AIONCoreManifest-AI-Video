/*
 * cogniforge-vx.c - QEMU PCI Device for CogniForge VX Virtual GPU
 * 2 TB VRAM, 256 SMs, InfiniBand CogniMesh fabric.
 */

#include "qemu/osdep.h"
#include "hw/pci/pci.h"
#include "hw/pci/pci_device.h"
#include "qemu/module.h"
#include "qemu/timer.h"
#include "qapi/error.h"
#include "exec/memory.h"
#include "qom/object.h"

#define TYPE_COGNIFORGE_VX "cogniforge-vx"
OBJECT_DECLARE_SIMPLE_TYPE(CogniForgeVXState, COGNIFORGE_VX)

#define COGNIFORGE_VENDOR_ID   0x1D0F
#define COGNIFORGE_DEVICE_ID   0xC0DA
#define BAR0_SIZE   (256 * 1024 * 1024)
#define BAR1_SIZE   (2ULL << 40)
#define SM_COUNT    256
#define MAX_WARPS   32

typedef struct CogniForgeSM {
    uint32_t active_warps;
    uint64_t pc;
    uint32_t warp_pcs[MAX_WARPS];
    uint8_t  warp_active[MAX_WARPS];
} CogniForgeSM;

struct CogniForgeVXState {
    PCIDevice parent_obj;
    MemoryRegion bar0;
    MemoryRegion bar1;
    CogniForgeSM sms[SM_COUNT];
    uint64_t vram_size;
    uint32_t sm_count;
    uint32_t doorbell_exec;
    uint32_t doorbell_rdma;
    uint32_t doorbell_irq;
    uint64_t doorbell_fence;
    uint64_t maud_binary_addr;
    uint32_t maud_binary_size;
};

static uint64_t cogniforge_bar0_read(void *opaque, hwaddr addr, unsigned size)
{
    CogniForgeVXState *s = opaque;
    switch (addr) {
    case 0x0000: return (COGNIFORGE_DEVICE_ID << 16) | COGNIFORGE_VENDOR_ID;
    case 0x0008: return s->sm_count;
    case 0x0010: return (uint32_t)(s->vram_size & 0xFFFFFFFF);
    case 0x0014: return (uint32_t)(s->vram_size >> 32);
    case 0x1000: return s->doorbell_exec;
    case 0x1008: return s->doorbell_rdma;
    case 0x1010: return s->doorbell_irq;
    case 0x1018: return s->doorbell_fence;
    default: return 0;
    }
}

static void cogniforge_bar0_write(void *opaque, hwaddr addr, uint64_t val, unsigned size)
{
    CogniForgeVXState *s = opaque;
    switch (addr) {
    case 0x1000: s->doorbell_exec = (uint32_t)val; break;
    case 0x1008: s->doorbell_rdma = (uint32_t)val; break;
    case 0x1010: s->doorbell_irq = (uint32_t)val; break;
    case 0x1018: s->doorbell_fence = val; break;
    case 0x2000: s->maud_binary_addr = val; break;
    case 0x2008: s->maud_binary_size = (uint32_t)val; break;
    default: break;
    }
}

static const MemoryRegionOps cogniforge_bar0_ops = {
    .read  = cogniforge_bar0_read,
    .write = cogniforge_bar0_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
    .valid = { .min_access_size = 4, .max_access_size = 8 },
};

static void cogniforge_vx_realize(PCIDevice *dev, Error **errp)
{
    CogniForgeVXState *s = COGNIFORGE_VX(dev);
    s->sm_count = SM_COUNT;
    s->vram_size = BAR1_SIZE;
    for (int i = 0; i < SM_COUNT; i++) {
        s->sms[i].active_warps = 0;
        s->sms[i].pc = 0;
    }
    memory_region_init_io(&s->bar0, OBJECT(s), &cogniforge_bar0_ops,
                          s, "cogniforge-bar0", BAR0_SIZE);
    pci_register_bar(dev, 0, PCI_BASE_ADDRESS_SPACE_MEMORY, &s->bar0);
    memory_region_init_ram(&s->bar1, OBJECT(s), "cogniforge-vram",
                           s->vram_size, errp);
    if (*errp) return;
    pci_register_bar(dev, 1, PCI_BASE_ADDRESS_SPACE_MEMORY |
                     PCI_BASE_ADDRESS_MEM_TYPE_64, &s->bar1);
}

static void cogniforge_vx_reset(DeviceState *dev)
{
    CogniForgeVXState *s = COGNIFORGE_VX(dev);
    s->doorbell_exec = s->doorbell_rdma = s->doorbell_irq = 0;
    s->doorbell_fence = 0;
    for (int i = 0; i < SM_COUNT; i++) {
        s->sms[i].active_warps = 0;
        s->sms[i].pc = 0;
    }
}

static void cogniforge_vx_class_init(ObjectClass *klass, void *data)
{
    DeviceClass *dc = DEVICE_CLASS(klass);
    PCIDeviceClass *k = PCI_DEVICE_CLASS(klass);
    k->realize = cogniforge_vx_realize;
    k->vendor_id = COGNIFORGE_VENDOR_ID;
    k->device_id = COGNIFORGE_DEVICE_ID;
    k->class_id = PCI_CLASS_DISPLAY_VGA;
    dc->reset = cogniforge_vx_reset;
    dc->desc = "CogniForge VX Virtual GPU (2 TB VRAM, 256 SMs)";
    set_bit(DEVICE_CATEGORY_MISC, dc->categories);
}

static const TypeInfo cogniforge_vx_info = {
    .name          = TYPE_COGNIFORGE_VX,
    .parent        = TYPE_PCI_DEVICE,
    .instance_size = sizeof(CogniForgeVXState),
    .class_init    = cogniforge_vx_class_init,
    .interfaces    = (InterfaceInfo[]) {
        { INTERFACE_CONVENTIONAL_PCI_DEVICE },
        { },
    },
};

static void cogniforge_vx_register_types(void)
{
    type_register_static(&cogniforge_vx_info);
}

type_init(cogniforge_vx_register_types);
