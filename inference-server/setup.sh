#!/bin/bash
set -euo pipefail

# CogniForge Virtual API - VM Setup Script
# Run this inside the VM (Ubuntu 24.04) to install dependencies
# and the CogniForge CUDA driver.

echo "=== CogniForge Virtual API Setup ==="

# 1. System packages
echo "Installing system dependencies..."
sudo apt update
sudo apt install -y python3 python3-pip ffmpeg libsvtav1enc-dev

# 2. Python packages
echo "Installing Python dependencies..."
pip3 install -r requirements.txt

# 3. CogniForge CUDA driver (copy from host mount)
DRIVER_SRC="/mnt/host-drivers"
DRIVER_DST="/usr/lib/x86_64-linux-gnu"

if [ -d "$DRIVER_SRC" ]; then
    echo "Installing CogniForge CUDA driver..."
    sudo cp ${DRIVER_SRC}/libcuda.so* ${DRIVER_DST}/
    sudo ldconfig
    echo "Driver installed."
else
    echo "WARNING: $DRIVER_SRC not found. CogniForge driver must be mounted from host."
    echo "  In QEMU, add: -virtfs local,path=/host/drivers,mount_tag=host-drivers..."
fi

# 4. Verify CUDA
echo "Verifying CUDA..."
python3 -c "
import torch
if torch.cuda.is_available():
    print(f'CUDA OK: {torch.cuda.device_count()} GPU(s)')
    for i in range(torch.cuda.device_count()):
        print(f'  GPU {i}: {torch.cuda.get_device_name(i)}')
else:
    print('CUDA not available. Check driver installation.')
"

# 5. Create output directory
OUTPUT_DIR="${OUTPUT_DIR:-/mnt/virtual_vram/outputs}"
mkdir -p "$OUTPUT_DIR"
echo "Output directory: $OUTPUT_DIR"

echo ""
echo "=== Setup complete. Start the server with: ==="
echo "  uvicorn virtual_api:app --host 0.0.0.0 --port 8000"
echo ""
echo "Or set VITE_VIRTUAL_API_URL=http://<this-vm-ip>:8000 in your frontend."
