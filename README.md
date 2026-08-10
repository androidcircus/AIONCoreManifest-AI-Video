# CogniForge VX - AION Core Manifest AI Video

A virtual GPU system for AI video generation built on KVM/QEMU. CogniForge VX
presents a 2 TB VRAM, 256 SM virtual GPU to guest VMs via a QEMU PCI device,
with a Linux DRM kernel driver, user-space CUDA shim, and an InfiniBand-based
CogniMesh fabric for cross-VM RDMA atomic operations.

## Architecture

```
[Guest VM]
  |-- libcuda.so (CUDA Driver API shim)
  |-- cogniforge_drm.ko (Linux kernel DRM driver)
  |-- /dev/dri/cogniforge (NVIF ioctl interface)
        |
  [QEMU Host Process]
  |-- cogniforge-vx (QEMU PCI device: BAR0=control, BAR1=2TB VRAM)
  |-- sm-emulator (256 virtual SMs, MAUD binary execution)
  |-- tensor-jit (AVX-512/BF16 kernel JIT for tensor ops)
  |-- pisa_compiler (LLVM NVVM IR -> MAUD binary)
  |
  [CogniMesh Fabric]
  |-- InfiniBand RDMA atomicAdd/atomicMin/atomicMax
  |-- 100-node mesh for distributed gradient accumulation
```

## Components

| Directory | Description |
|-----------|-------------|
| `compiler/` | pisa_compiler - converts CUDA NVVM IR to MAUD binary |
| `qemu-device/` | QEMU PCI device for CogniForge VX |
| `sm-emulator/` | Virtual streaming multiprocessor with MAUD execution |
| `tensor-jit/` | AVX-512/BF16 micro-kernel JIT generator |
| `cognimesh/` | InfiniBand RDMA mesh for inter-VM atomic ops |
| `drivers/linux/` | Linux DRM kernel driver (NVIF protocol) |
| `drivers/user/` | User-space CUDA Driver API shim |
| `kernel/` | CUDA diffusion kernel for video generation |
| `vulkan-icd/` | Vulkan ICD manifest for CogniForge backend |
| `integration/` | Kubernetes, Ray, Prometheus, OpenAI-compat API |
| `rack-blueprint/` | Physical rack build guide |

## Build

```bash
# Install dependencies
pip install -r requirements.txt

# Build all C/C++ components
make all

# Compile CUDA kernel to MAUD binary
make maud-compile

# Build QEMU with CogniForge device
cp qemu-device/cogniforge-vx.c $QEMU_SRC/hw/display/
cd $QEMU_SRC && ./configure --target-list=x86_64-softmmu && make -j$(nproc)
```

## Deploy

```bash
# Create base VM image
# (see deploy_manifest.sh for packaging)

# Start the OpenAI-compatible API server
python3 integration/openai-compat/server.py

# Start the PiMaster gateway
python3 integration/pimaster_gateway.py --api-key YOUR_KEY --gpu-count 100

# Start Ray cluster
python3 integration/ray/cogniforge_ray_cluster.py
```

## License

See LICENSE file.

## Inference Server (Virtual API)

The CogniForge Virtual API is a FastAPI server that runs on a VM with
access to the CogniForge VX virtual GPU. It loads a video diffusion model
across all 100 virtual GPUs and serves generation requests.

### Deploy

```bash
# Deploy to a VM
./deploy_inference_server.sh <vm-ip> [vm-user]

# Or manually inside the VM:
cd inference-server
bash setup.sh
uvicorn virtual_api:app --host 0.0.0.0 --port 8000
```

### API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | GPU count, CUDA status, model state |
| POST | `/generate` | Start a video generation job |
| GET | `/status/{job_id}` | Poll job status and progress |
| GET | `/download/{job_id}` | Download completed MP4 |
| GET | `/jobs` | List all jobs |
| DELETE | `/jobs/{job_id}` | Delete a job and its video |

### Frontend Integration

```bash
# In frontend/.env
VITE_VIRTUAL_API_URL=http://<vm-ip>:8000

# Install and run
cd frontend
npm install
npm run dev
```

The frontend polls `/status/{job_id}` and displays a progress bar while
the 100-GPU distributed inference generates and encodes the video.
