#!/usr/bin/env bash
# Download the pinned model revision and optionally copy its HF cache to workers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/deepseek-v4-vision-versions.lock" ]]; then
  LOCK_FILE="$SCRIPT_DIR/deepseek-v4-vision-versions.lock"
else
  LOCK_FILE="$SCRIPT_DIR/../VERSIONS.lock"
fi
if [[ ! -f "$LOCK_FILE" ]]; then
  echo "ERROR: version lock not found: $LOCK_FILE" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$LOCK_FILE"

TARGET_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$TARGET_ROOT/.env"
SSH_USER="$USER"
COPY_REQUESTED=false
COPY_PARALLEL=false
HOSTS=()

usage() {
  cat <<'USAGE'
Usage: deepseek-v4-vision-download.sh [OPTIONS]
  -c, --copy-to [hosts]  Copy to comma-separated hosts; defaults to COPY_HOSTS.
      --copy-parallel    Copy to workers concurrently.
  -u, --user USER        Remote SSH user.
      --config FILE      eugr .env containing COPY_HOSTS.
      --print-pins       Print model identity without downloading.
  -h, --help             Show this help.
USAGE
}

add_hosts() {
  local token part
  for token in "$@"; do
    IFS=',' read -ra parts <<< "$token"
    for part in "${parts[@]}"; do
      part="${part//[[:space:]]/}"
      [[ -z "$part" ]] || HOSTS+=("$part")
    done
  done
}

while (($#)); do
  case "$1" in
    -c|--copy-to)
      COPY_REQUESTED=true
      shift
      while (($#)) && [[ "$1" != -* ]]; do
        add_hosts "$1"
        shift
      done
      continue
      ;;
    --copy-parallel) COPY_PARALLEL=true ;;
    -u|--user) SSH_USER="${2:?--user requires a value}"; shift ;;
    --config) CONFIG_FILE="${2:?--config requires a value}"; shift ;;
    --print-pins)
      printf 'model=%s\nrevision=%s\n' "$MODEL_ID" "$MODEL_REVISION"
      exit 0
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

for command in uvx python3; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "ERROR: required command is unavailable: $command" >&2
    exit 1
  }
done

if [[ "$COPY_REQUESTED" == true && "${#HOSTS[@]}" -eq 0 ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: no copy hosts supplied and config not found: $CONFIG_FILE" >&2
    exit 1
  fi
  copy_hosts="$(python3 - "$CONFIG_FILE" <<'PY'
from pathlib import Path
import re
import sys

value = ""
for raw in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    match = re.match(r"^(?:export\s+)?COPY_HOSTS\s*=\s*(.*)$", line)
    if match:
        value = match.group(1).strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        break
print(value)
PY
)"
  if [[ -z "$copy_hosts" ]]; then
    echo "ERROR: COPY_HOSTS is empty in $CONFIG_FILE" >&2
    exit 1
  fi
  add_hosts "$copy_hosts"
fi

if [[ "$COPY_REQUESTED" == true ]]; then
  for command in rsync ssh; do
    command -v "$command" >/dev/null 2>&1 || {
      echo "ERROR: required copy command is unavailable: $command" >&2
      exit 1
    }
  done
fi

HUB_PATH="${HF_HOME:-$HOME/.cache/huggingface}/hub"
REMOTE_HUB_PATH="${REMOTE_HF_HOME:-$HUB_PATH}"
MODEL_ORG="${MODEL_ID%%/*}"
MODEL_NAME="${MODEL_ID#*/}"
MODEL_DIR="$HUB_PATH/models--$MODEL_ORG--$MODEL_NAME"

echo "Downloading $MODEL_ID@$MODEL_REVISION"
uvx hf download "$MODEL_ID" --revision "$MODEL_REVISION"

SNAPSHOT="$MODEL_DIR/snapshots/$MODEL_REVISION"
python3 - "$SNAPSHOT" <<'PY'
from pathlib import Path
import sys

snapshot = Path(sys.argv[1])
if not (snapshot / "model.safetensors.index.json").is_file():
    raise SystemExit(f"pinned snapshot is incomplete: {snapshot}")
shards = sorted(snapshot.glob("model-*-of-00048.safetensors"))
if len(shards) != 48:
    raise SystemExit(f"expected 48 SafeTensors shards, found {len(shards)}")
print(f"Verified pinned snapshot: {snapshot} ({len(shards)} shards)")
PY

copy_one() {
  local host="$1"
  echo "Copying pinned Hugging Face repository cache to $SSH_USER@$host"
  rsync -a --mkpath --info=progress2 "$MODEL_DIR" \
    "$SSH_USER@$host:$REMOTE_HUB_PATH/"
}

if [[ "$COPY_REQUESTED" == true ]]; then
  if [[ "$COPY_PARALLEL" == true ]]; then
    pids=()
    for host in "${HOSTS[@]}"; do
      copy_one "$host" &
      pids+=("$!")
    done
    failed=0
    for pid in "${pids[@]}"; do
      wait "$pid" || failed=1
    done
    [[ "$failed" -eq 0 ]] || { echo "ERROR: one or more model copies failed" >&2; exit 1; }
  else
    for host in "${HOSTS[@]}"; do
      copy_one "$host"
    done
  fi
else
  echo "No copy requested; pinned model remains on this node."
fi
