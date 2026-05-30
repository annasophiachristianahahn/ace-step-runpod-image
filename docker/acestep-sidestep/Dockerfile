FROM runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04

ARG ACE_REPO_URL=https://github.com/ACE-Step/ACE-Step-1.5.git
ARG ACE_REF=6c1b2ef130bb7a7705a2abc61c11a258202b9ed2
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
    /usr/local/bin/bootstrap_runpod_acestep.sh

RUN git clone "$SIDESTEP_REPO_URL" "$SIDESTEP_DIR" \
    && cd "$SIDESTEP_DIR" \
    && git checkout "$SIDESTEP_REF" \
    && python3 -c "from pathlib import Path; import re; p=Path('pyproject.toml'); t=p.read_text(); t=re.sub(r',?\\s*\\{\\s*url\\s*=\\s*\\\"[^\\\"]*win_amd64[^\\\"]*\\\"[^}]*\\}', '', t); t=re.sub(r',?\\s*\\\"flash-attn[^\\\"]*\\\"', '', t); t=re.sub(r',?\\s*\\{\\s*url\\s*=\\s*\\\"[^\\\"]*flash-attention[^\\\"]*\\\"[^}]*\\}', '', t); t=t.replace('[ ,', '[').replace(', ]', ' ]'); p.write_text(t)" \
    && uv sync --no-dev \
    && uv run --no-sync python -c "import sidestep_engine; print('Side-Step installed:', sidestep_engine.__file__)" \
    && git rev-parse HEAD > /opt/Side-Step/.image_git_revision

RUN /usr/local/bin/verify_runpod_runtime.sh

WORKDIR /workspace
