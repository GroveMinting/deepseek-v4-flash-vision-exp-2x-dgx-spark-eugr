#!/usr/bin/env bash
# One-command setup and launch wrapper for the installed eugr integration.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="$ROOT/tools/deepseek-v4-vision-versions.lock"
if [[ ! -f "$LOCK_FILE" ]]; then
  LOCK_FILE="$ROOT/VERSIONS.lock"
fi
if [[ ! -f "$LOCK_FILE" ]]; then
  echo "ERROR: version lock not found" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$LOCK_FILE"

SETUP=false
BASE_PROFILE=false
BUILD_ONLY=false
DOWNLOAD_ONLY=false
FORCE_BUILD=false
DRY_RUN=false
CONFIG_FILE="$ROOT/.env"
PASSTHROUGH=()

usage() {
  cat <<'USAGE'
Usage: ./run-deepseek-v4-vision.sh [WRAPPER OPTIONS] [EUGR OPTIONS]

Wrapper options:
  --setup          Discover if needed, prepare image and model, then launch.
  --base           Use the diagnostic non-DSpark recipe.
  --build-only     Build/copy the pinned runtime and exit.
  --download-only  Download/copy the pinned model and exit.
  --force-build    Rebuild the runtime even if its local image exists.
  --config FILE    Use a specific eugr cluster configuration.
  --dry-run        Print setup commands and dry-run the eugr recipe.
  -h, --help       Show this help.

Other options are passed to run-recipe.sh, including -d, -n, --port,
--gpu-mem, --max-model-len, and arguments following --.
USAGE
}

print_command() {
  printf '  '
  printf '%q ' "$@"
  printf '\n'
}

while (($#)); do
  case "$1" in
    --setup) SETUP=true ;;
    --base) BASE_PROFILE=true ;;
    --build-only) BUILD_ONLY=true ;;
    --download-only) DOWNLOAD_ONLY=true ;;
    --force-build) FORCE_BUILD=true ;;
    --dry-run) DRY_RUN=true ;;
    --config)
      CONFIG_FILE="${2:?--config requires a value}"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    --)
      PASSTHROUGH+=("$1")
      shift
      while (($#)); do PASSTHROUGH+=("$1"); shift; done
      break
      ;;
    *) PASSTHROUGH+=("$1") ;;
  esac
  shift
done

if [[ "$BUILD_ONLY" == true && "$DOWNLOAD_ONLY" == true ]]; then
  echo "ERROR: --build-only and --download-only cannot be combined" >&2
  exit 2
fi
if [[ ! -x "$ROOT/run-recipe.sh" || ! -f "$ROOT/run-recipe.py" ]]; then
  echo "ERROR: this wrapper must be installed in an eugr spark-vllm-docker checkout." >&2
  echo "Run: bash install.sh /path/to/spark-vllm-docker" >&2
  exit 1
fi
for path in \
  "$ROOT/tools/deepseek-v4-vision-build.sh" \
  "$ROOT/tools/deepseek-v4-vision-download.sh"; do
  if [[ ! -x "$path" ]]; then
    echo "ERROR: required installed tool is missing or not executable: $path" >&2
    exit 1
  fi
done

needs_setup=false
if [[ "$SETUP" == true || "$BUILD_ONLY" == true || "$DOWNLOAD_ONLY" == true || "$FORCE_BUILD" == true ]]; then
  needs_setup=true
fi

if [[ "$needs_setup" == true && ! -f "$CONFIG_FILE" ]]; then
  echo "Cluster configuration not found: $CONFIG_FILE"
  if [[ "$DRY_RUN" == true ]]; then
    echo "Would run eugr cluster discovery:"
    print_command "$ROOT/run-recipe.sh" --discover --config "$CONFIG_FILE"
  else
    "$ROOT/run-recipe.sh" --discover --config "$CONFIG_FILE"
  fi
fi

if [[ "$DRY_RUN" == true && ! -f "$CONFIG_FILE" ]]; then
  has_nodes=false
  for argument in "${PASSTHROUGH[@]}"; do
    if [[ "$argument" == "-n" || "$argument" == "--nodes" ]]; then
      has_nodes=true
      break
    fi
  done
  if [[ "$has_nodes" == false ]]; then
    echo "Using synthetic nodes for side-effect-free recipe validation."
    PASSTHROUGH+=(-n 127.0.0.1,127.0.0.2)
  fi
fi

copy_args=(-c --copy-parallel --config "$CONFIG_FILE")

if [[ "$SETUP" == true || "$BUILD_ONLY" == true || "$FORCE_BUILD" == true ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    echo "Would prepare and distribute runtime image $IMAGE_TAG:"
    print_command "$ROOT/tools/deepseek-v4-vision-build.sh" "${copy_args[@]}"
  elif [[ "$FORCE_BUILD" == true ]] || ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    "$ROOT/tools/deepseek-v4-vision-build.sh" "${copy_args[@]}"
  else
    echo "Runtime image $IMAGE_TAG already exists locally; checking worker copies."
    "$ROOT/build-and-copy.sh" --no-build -t "$IMAGE_TAG" "${copy_args[@]}"
  fi
fi

if [[ "$BUILD_ONLY" == true ]]; then
  echo "Runtime image preparation complete."
  exit 0
fi

if [[ "$SETUP" == true || "$DOWNLOAD_ONLY" == true ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    echo "Would download and distribute $MODEL_ID@$MODEL_REVISION:"
    print_command "$ROOT/tools/deepseek-v4-vision-download.sh" "${copy_args[@]}"
  else
    "$ROOT/tools/deepseek-v4-vision-download.sh" "${copy_args[@]}"
  fi
fi

if [[ "$DOWNLOAD_ONLY" == true ]]; then
  echo "Pinned model preparation complete."
  exit 0
fi

if [[ "$BASE_PROFILE" == true ]]; then
  RECIPE="deepseek-v4-flash-vision-exp-base-fp8"
else
  RECIPE="deepseek-v4-flash-vision-exp-dspark-fp8"
fi

run_args=("$RECIPE")
if [[ -f "$CONFIG_FILE" ]]; then
  run_args+=(--config "$CONFIG_FILE")
fi
run_args+=("${PASSTHROUGH[@]}")
if [[ "$DRY_RUN" == true ]]; then
  run_args+=(--dry-run)
fi

echo "Launching through eugr recipe: $RECIPE"
exec "$ROOT/run-recipe.sh" "${run_args[@]}"
