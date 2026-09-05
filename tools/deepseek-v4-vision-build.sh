#!/usr/bin/env bash
# Reproducibly build the native Vision runtime without modifying the user's eugr checkout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CALLER_PWD="$PWD"
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
IMAGE_TAG="${DSV4FV_IMAGE_TAG:-$IMAGE_TAG}"
PREPARE_ONLY=false

if [[ "${1:-}" == "--print-pins" ]]; then
  printf 'eugr=%s\nvllm=%s@%s\nb12x=%s\nimage=%s\n' \
    "$EUGR_COMMIT" "$VLLM_REPO" "$VLLM_COMMIT" "$B12X_COMMIT" "$IMAGE_TAG"
  exit 0
fi
if [[ "${1:-}" == "--prepare-only" ]]; then
  PREPARE_ONLY=true
  shift
fi

required_commands=(git python3)
if [[ "$PREPARE_ONLY" == false ]]; then
  required_commands+=(docker)
fi
for command in "${required_commands[@]}"; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "ERROR: required command is unavailable: $command" >&2
    exit 1
  }
done

TARGET_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="${DSV4FV_BUILD_DIR:-$TARGET_ROOT/.dsv4fv-build}"
CHECKOUT="$WORK_DIR/spark-vllm-docker"
mkdir -p "$WORK_DIR"

if [[ ! -d "$CHECKOUT/.git" ]]; then
  git clone "$EUGR_REPO" "$CHECKOUT"
else
  actual_origin="$(git -C "$CHECKOUT" remote get-url origin)"
  if [[ "${actual_origin%.git}" != "${EUGR_REPO%.git}" ]]; then
    echo "ERROR: cached checkout has unexpected origin: $actual_origin" >&2
    exit 1
  fi
fi
git -C "$CHECKOUT" fetch --quiet origin "$EUGR_COMMIT"
git -C "$CHECKOUT" checkout --quiet --detach "$EUGR_COMMIT"
if [[ "$(git -C "$CHECKOUT" rev-parse HEAD)" != "$EUGR_COMMIT" ]]; then
  echo "ERROR: failed to select pinned eugr commit" >&2
  exit 1
fi

# This is a package-managed cache: every build starts from the pinned tracked tree.
git -C "$CHECKOUT" restore --source "$EUGR_COMMIT" --worktree --staged -- .

python3 - \
  "$CHECKOUT/build-and-copy.sh" \
  "$CHECKOUT/Dockerfile" \
  "$VLLM_REPO" \
  "$B12X_REPO" \
  "$B12X_COMMIT" <<'PY'
from pathlib import Path
import re
import sys

build_script = Path(sys.argv[1])
dockerfile = Path(sys.argv[2])
vllm_repo, b12x_repo, b12x_commit = sys.argv[3:]
text = build_script.read_text(encoding="utf-8")
replacements = {
    r'^EXP_B12X_VLLM_REPO=.*$': f'EXP_B12X_VLLM_REPO="{vllm_repo}"',
    r'^B12X_PACKAGE_REPO=.*$': f'B12X_PACKAGE_REPO="{b12x_repo}"',
    r'^B12X_PACKAGE_REF=.*$': f'B12X_PACKAGE_REF="{b12x_commit}"',
    r'^WHEEL_CACHE_ROOT=.*$': 'WHEEL_CACHE_ROOT="${DSV4FV_WHEEL_CACHE_ROOT:-./.wheel-cache}"',
}
for pattern, replacement in replacements.items():
    text, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"build script drift: expected one match for {pattern}")
build_script.write_text(text, encoding="utf-8")

final = build_script.read_text(encoding="utf-8")
for replacement in replacements.values():
    if final.count(replacement) != 1:
        raise SystemExit(f"build script verification failed for {replacement}")

docker_text = dockerfile.read_text(encoding="utf-8")
old = (
    '        git clone --depth 1 --branch "$B12X_REF" "$B12X_REPO" /tmp/b12x-source && \\\n'
    '        B12X_COMMIT=$(git -C /tmp/b12x-source rev-parse HEAD) && \\\n'
)
new = (
    '        git clone --filter=blob:none --depth 1 --no-checkout "$B12X_REPO" /tmp/b12x-source && \\\n'
    '        git -C /tmp/b12x-source fetch --depth 1 origin "$B12X_REF" && \\\n'
    '        git -C /tmp/b12x-source checkout --detach FETCH_HEAD && \\\n'
    '        B12X_COMMIT=$(git -C /tmp/b12x-source rev-parse HEAD) && \\\n'
    '        test "$B12X_COMMIT" = "$B12X_REF" && \\\n'
)
if docker_text.count(old) != 1:
    raise SystemExit("Dockerfile drift: expected one B12X clone block")
