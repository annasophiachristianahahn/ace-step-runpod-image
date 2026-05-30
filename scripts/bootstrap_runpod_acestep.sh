#!/usr/bin/env bash
set -euo pipefail

ACE_DIR="${ACE_DIR:-/opt/ACE-Step-1.5}"
ACE_REPO_URL="${ACE_REPO_URL:-https://github.com/ACE-Step/ACE-Step-1.5.git}"
PERSIST_DIR="${PERSIST_DIR:-/workspace}"
CHECKPOINTS_DIR="${CHECKPOINTS_DIR:-$PERSIST_DIR/checkpoints}"
THAI_COMPAT_ACE_DIR="${THAI_COMPAT_ACE_DIR:-$PERSIST_DIR/ACE-Step-1.5}"
THAI_COMPAT_CHECKPOINTS_DIR="${THAI_COMPAT_CHECKPOINTS_DIR:-$THAI_COMPAT_ACE_DIR/checkpoints}"

# Apt mirrors have been unreliable on RunPod; avoid them unless explicitly asked.
if [ "${ACE_BOOTSTRAP_USE_APT:-0}" = "1" ]; then
  apt-get update
  apt-get install -y git curl tmux ca-certificates
fi

if ! test -x "$HOME/.local/bin/uv"; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"
export UV_CACHE_DIR="${UV_CACHE_DIR:-/opt/.uv-cache}"

mkdir -p /opt "$PERSIST_DIR" "$CHECKPOINTS_DIR" "$PERSIST_DIR/datasets" "$PERSIST_DIR/adapters" "$PERSIST_DIR/outputs" "$PERSIST_DIR/logs" "$PERSIST_DIR/sidestep_tensors" "$PERSIST_DIR/sidestep_outputs" /tmp/ace-trainer
workspace_type="$(df -T "$PERSIST_DIR" 2>/dev/null | awk 'NR==2 {print $2}' || true)"
echo "Persistent workspace filesystem: ${workspace_type:-unknown}"
if [ -e "$PERSIST_DIR/ACE-Step-1.5/acestep" ]; then
  echo "Refusing to use $PERSIST_DIR/ACE-Step-1.5 as executable runtime."
  echo "$PERSIST_DIR is for durable weights, datasets, adapters, and logs only."
  exit 64
fi
if [ -e "$ACE_DIR" ] && ! test -d "$ACE_DIR/.git"; then
  mv "$ACE_DIR" "$ACE_DIR.broken.$(date -u +%Y%m%dT%H%M%SZ)"
fi
if ! test -d "$ACE_DIR/.git"; then
  git clone --depth 1 "$ACE_REPO_URL" "$ACE_DIR"
fi

cd "$ACE_DIR"
if [ -n "${ACE_REF:-}" ]; then
  git checkout "$ACE_REF"
fi
if [ "${ACE_BOOTSTRAP_UPDATE:-0}" = "1" ]; then
  git pull --ff-only
fi
python3 - <<'PY'
from pathlib import Path
import re

path = Path("pyproject.toml")
text = path.read_text()
text = re.sub(
    r"required-environments\s*=\s*\[[^\]]+\]",
    'required-environments = [ "sys_platform == \'linux\' and platform_machine == \'x86_64\'" ]',
    text,
    count=1,
)
text = re.sub(r",?\s*\{\s*url\s*=\s*\"[^\"]*win_amd64[^\"]*\"[^}]*\}", "", text)
text = re.sub(r",?\s*\"flash-attn[^\"]*\"", "", text)
text = re.sub(r",?\s*\{\s*url\s*=\s*\"[^\"]*flash-attention[^\"]*\"[^}]*\}", "", text)
text = text.replace("[ ,", "[").replace(", ]", " ]")
path.write_text(text)

nano = Path("acestep/third_parts/nano-vllm/pyproject.toml")
if nano.exists():
    text = nano.read_text()
    text = re.sub(r",?\s*\"flash-attn[^\"]*\"", "", text)
    text = re.sub(r",?\s*\{\s*url\s*=\s*\"[^\"]*flash-attention[^\"]*\"[^}]*\}", "", text)
    text = text.replace("[ ,", "[").replace(", ]", " ]")
    nano.write_text(text)
PY
if test -x .venv/bin/python && ! .venv/bin/python - <<'PY'
import importlib.util
import torch

required = ["torchao", "torchcodec", "nano_vllm"]
missing = [name for name in required if importlib.util.find_spec(name) is None]
if not torch.__version__.startswith("2.10.0"):
    raise SystemExit(f"wrong torch version: {torch.__version__}")
if missing:
    raise SystemExit(f"missing required packages: {missing}")
print("ACE official dependency check passed:", torch.__version__)
PY
then
  echo "Existing ACE-Step venv is not official/current; rebuilding it."
  rm -rf .venv
fi
if [ -e checkpoints ] && [ ! -L checkpoints ]; then
  if find checkpoints -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    cp -a checkpoints/. "$CHECKPOINTS_DIR"/
  fi
  rm -rf checkpoints
fi
ln -sfn "$CHECKPOINTS_DIR" checkpoints
mkdir -p "$THAI_COMPAT_ACE_DIR"
if [ -e "$THAI_COMPAT_CHECKPOINTS_DIR" ] && [ ! -L "$THAI_COMPAT_CHECKPOINTS_DIR" ]; then
  rm -rf "$THAI_COMPAT_CHECKPOINTS_DIR"
fi
ln -sfn "$CHECKPOINTS_DIR" "$THAI_COMPAT_CHECKPOINTS_DIR"
if ! test -x .venv/bin/acestep; then
  echo "ACE-Step runtime missing; installing official uv environment under local /opt."
  uv sync --no-dev
else
  echo "Reusing existing ACE-Step runtime: $ACE_DIR"
fi

uv run --no-sync python - <<'PY'
from pathlib import Path

controls = Path("acestep/core/generation/handler/lora/controls.py")
text = controls.read_text()
text = text.replace("Set LoRA scale (0-1).", "Set LoRA scale (0-2).")
text = text.replace("Set LoRA scale (0–1).", "Set LoRA scale (0–2).")
text = text.replace("between 0 and 1.", "between 0 and 2.")
text = text.replace("scale_value = max(0.0, min(1.0, scale_value))", "scale_value = max(0.0, min(2.0, scale_value))")
controls.write_text(text)

ui = Path("acestep/ui/gradio/interfaces/generation_advanced_primary_controls.py")
text = ui.read_text().replace("maximum=1.0,", "maximum=2.0,")
ui.write_text(text)
PY

"$ACE_DIR/.venv/bin/python" - <<'PY'
from pathlib import Path

for path in [
    "acestep",
    "acestep/audio_utils.py",
    "acestep/core/generation/handler/lora/controls.py",
    "acestep/training/dataset_builder_modules/preprocess_audio.py",
]:
    if not Path(path).exists():
        raise SystemExit(f"Missing runtime file: {path}")
print("ACE runtime verification passed.")
PY

echo "ACE-Step bootstrap complete: $ACE_DIR"
echo "Persistent checkpoints: $CHECKPOINTS_DIR"
echo "Thai-compatible checkpoints: $THAI_COMPAT_CHECKPOINTS_DIR"
git rev-parse HEAD > "$ACE_DIR/.image_git_revision" 2>/dev/null || true
