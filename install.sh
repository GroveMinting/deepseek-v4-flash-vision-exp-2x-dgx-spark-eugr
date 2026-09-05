#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-$PWD}"
TARGET="$(cd "$TARGET" && pwd)"

if [[ ! -x "$TARGET/run-recipe.sh" || ! -f "$TARGET/run-recipe.py" ]]; then
  echo "ERROR: '$TARGET' does not look like an eugr spark-vllm-docker checkout." >&2
  echo "Usage: $0 /path/to/spark-vllm-docker" >&2
  exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
backup="$TARGET/.local-backups/deepseek-v4fv-eugr-$stamp"
files=(
  "run-deepseek-v4-vision.sh"
  "recipes/deepseek-v4-flash-vision-exp-base-fp8.yaml"
  "recipes/deepseek-v4-flash-vision-exp-dspark-fp8.yaml"
  "mods/deepseek-v4-vision-native-check"
  "tools/deepseek-v4-vision-versions.lock"
  "tools/deepseek-v4-vision-build.sh"
  "tools/deepseek-v4-vision-download.sh"
  "tools/deepseek-v4-vision-smoke.sh"
  "tools/deepseek-v4-vision-inspect.sh"
  "tools/deepseek-v4-vision-benchmark.py"
)

backed_up=false
for rel in "${files[@]}"; do
  if [[ -e "$TARGET/$rel" ]]; then
    mkdir -p "$backup/$(dirname "$rel")"
    cp -a "$TARGET/$rel" "$backup/$rel"
    echo "Backed up: $rel"
    backed_up=true
  fi
done

mkdir -p "$TARGET/recipes" "$TARGET/mods" "$TARGET/tools"
cp -a "$SRC_DIR/run-deepseek-v4-vision.sh" "$TARGET/"
cp -a "$SRC_DIR/recipes/." "$TARGET/recipes/"
rm -rf "$TARGET/mods/deepseek-v4-vision-native-check"
cp -a "$SRC_DIR/mods/deepseek-v4-vision-native-check" "$TARGET/mods/"
cp -a "$SRC_DIR/tools/." "$TARGET/tools/"
cp -a "$SRC_DIR/VERSIONS.lock" "$TARGET/tools/deepseek-v4-vision-versions.lock"
cp -a "$SRC_DIR/VERSIONS.lock" "$TARGET/mods/deepseek-v4-vision-native-check/VERSIONS.lock"
rm -rf "$TARGET/mods/deepseek-v4-vision-native-check/__pycache__" "$TARGET/tools/__pycache__"

chmod +x \
  "$TARGET/run-deepseek-v4-vision.sh" \
  "$TARGET/mods/deepseek-v4-vision-native-check/run.sh" \
  "$TARGET/mods/deepseek-v4-vision-native-check/check_native_runtime.py" \
  "$TARGET/tools/deepseek-v4-vision-build.sh" \
  "$TARGET/tools/deepseek-v4-vision-download.sh" \
  "$TARGET/tools/deepseek-v4-vision-smoke.sh" \
  "$TARGET/tools/deepseek-v4-vision-inspect.sh" \
  "$TARGET/tools/deepseek-v4-vision-benchmark.py"

cat <<MSG
Installed the DeepSeek V4 Flash Vision integration into:
  $TARGET

One-command setup and recommended DSpark launch:
  cd "$TARGET"
  ./run-deepseek-v4-vision.sh --setup -d

Use --base with the wrapper for the diagnostic non-DSpark profile.
See README.md in the source package for the staged commands.
MSG

if [[ "$backed_up" == true ]]; then
  echo
  echo "Backup directory:"
  echo "  $backup"
fi