docker_text = docker_text.replace(old, new, 1)
dockerfile.write_text(docker_text, encoding="utf-8")
if docker_text.count('fetch --depth 1 origin "$B12X_REF"') != 1:
    raise SystemExit("Dockerfile verification failed for immutable B12X fetch")
if docker_text.count('test "$B12X_COMMIT" = "$B12X_REF"') != 1:
    raise SystemExit("Dockerfile verification failed for B12X commit check")

build_text = build_script.read_text(encoding="utf-8")
old_rebuild = (
    '        if { [ "$VLLM_PROFILE" = "custom" ] && [ "$USE_WHEELS" != true ]; } || \\\n'
    '           [ "$VLLM_REF_SET" = true ] || [ "$VLLM_PR_APPLICATION_REQUESTED" = true ]; then\n'
)
new_rebuild = (
    '        if [ "${DSV4FV_REUSE_VLLM_WHEEL:-0}" != "1" ] && \\\n'
    '           { [ "$VLLM_PROFILE" = "custom" ] && [ "$USE_WHEELS" != true ]; } || \\\n'
    '           { [ "${DSV4FV_REUSE_VLLM_WHEEL:-0}" != "1" ] && \\\n'
    '             { [ "$VLLM_REF_SET" = true ] || [ "$VLLM_PR_APPLICATION_REQUESTED" = true ]; }; }; then\n'
)
if build_text.count(old_rebuild) != 1:
    raise SystemExit("build script drift: expected one vLLM rebuild decision block")
build_text = build_text.replace(old_rebuild, new_rebuild, 1)
build_script.write_text(build_text, encoding="utf-8")
if build_text.count("DSV4FV_REUSE_VLLM_WHEEL") != 2:
    raise SystemExit("build script verification failed for vLLM wheel reuse gate")
PY

git -C "$CHECKOUT" diff --check
changed="$(git -C "$CHECKOUT" diff --name-only "$EUGR_COMMIT")"
if [[ "$changed" != $'Dockerfile\nbuild-and-copy.sh' ]]; then
  echo "ERROR: source preparation changed unexpected tracked paths: $changed" >&2
  exit 1
fi

WHEEL_CACHE_ROOT="${DSV4FV_WHEEL_CACHE_ROOT:-$TARGET_ROOT/.wheel-cache}"
VLLM_CACHE_DIR="$WHEEL_CACHE_ROOT/vllm/custom"
REUSE_VLLM_WHEEL=0
vllm_wheels=("$VLLM_CACHE_DIR"/vllm-*.whl)
if [[ -f "$VLLM_CACHE_DIR/.vllm-commit" \
      && "$(<"$VLLM_CACHE_DIR/.vllm-commit")" == "$VLLM_COMMIT" \
      && -f "$VLLM_CACHE_DIR/.deepgemm-commit" \
      && -f "$VLLM_CACHE_DIR/.vllm-arch" \
      && "$(<"$VLLM_CACHE_DIR/.vllm-arch")" == "12.1a" \
      && "${#vllm_wheels[@]}" -eq 1 \
      && -f "${vllm_wheels[0]}" ]]; then
  REUSE_VLLM_WHEEL=1
  echo "Reusing cached vLLM wheel for $VLLM_COMMIT from $VLLM_CACHE_DIR"
else
  echo "No complete cached vLLM wheel matches $VLLM_COMMIT; a source build is required."
fi

forward_args=()
while (($#)); do
  if [[ "$1" == "--config" ]]; then
    config_path="${2:?--config requires a value}"
    if [[ "$config_path" != /* ]]; then
      config_path="$CALLER_PWD/$config_path"
    fi
    forward_args+=(--config "$config_path")
    shift 2
    continue
  fi
  forward_args+=("$1")
  shift
done

if [[ "$PREPARE_ONLY" == true ]]; then
  echo "Prepared pinned eugr build source at $CHECKOUT"
  echo "Build context: $CHECKOUT"
  echo "Wheel cache: $WHEEL_CACHE_ROOT"
  echo "Reusable pinned vLLM wheel: $REUSE_VLLM_WHEEL"
  exit 0
fi

echo "Building $IMAGE_TAG from native vLLM Vision support."
(
  cd "$CHECKOUT"
  DSV4FV_WHEEL_CACHE_ROOT="$WHEEL_CACHE_ROOT" \
  DSV4FV_REUSE_VLLM_WHEEL="$REUSE_VLLM_WHEEL" \
    ./build-and-copy.sh \
      --vllm-repo "$VLLM_REPO" \
      --vllm-ref "$VLLM_COMMIT" \
      -t "$IMAGE_TAG" \
      "${forward_args[@]}"
)
