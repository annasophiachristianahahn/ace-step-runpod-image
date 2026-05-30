#!/usr/bin/env bash
set -euo pipefail

ACE_DIR="${ACE_DIR:-/opt/ACE-Step-1.5}"
GRADIO_PORT="${GRADIO_PORT:-7860}"

if test -x /usr/local/bin/verify_runpod_runtime.sh; then
  REQUIRE_MODELS=1 /usr/local/bin/verify_runpod_runtime.sh
else
  echo "Missing /usr/local/bin/verify_runpod_runtime.sh" >&2
  exit 65
fi

if ! command -v tmux >/dev/null 2>&1; then
  apt-get update
  apt-get install -y tmux
fi

cd "$ACE_DIR"
tmux kill-session -t acestep_smoke 2>/dev/null || true
tmux new-session -d -s acestep_smoke \
  "PATH=\$HOME/.local/bin:\$PATH CHECK_UPDATE=false uv run --no-sync acestep --port $GRADIO_PORT --server-name 0.0.0.0 --language en --config_path acestep-v15-xl-sft --lm_model_path acestep-5Hz-lm-0.6B --init_llm true --init_service true --enable-api > /tmp/acestep-smoke.log 2>&1"

echo "Started ACE-Step smoke server on port $GRADIO_PORT."
echo "Logs: /tmp/acestep-smoke.log"
