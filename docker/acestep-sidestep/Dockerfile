# syntax=docker/dockerfile:1.7
FROM runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04

ARG ACE_REPO_URL=https://github.com/ACE-Step/ACE-Step-1.5.git
ARG ACE_REF=dce621408bee8c31b4fcf4811682eb9359e1bc94
ARG SIDESTEP_REPO_URL=https://github.com/koda-dernet/Side-Step.git
ARG SIDESTEP_REF=ecd13bdd1a1e7189582c032f875d5b90efdc77d5

ENV DEBIAN_FRONTEND=noninteractive \
    ACE_DIR=/opt/ACE-Step-1.5 \
    SIDESTEP_DIR=/opt/Side-Step \
    PERSIST_DIR=/workspace \
    CHECKPOINTS_DIR=/workspace/checkpoints \
    UV_CACHE_DIR=/opt/.uv-cache \
    PATH=/root/.local/bin:/opt/ACE-Step-1.5/.venv/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      libsndfile1 \
      rsync \
      tmux \
      ffmpeg \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

COPY scripts/bootstrap_runpod_acestep.sh /usr/local/bin/bootstrap_runpod_acestep.sh
COPY scripts/verify_runpod_runtime.sh /usr/local/bin/verify_runpod_runtime.sh
COPY scripts/runpod_runtime_smoke_test.sh /usr/local/bin/runpod_runtime_smoke_test.sh
RUN chmod +x \
      /usr/local/bin/bootstrap_runpod_acestep.sh \
      /usr/local/bin/verify_runpod_runtime.sh \
      /usr/local/bin/runpod_runtime_smoke_test.sh

RUN ACE_REPO_URL="$ACE_REPO_URL" ACE_REF="$ACE_REF" ACE_DIR="$ACE_DIR" PERSIST_DIR="$PERSIST_DIR" CHECKPOINTS_DIR="$CHECKPOINTS_DIR" \
    /usr/local/bin/bootstrap_runpod_acestep.sh \
    && rm -rf "$UV_CACHE_DIR"

RUN git clone "$SIDESTEP_REPO_URL" "$SIDESTEP_DIR" \
    && cd "$SIDESTEP_DIR" \
    && git checkout "$SIDESTEP_REF"

RUN cd "$SIDESTEP_DIR" \
    && python3 <<'PY'
from pathlib import Path
import re

path = Path("pyproject.toml")
text = path.read_text()
text = re.sub(r'(?ms)^\s*flash-attn\s*=\s*\[\n.*?^\s*\]\n', '', text)
text = re.sub(r'(?m)^\s*"flash-attn[^"]*",\n?', '', text)
text = re.sub(r'(?ms)^\s*\{\s*url\s*=\s*"[^"]*flash-attention[^"]*"[^}]*\},?\n?', '', text)
text = re.sub(r"\[\s*,", "[", text)
text = re.sub(r",\s*\]", "]", text)
path.write_text(text)
PY

RUN cd "$SIDESTEP_DIR" \
    && uv pip install --python "$ACE_DIR/.venv/bin/python" -e . \
    && uv pip install --python "$ACE_DIR/.venv/bin/python" "$ACE_DIR/acestep/third_parts/nano-vllm" \
    && ln -sfn "$ACE_DIR/.venv" "$SIDESTEP_DIR/.venv" \
    && "$SIDESTEP_DIR/.venv/bin/python" -c "import sidestep_engine; print('Side-Step installed:', sidestep_engine.__file__)" \
    && rm -rf "$UV_CACHE_DIR" \
    && git rev-parse HEAD > /opt/Side-Step/.image_git_revision

RUN /usr/local/bin/verify_runpod_runtime.sh

WORKDIR /workspace
