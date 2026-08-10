from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uuid, subprocess, json

app = FastAPI()

class VideoRequest(BaseModel):
    prompt: str
    resolution: str = "7680x4320"
    duration: int = 10
    steps: int = 100
    model: str = "cogniforge-sora2"

class VideoResponse(BaseModel):
    id: str
    status: str
    video_url: str

@app.post("/v1/video/generate")
async def generate_video(req: VideoRequest):
    job_id = str(uuid.uuid4())
    cmd = f"ssh vm-0 'cd /opt/cogniforge && python3 generate.py'"
    spec = json.dumps(req.model_dump())
    subprocess.Popen(cmd, stdin=subprocess.PIPE).communicate(input=spec.encode())
    return VideoResponse(id=job_id, status="processing", video_url=f"https://rack.pimaster.org/output/{job_id}.mp4")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
