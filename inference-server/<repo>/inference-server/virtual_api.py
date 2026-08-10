cp src/server/virtual_api.py <repo>/inference-server/virtual_api.py
cd <repo>
pip install fastapi uvicorn "diffusers==0.32.2" transformers accelerate imageio imageio-ffmpeg pillow
