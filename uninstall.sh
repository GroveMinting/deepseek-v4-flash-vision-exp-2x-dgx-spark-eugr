#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-$PWD}"
TARGET="$(cd "$TARGET" && pwd)"
if [[ ! -x "$TARGET/run-recipe.sh" || ! -f "$TARGET/run-recipe.py" ]]; then
  echo "ERROR: '$TARGET' does not look like an eugr spark-vllm-docker checkout." >&2
  echo "Usage: $0 /path/to/spark-vllm-docker" >&2
  exit 1
fi

rm -f \
  "$TARGET/run-deepseek-v4-vision.sh" \
  "$TARGET/recipes/deepseek-v4-flash-vision-exp-base-fp8.yaml" \
  "$TARGET/recipes/deepseek-v4-flash-vision-exp-dspark-fp8.yaml" \
  "$TARGET/tools/deepseek-v4-vision-versions.lock" \
  "$TARGET/tools/deepseek-v4-vision-build.sh" \
  "$TARGET/tools/deepseek-v4-vision-download.sh" \
  "$TARGET/tools/deepseek-v4-vision-smoke.sh" \
  "$TARGET/tools/deepseek-v4-vision-inspect.sh" \
  "$TARGET/tools/deepseek-v4-vision-benchmark.py"
rm -rf "$TARGET/mods/deepseek-v4-vision-native-check"

echo "Removed DeepSeek V4 Vision integration files from $TARGET"
echo "Backups, build caches, model caches, images, and running containers were left untouched."
