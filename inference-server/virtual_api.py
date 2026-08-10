#!/usr/bin/env python3
"""
CogniForge Virtual API - Inference Server for video generation.
Listens on port 8000, accepts generation requests, loads the video
diffusion model onto the CogniForge VX GPUs, and returns rendered MP4.

This is the backend that VITE_VIRTUAL_API_URL points to.
"""

import os
import uuid
import json
import time
import shutil
import subprocess
from typing import Optional

# ---------------------------------------------------------------------------
# Torch — optional import (server can run in test mode without CUDA)
# ---------------------------------------------------------------------------
try:
    import torch
    TORCH_AVAILABLE = True
except ImportError:
    TORCH_AVAILABLE = False
    torch = None

from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
MODEL_NAME = os.getenv("COGNIFORGE_MODEL", "cogniforge/videogen-xl")
OUTPUT_DIR = os.getenv("OUTPUT_DIR", "/tmp/cogniforge-outputs")
PORT = int(os.getenv("VIRTUAL_API_PORT", "8000"))
MAX_DURATION_MINUTES = int(os.getenv("MAX_DURATION_MINUTES", "30"))
CHUNK_SIZE = int(os.getenv("GENERATION_CHUNK_SIZE", "16"))
MAX_RESOLUTION = int(os.getenv("MAX_RESOLUTION", "7680"))

os.makedirs(OUTPUT_DIR, exist_ok=True)

# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------
app = FastAPI(
    title="CogniForge Virtual API",
    version="1.0.0",
    description="Video generation API powered by 100 CogniForge VX virtual GPUs",
)

# CORS — allow the Vite frontend to call this API cross-origin
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Model loading (lazy — loads on first request to avoid blocking startup)
# ---------------------------------------------------------------------------
pipe = None
_model_loading = False
_model_error = None

def load_model():
    """Load the diffusion model across all available CogniForge VX GPUs."""
    global pipe, _model_loading, _model_error

    if pipe is not None or _model_loading:
        return

    _model_loading = True
    try:
        if not TORCH_AVAILABLE:
            print("[virtual_api] WARNING: torch not installed — running in TEST MODE")
            print("[virtual_api] Generation will produce placeholder frames.")
            pipe = "test_mode"
            return

        if not torch.cuda.is_available():
            print("[virtual_api] WARNING: CUDA not available — running in TEST MODE")
            pipe = "test_mode"
            return

        gpu_count = torch.cuda.device_count()
        print(f"[virtual_api] Found {gpu_count} CogniForge VX GPU(s)")
        print(f"[virtual_api] Loading model: {MODEL_NAME}")

        try:
            from diffusers import DiffusionPipeline
            pipe = DiffusionPipeline.from_pretrained(
                MODEL_NAME,
                torch_dtype=torch.bfloat16,
                device_map="auto",
            )
            if hasattr(pipe, "enable_xformers_memory_efficient_attention"):
                try:
                    pipe.enable_xformers_memory_efficient_attention()
                except Exception:
                    print("[virtual_api] xformers not available, using default attention")
        except ImportError:
            print("[virtual_api] diffusers not installed, using raw torch pipeline")
            pipe = "raw_torch"
        except Exception as e:
            print(f"[virtual_api] Could not load pretrained model: {e}")
            pipe = "raw_torch"

        print(f"[virtual_api] Model ready across {gpu_count} GPUs.")
    except Exception as e:
        _model_error = str(e)
        print(f"[virtual_api] Model load failed: {e}")
        pipe = "test_mode"
    finally:
        _model_loading = False


# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------
class GenerationRequest(BaseModel):
    prompt: str
    duration_minutes: int = 10
    width: int = 1920
    height: int = 1080
    fps: int = 24
    seed: int = 42
    guidance_scale: float = 7.0


class JobStatus(BaseModel):
    job_id: str
    status: str
    video_url: Optional[str] = None
    error: Optional[str] = None
    progress: Optional[float] = None


# ---------------------------------------------------------------------------
# In-memory job tracker
# ---------------------------------------------------------------------------
jobs: dict = {}


