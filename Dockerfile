# ---------------------------------------------------------------------------- #
#                         Stage 1: Download the models                         #
# ---------------------------------------------------------------------------- #
FROM alpine/git:2.43.0 as download

# NOTE: CivitAI usually requires an API token, so you need to add it in the header
#       of the wget command if you're using a model from CivitAI.
RUN apk add --no-cache wget && \
    wget -q -O /DreamShaper.safetensors "https://civitai.com/api/download/models/128713?type=Model&format=SafeTensor&size=pruned&fp=fp16" && \
    wget -q -O /3danime.safetensors "https://civitai.com/api/download/models/128046?type=Model&format=SafeTensor&size=pruned&fp=fp16" && \
    wget -q -O /XL.safetensors "https://civitai.com/api/download/models/354657?type=Model&format=SafeTensor&size=full&fp=fp16"

# ---------------------------------------------------------------------------- #
#                        Stage 2: Build the final image                        #
# ---------------------------------------------------------------------------- #
FROM python:3.10.14-slim as build_final_image

ARG A1111_RELEASE=v1.9.3

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    ROOT=/stable-diffusion-webui \
    PYTHONUNBUFFERED=1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && \
    apt install -y \
    fonts-dejavu-core rsync git jq moreutils aria2 wget libgoogle-perftools-dev libtcmalloc-minimal4 procps libgl1 libglib2.0-0 && \
    apt-get autoremove -y && rm -rf /var/lib/apt/lists/* && apt-get clean -y

RUN --mount=type=cache,target=/root/.cache/pip \
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git && \
    cd stable-diffusion-webui && \
    git reset --hard ${A1111_RELEASE} && \
    pip install xformers && \
    pip install -r requirements_versions.txt && \
    python -c "from launch import prepare_environment; prepare_environment()" --skip-torch-cuda-test

# Install ControlNet extension
RUN git clone --branch 1.1.436 https://github.com/Mikubill/sd-webui-controlnet.git /stable-diffusion-webui/extensions/sd-webui-controlnet

# Install Ultimate SD upscale extension (correct repo)
RUN git clone https://github.com/Coyote-A/ultimate-upscale-for-automatic1111.git /stable-diffusion-webui/extensions/ultimate-upscale-for-automatic1111

COPY --from=download /XL.safetensors /stable-diffusion-webui/models/Stable-diffusion/XL.safetensors
COPY --from=download /3danime.safetensors /stable-diffusion-webui/models/Stable-diffusion/3danime.safetensors
COPY --from=download /DreamShaper.safetensors /stable-diffusion-webui/models/Stable-diffusion/DreamShaper.safetensors

# Download ControlNet model for canny
RUN mkdir -p /stable-diffusion-webui/extensions/sd-webui-controlnet/models && \
    wget -O /stable-diffusion-webui/extensions/sd-webui-controlnet/models/control_v11p_sd15_canny.pth \
    https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/459bf90295ac305bc3ae8266e39a089f433eab4f/control_v11p_sd15_canny.pth

# Download IPAdapter model for ControlNet (ip-adapter-plus-face_sd15)
RUN wget -O /stable-diffusion-webui/extensions/sd-webui-controlnet/models/ip-adapter-plus-face_sd15.safetensors \
    https://huggingface.co/h94/IP-Adapter/resolve/main/models/ip-adapter-plus-face_sd15.safetensors

# Download IPAdapter CLIP-ViT-H model weights
RUN mkdir -p /stable-diffusion-webui/extensions/sd-webui-controlnet/models/clipvision && \
    wget -O /stable-diffusion-webui/extensions/sd-webui-controlnet/models/clipvision/clip_vit_h.safetensors \
    http://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors

# Download all LoRA models from the provided Google Drive folder
RUN apt-get update && \
    pip install gdown && \
    mkdir -p /stable-diffusion-webui/models/Lora && \
    gdown --folder "https://drive.google.com/drive/folders/1xGotF3_9tA7ojuFuuAk2xJ308_ytZSEI" -O /stable-diffusion-webui/models/Lora/

# install dependencies
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements.txt

COPY test_input.json .

ADD src .

RUN chmod +x /start.sh
CMD /start.sh