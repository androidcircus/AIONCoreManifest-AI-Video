# CogniForge VX Rack Build Guide

## Overview

This document describes the physical rack configuration for a 100-node
CogniForge VX deployment. Each node runs a KVM virtual machine with a
CogniForge VX virtual GPU (2 TB VRAM, 256 SMs) backed by the QEMU PCI
device and SM emulator.

## Rack Configuration

### Nodes (10 racks x 10 nodes = 100 VMs)

| Component | Specification |
|-----------|--------------|
| CPU       | 2x AMD EPYC 9654 (96 cores, 384 threads) |
| Memory    | 2 TB DDR5 ECC per node |
| Storage   | 4x 7.68TB NVMe SSD (U.2) in RAID 0 |
| Network   | Mellanox ConnectX-7 400Gb/s InfiniBand |
| GPU       | None required (CogniForge VX is fully virtual) |
| NIC       | 2x 100GbE for management + storage |

### Network Topology

```
[100 VMs] --InfiniBand--> [CogniMesh Fabric]
                          |
                    [InfiniBand Switch]
                     (400Gb/s, HDR)
                          |
                   [10 Racks x 10 Nodes]
                          |
                    [Management Network]
                     (100GbE, L2)
```

### Power

- Per node: ~1200W (CPU + memory + NVMe + IB)
- Per rack (10 nodes + switch): ~13kW
- Total: ~130kW across 10 racks
- UPS: 150kVA minimum, with 10-minute runtime

### Cabling

- InfiniBand: HDR (400Gb/s) per node, aggregated to HDR switch
- Management: 100GbE DAC cables
- Power: PDU per rack, dual-feed A/B

### BOM (Bill of Materials)

| Item | Qty | Part Number |
|------|-----|-------------|
| AMD EPYC 9654 | 200 | 100-000000803 |
| 64GB DDR5 ECC | 3200 | M393A8G40AB2 |
| 7.68TB NVMe U.2 | 400 | Micron 7450 |
| ConnectX-7 400Gb IB | 100 | MCX75310 |
| HDR IB Switch 40-port | 10 | NVIDIA SB7800 |
| 48-port 100GbE switch | 10 | Any L3 switch |
| 1U server chassis (2-socket) | 100 | Supermicro AS-2124BT-HNTR |

## Deployment Steps

1. Install Ubuntu 24.04 LTS on all nodes
2. Install KVM + QEMU with CogniForge VX device support
3. Configure InfiniBand: `ibstat`, set port to HDR
4. Load kernel module: `modprobe cogniforge_drm`
5. Deploy KubeVirt + device plugin
6. Start Ray cluster: `ray start --head --resources='{"cogniforge_vgpu": 100}'`
7. Deploy PiMaster gateway
8. Verify: `virsh list --all`, `ray status`, `ibstat`
