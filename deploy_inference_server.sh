#!/bin/bash
set -euo pipefail

# Deploy the CogniForge Virtual API inference server to a VM.
# Usage: ./deploy_inference_server.sh <vm-ip> [vm-user]
#
# Prerequisites:
#   - SSH access to the VM
#   - CogniForge VX virtual GPU is configured on the VM
#   - libcuda.so is mounted at /mnt/host-drivers/

VM_IP="${1:?Usage: $0 <vm-ip> [vm-user]}"
VM_USER="${2:-ubuntu}"
REMOTE_DIR="/opt/cogniforge/inference-server"

echo "=== Deploying CogniForge Virtual API to ${VM_USER}@${VM_IP} ==="

# 1. Create directory
ssh "${VM_USER}@${VM_IP}" "sudo mkdir -p ${REMOTE_DIR} && sudo chown \$(whoami) ${REMOTE_DIR}"

# 2. Copy files
scp -r inference-server/* "${VM_USER}@${VM_IP}:${REMOTE_DIR}/"

# 3. Run setup
ssh "${VM_USER}@${VM_IP}" "cd ${REMOTE_DIR} && bash setup.sh"

# 4. Install systemd service
ssh "${VM_USER}@${VM_IP}" "
  sudo cp ${REMOTE_DIR}/cogniforge-api.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable cogniforge-api
  sudo systemctl start cogniforge-api
"

# 5. Verify
echo "=== Verifying deployment ==="
sleep 3
ssh "${VM_USER}@${VM_IP}" "curl -s http://localhost:8000/health | python3 -m json.tool"

echo ""
echo "=== Deployment complete ==="
echo "Virtual API is running at: http://${VM_IP}:8000"
echo ""
echo "Set this in your frontend .env:"
echo "  VITE_VIRTUAL_API_URL=http://${VM_IP}:8000"
echo ""
echo "Or export it before running the dev server:"
echo "  export VITE_VIRTUAL_API_URL=http://${VM_IP}:8000"
echo "  cd frontend && npm install && npm run dev"