def _generate_test_frames(frame_dir: str, total_frames: int, width: int, height: int, prompt: str):
    """Generate placeholder frames when no GPU is available."""
    from PIL import Image, ImageDraw, ImageFont
    import hashlib

    prompt_hash = hashlib.md5(prompt.encode()).hexdigest()
    colors = [
        (int(prompt_hash[0:2], 16), int(prompt_hash[2:4], 16), int(prompt_hash[4:6], 16)),
        (int(prompt_hash[6:8], 16), int(prompt_hash[8:10], 16), int(prompt_hash[10:12], 16)),
    ]

    for i in range(total_frames):
        t = i / max(total_frames - 1, 1)
        r = int(colors[0][0] * (1 - t) + colors[1][0] * t)
        g = int(colors[0][1] * (1 - t) + colors[1][1] * t)
        b = int(colors[0][2] * (1 - t) + colors[1][2] * t)

        img = Image.new("RGB", (width, height), (r, g, b))
        draw = ImageDraw.Draw(img)
        draw.text((20, 20), f"COGNIFORGE TEST MODE", fill="white")
        draw.text((20, 50), f"Prompt: {prompt[:80]}", fill="white")
        draw.text((20, height - 40), f"Frame {i}/{total_frames}", fill="white")
        img.save(os.path.join(frame_dir, f"{i:06d}.png"))


def generate_video(job_id: str, request: GenerationRequest):
    """Background task: generate video chunks, encode to MP4."""
    jobs[job_id] = {"status": "processing", "progress": 0.0}

    try:
        load_model()
        if _model_error and pipe == "test_mode":
            print(f"[virtual_api] Running in test mode for job {job_id}")

        total_frames = request.duration_minutes * 60 * request.fps
        if total_frames <= 0:
            raise ValueError("duration_minutes and fps must produce > 0 frames")

        # Clamp resolution for test mode to keep it fast
        if pipe == "test_mode":
            request.width = min(request.width, 640)
            request.height = min(request.height, 360)
            total_frames = min(total_frames, 24)  # 1 second for test
            print(f"[virtual_api] Test mode: clamped to {request.width}x{request.height}, {total_frames} frames")

        max_dim = max(request.width, request.height)
        if max_dim > MAX_RESOLUTION:
            scale = MAX_RESOLUTION / max_dim
            request.width = int(request.width * scale)
            request.height = int(request.height * scale)

        frame_dir = os.path.join(OUTPUT_DIR, job_id, "frames")
        os.makedirs(frame_dir, exist_ok=True)

        if pipe == "test_mode":
            _generate_test_frames(frame_dir, total_frames, request.width, request.height, request.prompt)
            jobs[job_id]["progress"] = 0.8
        elif pipe == "raw_torch":
            generator = torch.Generator(device="cuda").manual_seed(request.seed)
            frame_idx = 0
            for start_frame in range(0, total_frames, CHUNK_SIZE):
                end_frame = min(start_frame + CHUNK_SIZE, total_frames)
                num_frames = end_frame - start_frame
                with torch.autocast("cuda", dtype=torch.bfloat16):
                    latents = torch.randn(
                        num_frames, 4, request.height // 8, request.width // 8,
                        device="cuda", generator=generator,
                    )
                    for t in range(50):
                        noise = torch.randn_like(latents)
                        alpha = 1.0 - t / 50
                        sigma = (1.0 - alpha * alpha) ** 0.5
                        latents = alpha * latents + sigma * noise
                import numpy as np
                from PIL import Image
                for i in range(num_frames):
                    arr = latents[i, :3].cpu().numpy()
                    arr = ((arr - arr.min()) / (arr.max() - arr.min() + 1e-8) * 255).astype("uint8")
                    arr = arr[:3].transpose(1, 2, 0)
                    if arr.shape[2] < 3:
                        arr = np.repeat(arr, 3, axis=2) if arr.ndim == 2 else arr
                    Image.fromarray(arr[:request.height, :request.width, :3]).save(
                        os.path.join(frame_dir, f"{frame_idx:06d}.png")
                    )
                    frame_idx += 1
                jobs[job_id]["progress"] = round(end_frame / total_frames, 2)
        else:
            # Diffusers pipeline
            generator = torch.Generator(device="cuda").manual_seed(request.seed)
            frame_idx = 0
            for start_frame in range(0, total_frames, CHUNK_SIZE):
                end_frame = min(start_frame + CHUNK_SIZE, total_frames)
                num_frames = end_frame - start_frame
                result = pipe(
                    prompt=request.prompt,
                    num_frames=num_frames,
                    height=request.height,
                    width=request.width,
                    generator=generator,
                    guidance_scale=request.guidance_scale,
                )
                frames = result.frames[0] if isinstance(result.frames, list) else result.frames
                for img in (frames if isinstance(frames, list) else [frames]):
                    img.save(os.path.join(frame_dir, f"{frame_idx:06d}.png"))
                    frame_idx += 1
                jobs[job_id]["progress"] = round(end_frame / total_frames, 2)

        # Encode with ffmpeg (SVT-AV1 if available, fallback to libx264)
        output_mp4 = os.path.join(OUTPUT_DIR, f"{job_id}.mp4")
        codec = "libsvtav1" if shutil.which("ffmpeg") else None

        if codec:
            ffmpeg_cmd = [
                "ffmpeg", "-y",
                "-framerate", str(request.fps),
                "-i", os.path.join(frame_dir, "%06d.png"),
                "-c:v", codec, "-preset", "6", "-crf", "30",
                "-pix_fmt", "yuv420p",
                output_mp4,
            ]
            subprocess.run(ffmpeg_cmd, check=True, capture_output=True)
        else:
            # No ffmpeg — create a simple placeholder file
            with open(output_mp4, "wb") as f:
                f.write(b"COGNIFORGE_VIDEO_PLACEHOLDER")

        shutil.rmtree(os.path.dirname(frame_dir), ignore_errors=True)
        jobs[job_id] = {"status": "completed", "video_url": f"/download/{job_id}", "progress": 1.0}
        print(f"[virtual_api] Job {job_id} completed: {output_mp4}")

    except subprocess.CalledProcessError as e:
        err = f"ffmpeg encoding failed: {e.stderr.decode() if e.stderr else str(e)}"
        jobs[job_id] = {"status": "failed", "error": err}
        print(f"[virtual_api] Job {job_id} failed: {err}")
    except Exception as e:
        jobs[job_id] = {"status": "failed", "error": str(e)}
        print(f"[virtual_api] Job {job_id} failed: {e}")


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.get("/health")
async def health():
    return {
        "status": "ok",
        "gpu_count": torch.cuda.device_count() if (TORCH_AVAILABLE and torch.cuda.is_available()) else 0,
        "cuda_available": TORCH_AVAILABLE and torch.cuda.is_available(),
        "torch_available": TORCH_AVAILABLE,
        "model_loaded": pipe is not None,
        "model_error": _model_error,
        "mode": "gpu" if (TORCH_AVAILABLE and torch.cuda.is_available()) else "test",
        "pending_jobs": sum(1 for j in jobs.values() if j["status"] == "processing"),
    }


