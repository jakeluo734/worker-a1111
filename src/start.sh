#!/bin/bash

echo "✅ Worker Initiated"

echo "🔗 Symlinking files from Network Volume"
rm -rf /workspace && \
  ln -s /runpod-volume /workspace

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
    --ckpt-dir /workspace/checkpoints \
    --lora-dir /workspace/loras \
    --controlnet-dir /stable-diffusion-webui/extensions/sd-webui-controlnet \
    --vae-dir /workspace/vae \
    --embeddings-dir /workspace/embeddings &


# --- 2. In the foreground, start the RunPod Handler ---
echo "🎧 Starting RunPod Handler to listen for jobs..."
python -u /stable-diffusion-webui/handler.py