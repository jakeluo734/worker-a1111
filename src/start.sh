#!/usr/bin/env bash

echo "✅ Worker Initiated"

# --- 1. 在后台启动 A1111 WebUI API ---
echo "🚀 Starting WebUI API on Port 3000..."

# 使用 tcmalloc 进行内存优化
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"
export PYTHONUNBUFFERED=true

# 启动 A1111 API 作为一个后台进程 (&)
# 我们保留了你的大部分原始启动参数，并替换了模型加载部分
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
    --checkpoint-dir /network-volume/checkpoints \
    --lora-dir /network-volume/loras \
    --controlnet-models-path /network-volume/controlnet_models \
    --vae-dir /network-volume/vae \
    --embeddings-dir /network-volume/embeddings &


# --- 2. 在前台启动 RunPod Handler ---
echo "🎧 Starting RunPod Handler to listen for jobs..."

# 这个进程会接收 RunPod 的任务请求
# 注意：根据你的 Dockerfile，handler.py 最终的路径是 /stable-diffusion-webui/handler.py
python -u /stable-diffusion-webui/handler.py
