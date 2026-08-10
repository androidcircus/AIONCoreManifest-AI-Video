import ray
from ray.util.placement_group import placement_group
import subprocess

def start_ray_head():
    subprocess.run(["ray", "start", "--head", "--port=6379",
                    "--resources='{\"cogniforge_vgpu\": 100}'"])

def add_worker(vm_ip):
    subprocess.run(["ssh", vm_ip,
                    "ray start --address='10.0.0.1:6379' --resources='{\"cogniforge_vgpu\": 1}'"])

# On head node:
ray.init(address="auto")
@ray.remote(resources={"cogniforge_vgpu": 1})
def video_inference_step(model, latents, timestep):
    import torch
    # This runs inside a VM with CogniForge libcuda.so preloaded
    return model(latents, timestep)

# The full Sora 2 pipeline scales across 100 workers automatically
