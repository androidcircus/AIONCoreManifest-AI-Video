#!/usr/bin/env python3
"""
pimaster_gateway.py – CogniForge VX ↔ PiMaster.org Integration Gateway
Accepts AI video generation jobs from PiMaster, dispatches to the
100‑virtual‑GPU CogniForge fabric, and returns completed videos.
Dr. Fei‑Fei Li, AI Lab.

Usage:
   python3 pimaster_gateway.py --api-key YOUR_PIMASTER_KEY --gpu-count 100
"""

import os
import sys
import json
import time
import uuid
import threading
import subprocess
import requests
from flask import Flask, request, jsonify
from queue import Queue
import torch

# ------------------------------------------------------------
#  PiMaster API Configuration
# ------------------------------------------------------------
PIMASTER_API_BASE = "https://www.pimaster.org/api/v1"
PIMASTER_API_KEY = None
CLUSTER_ID = "cogniforge-rack-01"

# ------------------------------------------------------------
#  Flask app for PiMaster webhook callbacks
# ------------------------------------------------------------
app = Flask(__name__)
job_queue = Queue()

# ------------------------------------------------------------
#  GPU Fabric Interface (local VMs with CogniForge)
# ------------------------------------------------------------
class CogniForgeFabric:
    """
    Interface to the 100 virtual GPUs. Since each VM has a full CUDA stack
    via our libcuda.so shim, we can SSH into any VM and run PyTorch directly.
    """
    def __init__(self, vm_ips_file="vm_ips.txt"):
        self.vms = []
        with open(vm_ips_file) as f:
            for line in f:
                self.vms.append(line.strip())
        self.current_vm = 0  # round-robin

    def execute_job(self, job_spec):
        """Launch a video generation job on one of the virtual GPUs."""
        vm = self.vms[self.current_vm % len(self.vms)]
        self.current_vm += 1

        # Build the command to run inside the VM
        cmd = f"ssh {vm} 'cd /opt/cogniforge && python3 run_model.py'"
        # Pass job parameters via stdin or a temporary file
        proc = subprocess.Popen(cmd, shell=True, stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, stderr = proc.communicate(input=json.dumps(job_spec).encode())
        if proc.returncode != 0:
            raise RuntimeError(f"Job failed on {vm}: {stderr.decode()}")
        result = json.loads(stdout.decode())
        return result  # contains video URL

# ------------------------------------------------------------
#  PiMaster Integration: register cluster, receive jobs, upload results
# ------------------------------------------------------------
def register_cluster():
    """Register this CogniForge rack with PiMaster as a custom compute provider."""
    payload = {
        "cluster_id": CLUSTER_ID,
        "name": "CogniForge VX Rack",
        "total_gpus": 100,
        "total_vram_tb": 200,
        "api_endpoint": f"http://{get_public_ip()}:5000/job_callback",
        "capabilities": ["video-generation", "8k", "diffusion-models"]
    }
    headers = {"Authorization": f"Bearer {PIMASTER_API_KEY}"}
    r = requests.post(f"{PIMASTER_API_BASE}/providers/register", json=payload, headers=headers)
    if r.status_code == 200:
        print("Cluster registered successfully with PiMaster.org")
    else:
        print(f"Registration failed: {r.text}")

def get_public_ip():
    return requests.get("https://api.ipify.org").text.strip()

# ------------------------------------------------------------
#  Job processing worker
# ------------------------------------------------------------
def job_worker(fabric):
    while True:
        job = job_queue.get()
        if job is None:
            break
        try:
            # 1. Notify PiMaster that job started
            requests.post(f"{PIMASTER_API_BASE}/jobs/{job['id']}/status",
                          json={"status": "running"}, 
                          headers={"Authorization": f"Bearer {PIMASTER_API_KEY}"})

            # 2. Execute on virtual GPU
            result = fabric.execute_job(job["spec"])

            # 3. Upload resulting video to PiMaster
            video_url = result["video_url"]
            requests.post(f"{PIMASTER_API_BASE}/jobs/{job['id']}/result",
                          json={"video_url": video_url, "duration": result["duration"]},
                          headers={"Authorization": f"Bearer {PIMASTER_API_KEY}"})

            print(f"Job {job['id']} completed. Video: {video_url}")
        except Exception as e:
            print(f"Job {job['id']} failed: {e}")
            requests.post(f"{PIMASTER_API_BASE}/jobs/{job['id']}/status",
                          json={"status": "failed", "error": str(e)},
                          headers={"Authorization": f"Bearer {PIMASTER_API_KEY}"})

# ------------------------------------------------------------
#  Flask endpoints: PiMaster calls these
# ------------------------------------------------------------
@app.route('/job_callback', methods=['POST'])
def job_callback():
    """Receive a new job from PiMaster."""
    data = request.json
    job_id = data.get("job_id")
    spec = data.get("spec")  # model, resolution, steps, etc.
    job_queue.put({"id": job_id, "spec": spec})
    return jsonify({"status": "accepted"})

@app.route('/status', methods=['GET'])
def status():
    return jsonify({"cluster": CLUSTER_ID, "queue_depth": job_queue.qsize()})

# ------------------------------------------------------------
#  Main
# ------------------------------------------------------------
def main():
    global PIMASTER_API_KEY
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--gpu-count", type=int, default=100)
    args = parser.parse_args()
    PIMASTER_API_KEY = args.api_key

    fabric = CogniForgeFabric()
    register_cluster()

    # Start worker threads
    workers = []
    for _ in range(4):
        t = threading.Thread(target=job_worker, args=(fabric,))
        t.daemon = True
        t.start()
        workers.append(t)

    # Start Flask server to receive jobs
    app.run(host="0.0.0.0", port=5000)

if __name__ == "__main__":
    main()
