# ---------------------------------------------------------------------------- #
#                      Build the final image                                   #
# ---------------------------------------------------------------------------- #
FROM python:3.10.14-slim as build_final_image

ARG A1111_RELEASE=v1.9.3

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    ROOT=/stable-diffusion-webui \
    PYTHONUNBUFFERED=1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install base dependencies
RUN apt-get update && \
    apt install -y \
    fonts-dejavu-core rsync git jq moreutils aria2 wget libgoogle-perftools-dev libtcmalloc-minimal4 procps libgl1 libglib2.0-0 && \
    apt-get autoremove -y && rm -rf /var/lib/apt/lists/* && apt-get clean -y

# Clone A1111 and install dependencies in separate, clearer steps
RUN git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
WORKDIR /stable-diffusion-webui
RUN git reset --hard ${A1111_RELEASE}

# Install Python packages
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install xformers && \
    pip install -r requirements_versions.txt && \
    python -c "from launch import prepare_environment; prepare_environment()" --skip-torch-cuda-test

# Install ControlNet Extension
RUN git clone https://github.com/Mikubill/sd-webui-controlnet.git extensions/sd-webui-controlnet && \
    cd extensions/sd-webui-controlnet && \
    git checkout 1.1.436 && \
    rm -rf .git

# Set working directory
WORKDIR /stable-diffusion-webui

# Install handler dependencies
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements.txt

# Add handler source code and make start script executable
COPY test_input.json .
ADD src .
RUN chmod +x /stable-diffusion-webui/start.sh

# Set the entrypoint to the start script
CMD ["/stable-diffusion-webui/start.sh"]
