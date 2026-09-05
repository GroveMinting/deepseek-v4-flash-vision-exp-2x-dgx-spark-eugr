#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:8000}"
MODEL="${2:-${MODEL:-}}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/deepseek-v4-vision-smoke.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fsS "$BASE_URL/v1/models" -o "$TMP_DIR/models.json"
if [[ -z "$MODEL" ]]; then
  MODEL="$(python3 - "$TMP_DIR/models.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["data"][0]["id"])
PY
)"
fi
echo "Using served model: $MODEL"

python3 - "$MODEL" "$TMP_DIR/text.json" <<'PY'
import json, sys
model, output = sys.argv[1:]
payload = {
    "model": model,
    "messages": [{"role": "user", "content": "Return exactly: DSV4_VISION_OK"}],
    "temperature": 0,
    "max_tokens": 64,
    "stream": False,
    "chat_template_kwargs": {"thinking": False},
}
json.dump(payload, open(output, "w", encoding="utf-8"))
PY
curl -fsS "$BASE_URL/v1/chat/completions" -H 'Content-Type: application/json' \
  --data-binary "@$TMP_DIR/text.json" -o "$TMP_DIR/text-response.json"
python3 - "$TMP_DIR/text-response.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
try:
    content = data["choices"][0]["message"]["content"]
except (KeyError, IndexError, TypeError) as exc:
    raise SystemExit(f"Unexpected text response: {exc}\n{json.dumps(data, indent=2)}")
if not isinstance(content, str) or "DSV4_VISION_OK" not in content:
    raise SystemExit("Text check failed:\n" + json.dumps(data, indent=2))
print("Text generation passed:", repr(content))
PY

if [[ "${SKIP_VISION_TEST:-0}" != "1" ]]; then
  python3 - "$MODEL" "$TMP_DIR/vision.json" <<'PY'
import base64, binascii, json, struct, sys, zlib

model, output = sys.argv[1:]
width, height = 64, 32
rows = []
for _ in range(height):
    pixels = b"\xff\x00\x00" * (width // 2) + b"\x00\x00\xff" * (width // 2)
    rows.append(b"\x00" + pixels)
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", binascii.crc32(kind + data) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b"")
uri = "data:image/png;base64," + base64.b64encode(png).decode()
payload = {
    "model": model,
    "messages": [{"role": "user", "content": [
        {"type": "image_url", "image_url": {"url": uri}},
        {"type": "text", "text": "Name the two colors in this image. Answer with only the color names."},
    ]}],
    "temperature": 0,
    "max_tokens": 64,
    "stream": False,
    "chat_template_kwargs": {"thinking": False},
}
json.dump(payload, open(output, "w", encoding="utf-8"))
PY
  curl -fsS "$BASE_URL/v1/chat/completions" -H 'Content-Type: application/json' \
    --data-binary "@$TMP_DIR/vision.json" -o "$TMP_DIR/vision-response.json"
  python3 - "$TMP_DIR/vision-response.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
try:
    content = data["choices"][0]["message"]["content"]
except (KeyError, IndexError, TypeError) as exc:
    raise SystemExit(f"Unexpected vision response: {exc}\n{json.dumps(data, indent=2)}")
text = content.lower() if isinstance(content, str) else ""
if "red" not in text or "blue" not in text:
    raise SystemExit("Vision color check failed:\n" + json.dumps(data, indent=2))
print("Native image understanding passed:", repr(content))
PY
fi

if [[ "${SKIP_TOOL_TEST:-0}" != "1" ]]; then
  python3 - "$MODEL" "$TMP_DIR/tool.json" <<'PY'
import json, sys
model, output = sys.argv[1:]
payload = {
    "model": model,
    "messages": [{"role": "user", "content": "Call report_probe with status DSV4_TOOL_OK."}],
    "tools": [{"type": "function", "function": {
        "name": "report_probe", "description": "Report probe status.",
        "parameters": {"type": "object", "properties": {"status": {"type": "string"}}, "required": ["status"]}
    }}],
    "tool_choice": "required",
    "temperature": 0,
    "max_tokens": 128,
    "stream": False,
    "chat_template_kwargs": {"thinking": False},
}
json.dump(payload, open(output, "w", encoding="utf-8"))
PY
  curl -fsS "$BASE_URL/v1/chat/completions" -H 'Content-Type: application/json' \
    --data-binary "@$TMP_DIR/tool.json" -o "$TMP_DIR/tool-response.json"
  python3 - "$TMP_DIR/tool-response.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
try:
    function = data["choices"][0]["message"]["tool_calls"][0]["function"]
except (KeyError, IndexError, TypeError) as exc:
    raise SystemExit(f"Structured tool call missing: {exc}\n{json.dumps(data, indent=2)}")
arguments = function.get("arguments", {})
if isinstance(arguments, str):
    arguments = json.loads(arguments)
if function.get("name") != "report_probe" or arguments.get("status") != "DSV4_TOOL_OK":
    raise SystemExit("Unexpected tool call:\n" + json.dumps(data, indent=2))
print("Tool calling passed:", function["name"], arguments)
PY
fi

if curl -fsS "$BASE_URL/metrics" -o "$TMP_DIR/metrics"; then
  python3 - "$TMP_DIR/metrics" "${REQUIRE_DSPARK:-0}" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
required = sys.argv[2] == "1"
def total(names):
    values = []
    for name in names:
        values.extend(float(x) for x in re.findall(rf"^vllm:{name}(?:\{{[^}}]*\}})?\s+([0-9.eE+-]+)$", text, re.M))
    return sum(values) if values else None
accepted = total(("spec_decode_num_accepted_tokens_total",))
drafted = total(("spec_decode_num_draft_tokens_total", "spec_decode_num_drafted_tokens_total"))
if drafted is None:
    if required:
        raise SystemExit("DSpark counters are unavailable")
    print("Speculative counters unavailable; base-profile smoke test continues.")
elif drafted <= 0 and required:
    raise SystemExit("DSpark smoke test failed: no draft tokens were recorded")
elif drafted > 0:
    print(f"DSpark counters: accepted={accepted or 0:g} drafted={drafted:g} ratio={(accepted or 0)/drafted:.3f}")
PY
fi

echo "All requested DeepSeek V4 Vision smoke tests passed."