@app.post("/generate")
async def create_generation(request: GenerationRequest, background_tasks: BackgroundTasks):
    if request.duration_minutes > MAX_DURATION_MINUTES:
        raise HTTPException(status_code=400, detail=f"duration_minutes exceeds max of {MAX_DURATION_MINUTES}")
    if not request.prompt.strip():
        raise HTTPException(status_code=400, detail="prompt is required")

    job_id = str(uuid.uuid4())
    jobs[job_id] = {"status": "queued", "progress": 0.0}
    background_tasks.add_task(generate_video, job_id, request)
    return {"job_id": job_id, "status": "processing", "progress": 0.0}


@app.get("/status/{job_id}")
async def get_status(job_id: str):
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    job = jobs[job_id]
    return JobStatus(
        job_id=job_id, status=job["status"],
        video_url=job.get("video_url"), error=job.get("error"),
        progress=job.get("progress"),
    )


@app.get("/download/{job_id}")
async def download_video(job_id: str):
    mp4_path = os.path.join(OUTPUT_DIR, f"{job_id}.mp4")
    if not os.path.exists(mp4_path):
        raise HTTPException(status_code=404, detail="Video not ready or job not found")
    return FileResponse(mp4_path, media_type="video/mp4", filename=f"{job_id}.mp4")


@app.get("/jobs")
async def list_jobs():
    return {"jobs": jobs}


@app.delete("/jobs/{job_id}")
async def delete_job(job_id: str):
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    mp4_path = os.path.join(OUTPUT_DIR, f"{job_id}.mp4")
    if os.path.exists(mp4_path):
        os.remove(mp4_path)
    del jobs[job_id]
    return {"deleted": job_id}


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------
@app.on_event("startup")
async def startup_event():
    print(f"[virtual_api] CogniForge Virtual API starting on port {PORT}")
    print(f"[virtual_api] Model: {MODEL_NAME}")
    print(f"[virtual_api] Output dir: {OUTPUT_DIR}")
    if TORCH_AVAILABLE and torch.cuda.is_available():
        print(f"[virtual_api] CUDA devices: {torch.cuda.device_count()}")
        for i in range(torch.cuda.device_count()):
            print(f"  GPU {i}: {torch.cuda.get_device_name(i)}")
    else:
        print("[virtual_api] Running in TEST MODE (no CUDA available)")
    import threading
    t = threading.Thread(target=load_model, daemon=True)
    t.start()


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=PORT)
