#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:8000}"
CONTAINER_NAME="${CONTAINER_NAME:-vllm_node}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/deepseek-v4-vision-inspect.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "API models:"
curl -fsS "$BASE_URL/v1/models" | python3 -m json.tool

if curl -fsS "$BASE_URL/metrics" -o "$TMP_DIR/metrics"; then
  echo
  echo "Selected runtime metrics:"
  python3 - "$TMP_DIR/metrics" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
names = (
    "vllm:kv_cache_usage_perc", "vllm:prefix_cache_hits_total",
    "vllm:prefix_cache_queries_total", "vllm:spec_decode_num_accepted_tokens_total",
    "vllm:spec_decode_num_draft_tokens_total", "vllm:spec_decode_num_drafted_tokens_total",
)
values = {}
for name in names:
    matches = re.findall(rf"^{re.escape(name)}(?:\{{[^}}]*\}})?\s+([0-9.eE+-]+)$", text, re.M)
    if matches:
        values[name] = sum(float(x) for x in matches)
        print(f"{name}: {values[name]:g}")
accepted = values.get("vllm:spec_decode_num_accepted_tokens_total")
drafted = values.get("vllm:spec_decode_num_draft_tokens_total", values.get("vllm:spec_decode_num_drafted_tokens_total"))
if accepted is not None and drafted:
    print(f"pooled DSpark acceptance: {accepted / drafted:.3f}")
PY
fi

if command -v docker >/dev/null 2>&1 && docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo
  docker inspect -f 'status={{.State.Status}} image={{.Config.Image}} restarts={{.RestartCount}}' "$CONTAINER_NAME"
  echo
  echo "Runtime provenance:"
  docker exec "$CONTAINER_NAME" sh -c '
    python3 -c "import b12x, vllm; print(\"vLLM:\", vllm.__version__); print(\"B12X:\", getattr(b12x, \"__version__\", \"unknown\"))"
    test ! -f /workspace/build-metadata.yaml || cat /workspace/build-metadata.yaml
    test ! -f /workspace/b12x-source-commit || printf "b12x-source-commit: "; test ! -f /workspace/b12x-source-commit || cat /workspace/b12x-source-commit
  '
  echo
  echo "Relevant startup log lines:"
  docker logs --tail 1600 "$CONTAINER_NAME" 2>&1 | \
    grep -Ei 'DeepseekV4ForConditionalGeneration|vision|multimodal|DSpark|speculat|acceptance|KV cache|context|GPU memory|B12X' || true
else
  echo "Container '$CONTAINER_NAME' was not found locally; API inspection completed."
fi
