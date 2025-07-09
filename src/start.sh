#!/bin/bash

echo "✅ Worker Initiated"

# --- 1. In the background, start the A1111 WebUI API ---
echo "🚀 Starting WebUI API on Port 3000..."

TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"
export PYTHONUNBUFFERED=true

# Launch A1111 API as a background process (&)
# This uses the corrected arguments for A1111 v1.9.3
python /stable-diffusion-webui/webui.py \
    --xformers \
    --no-half-vae \
    --skip-python-version-check \
    --skip-torch-cuda-test \
    --skip-install \
    --opt-sdp-attention \
    --disable-safe-unpickle \
    --port 3000 \
    --api \
    --nowebui \
    --skip-version-check \
    --no-hashing \
    --no-download-sd-model \
    --ckpt-dir /runpod-volume/workspace/checkpoints \
    --lora-dir /runpod-volume/workspace/loras \
    --controlnet-dir /stable-diffusion-webui/extensions/sd-webui-controlnet \
    --vae-dir /runpod-volume/workspace/vae \
    --embeddings-dir /runpod-volume/workspace/embeddings &


# --- 2. In the foreground, start the RunPod Handler ---
echo "🎧 Starting RunPod Handler to listen for jobs..."
python -u /stable-diffusion-webui/handler.py