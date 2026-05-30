#!/usr/bin/env bash
set -euo pipefail

ACE_DIR="${ACE_DIR:-/opt/ACE-Step-1.5}"
SIDESTEP_DIR="${SIDESTEP_DIR:-/opt/Side-Step}"
PERSIST_DIR="${PERSIST_DIR:-/workspace}"
CHECKPOINTS_DIR="${CHECKPOINTS_DIR:-$PERSIST_DIR/checkpoints}"
THAI_COMPAT_CHECKPOINTS_DIR="${THAI_COMPAT_CHECKPOINTS_DIR:-$PERSIST_DIR/ACE-Step-1.5/checkpoints}"
REQUIRE_MODELS="${REQUIRE_MODELS:-0}"

fail() {
  echo "[FAIL] $*" >&2
  exit 65
}

warn() {
  echo "[WARN] $*" >&2
}

echo "== ACE-Step / Side-Step runtime verification =="
echo "ACE runtime:       $ACE_DIR"
echo "Side-Step runtime: $SIDESTEP_DIR"
echo "Persistent dir:    $PERSIST_DIR"
echo "Checkpoints:       $CHECKPOINTS_DIR"
echo ""

mkdir -p \
  "$PERSIST_DIR" \
  "$CHECKPOINTS_DIR" \
  "$PERSIST_DIR/datasets" \
  "$PERSIST_DIR/adapters" \
  "$PERSIST_DIR/outputs" \
  "$PERSIST_DIR/logs" \
  "$PERSIST_DIR/sidestep_tensors" \
  "$PERSIST_DIR/sidestep_outputs" \
  "$(dirname "$THAI_COMPAT_CHECKPOINTS_DIR")"
if [ -e "$THAI_COMPAT_CHECKPOINTS_DIR" ] && [ ! -L "$THAI_COMPAT_CHECKPOINTS_DIR" ]; then
  fail "$THAI_COMPAT_CHECKPOINTS_DIR exists but is not a symlink to $CHECKPOINTS_DIR"
fi
ln -sfn "$CHECKPOINTS_DIR" "$THAI_COMPAT_CHECKPOINTS_DIR"

df -T "$PERSIST_DIR" 2>/dev/null || warn "Could not inspect $PERSIST_DIR filesystem type."

case "$ACE_DIR" in
  "$PERSIST_DIR"/*) fail "ACE runtime is under persistent storage. Runtime code/venv must live on local/image disk." ;;
esac

case "$SIDESTEP_DIR" in
  "$PERSIST_DIR"/*) fail "Side-Step runtime is under persistent storage. Runtime code/venv must live on local/image disk." ;;
esac

test -d "$ACE_DIR/.git" || fail "Missing ACE-Step checkout at $ACE_DIR"
test -x "$ACE_DIR/.venv/bin/python" || fail "Missing ACE-Step venv at $ACE_DIR/.venv"
test -x "$ACE_DIR/.venv/bin/acestep" || fail "Missing ACE-Step executable at $ACE_DIR/.venv/bin/acestep"

test -L "$ACE_DIR/checkpoints" || fail "$ACE_DIR/checkpoints must be a symlink to $CHECKPOINTS_DIR"
resolved_checkpoints="$(readlink -f "$ACE_DIR/checkpoints")"
test "$resolved_checkpoints" = "$CHECKPOINTS_DIR" || fail "$ACE_DIR/checkpoints resolves to $resolved_checkpoints, expected $CHECKPOINTS_DIR"

test -L "$THAI_COMPAT_CHECKPOINTS_DIR" || fail "$THAI_COMPAT_CHECKPOINTS_DIR must be a symlink to $CHECKPOINTS_DIR"
resolved_thai_checkpoints="$(readlink -f "$THAI_COMPAT_CHECKPOINTS_DIR")"
test "$resolved_thai_checkpoints" = "$CHECKPOINTS_DIR" || fail "$THAI_COMPAT_CHECKPOINTS_DIR resolves to $resolved_thai_checkpoints, expected $CHECKPOINTS_DIR"

if [ -e "$PERSIST_DIR/ACE-Step-1.5/acestep" ]; then
  fail "$PERSIST_DIR/ACE-Step-1.5 contains executable ACE source. This can contaminate imports."
fi

if [ -e /root/ACE-Step-1.5/acestep ]; then
  fail "/root/ACE-Step-1.5 exists. Remove it so old scripts cannot generate against the wrong model code."
fi

if [ -d "$SIDESTEP_DIR" ]; then
  test -f "$SIDESTEP_DIR/train.py" || fail "Side-Step train.py missing at $SIDESTEP_DIR"
  test -x "$SIDESTEP_DIR/.venv/bin/python" || fail "Side-Step venv missing at $SIDESTEP_DIR/.venv"
  cd "$SIDESTEP_DIR"
  "$SIDESTEP_DIR/.venv/bin/python" - <<'PY'
import sidestep_engine
print("Side-Step import OK:", sidestep_engine.__file__)
PY
else
  warn "Side-Step checkout not found at $SIDESTEP_DIR. Generation-only pods may omit it."
fi

cd "$ACE_DIR"
"$ACE_DIR/.venv/bin/python" - <<'PY'
import importlib.util
from pathlib import Path
import torch

required = [
    "acestep",
    "acestep/audio_utils.py",
    "acestep/core/generation/handler/lora/controls.py",
    "acestep/training/dataset_builder_modules/preprocess_audio.py",
]
for item in required:
    if not Path(item).exists():
        raise SystemExit(f"Missing ACE runtime file: {item}")
missing = [name for name in ["torchao", "torchcodec", "nano_vllm"] if importlib.util.find_spec(name) is None]
if missing:
    raise SystemExit(f"Missing ACE official dependencies: {missing}")
if not torch.__version__.startswith("2.10.0"):
    raise SystemExit(f"ACE torch version is {torch.__version__}; expected 2.10.0+cu128")
print("ACE import path OK:", Path.cwd(), "torch", torch.__version__)
PY

if [ "$REQUIRE_MODELS" = "1" ]; then
  test -d "$CHECKPOINTS_DIR/acestep-v15-xl-sft" || fail "Missing $CHECKPOINTS_DIR/acestep-v15-xl-sft"
  test -d "$CHECKPOINTS_DIR/scragvae" || fail "Missing $CHECKPOINTS_DIR/scragvae"
  test -d "$CHECKPOINTS_DIR/acestep-5Hz-lm-0.6B" || fail "Missing $CHECKPOINTS_DIR/acestep-5Hz-lm-0.6B"

  canonical="$(readlink -f "$CHECKPOINTS_DIR/acestep-v15-xl-sft")"
  while IFS= read -r found; do
    resolved="$(readlink -f "$(dirname "$found")")"
    if [ "$resolved" != "$canonical" ]; then
      fail "Duplicate XL-SFT model implementation found at $found; canonical is $canonical"
    fi
  done < <(find /opt /workspace /root -path '*/acestep-v15-xl-sft/modeling_acestep_v15_xl_base.py' 2>/dev/null || true)
fi

echo "Runtime verification passed."
