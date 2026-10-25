# Any Civitai SDXL model — RunPod Serverless ComfyUI worker (SDXL · Pony · Illustrious · NoobAI checkpoints)
# Build on RunPod from your own PRIVATE copy of this repo (Dockerfile path = Dockerfile, build context = .).
# The build steps are downloaded from the original repo, so you never need to edit anything but these two lines.

# Cobalt Pear users: skip these two lines — the app's «Add your token» link puts both in a file civitai.env instead.
# >>> Put your Civitai API token here (civitai.com → Account settings → Security & Apps → API Keys). Keep your repo PRIVATE. <<<
ARG CIVITAI_TOKEN=PASTE_YOUR_CIVITAI_TOKEN_HERE
# >>> Put the model's Civitai page link here (or just its version number, e.g. 290640). <<<
ARG CIVITAI_MODEL=PASTE_THE_MODEL_LINK_HERE

FROM runpod/worker-comfyui:5.10.0-base
ARG CIVITAI_TOKEN
ARG CIVITAI_MODEL
COPY . /setup/
ADD https://github.com/cobaltpear/civitai-sdxl/releases/latest/download/build.sh /build.sh
RUN CIVITAI_TOKEN="$CIVITAI_TOKEN" CIVITAI_MODEL="$CIVITAI_MODEL" sh /build.sh && rm -rf /setup
ADD https://github.com/cobaltpear/civitai-sdxl/releases/latest/download/handler.py /handler.py
