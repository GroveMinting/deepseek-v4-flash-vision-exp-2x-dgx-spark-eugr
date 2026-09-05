#!/usr/bin/env python3
"""Fail-closed checks for the pinned native DeepSeek V4 Vision runtime."""

from __future__ import annotations

import argparse
import importlib.util
import os
import re
from pathlib import Path


def load_lock() -> dict[str, str]:
    here = Path(__file__).resolve()
    candidates = (here.with_name("VERSIONS.lock"), here.parents[2] / "VERSIONS.lock")
    lock = next((path for path in candidates if path.is_file()), None)
    if lock is None:
        raise RuntimeError("VERSIONS.lock is missing")
    values: dict[str, str] = {}
    pattern = re.compile(r'^([A-Z][A-Z0-9_]*)="([^"]+)"$')
    for line in lock.read_text(encoding="utf-8").splitlines():
        match = pattern.fullmatch(line.strip())
        if match:
            values[match.group(1)] = match.group(2)
    for key in ("VLLM_COMMIT", "B12X_COMMIT"):
        if key not in values:
            raise RuntimeError(f"{key} is missing from {lock}")
    return values


PINS = load_lock()
VLLM_COMMIT = PINS["VLLM_COMMIT"]
B12X_COMMIT = PINS["B12X_COMMIT"]
REQUIRED_SOURCE_MARKERS = {
    "DeepseekV4ForConditionalGeneration",
    "DeepseekV4ModelArchConfigConvertor",
    "DeepseekV4ViT",
    "DeepseekV4Aligner",
    "IMAGE_PLACEHOLDER",
    "bias_vl",
    "DSparkDraftModel",
}


def inspect_tree(vllm_root: Path, metadata_root: Path, strict_pins: bool) -> dict[str, str]:
    if not vllm_root.is_dir():
        raise RuntimeError(f"vLLM package directory does not exist: {vllm_root}")

    missing = set(REQUIRED_SOURCE_MARKERS)
    registry_has_multimodal_arch = False
    for path in vllm_root.rglob("*.py"):
        try:
            source = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        missing.difference_update([marker for marker in missing if marker in source])
        if path.name == "registry.py" and "_MULTIMODAL_MODELS" in source:
            registry_has_multimodal_arch |= "DeepseekV4ForConditionalGeneration" in source

    if missing:
        raise RuntimeError("native Vision runtime markers are missing: " + ", ".join(sorted(missing)))
    if not registry_has_multimodal_arch:
        raise RuntimeError("DeepseekV4ForConditionalGeneration is not in the multimodal registry")

    result = {"vllm_commit": "unverified", "b12x_commit": "unverified"}
    metadata = metadata_root / "build-metadata.yaml"
    b12x_commit_file = metadata_root / "b12x-source-commit"
    if metadata.is_file():
        text = metadata.read_text(encoding="utf-8")
        if VLLM_COMMIT in text:
            result["vllm_commit"] = VLLM_COMMIT
    if b12x_commit_file.is_file():
        value = b12x_commit_file.read_text(encoding="utf-8").strip()
        if value == B12X_COMMIT:
            result["b12x_commit"] = value

    if strict_pins and result["vllm_commit"] != VLLM_COMMIT:
        raise RuntimeError(f"image metadata does not identify pinned vLLM commit {VLLM_COMMIT}")
    if strict_pins and result["b12x_commit"] != B12X_COMMIT:
        raise RuntimeError(f"image metadata does not identify pinned B12X commit {B12X_COMMIT}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vllm-root", type=Path)
    parser.add_argument("--metadata-root", type=Path, default=Path("/workspace"))
    parser.add_argument("--no-strict-pins", action="store_true")
    args = parser.parse_args()

    if args.vllm_root is None:
        spec = importlib.util.find_spec("vllm")
        if spec is None or spec.origin is None:
            raise SystemExit("native runtime check failed: cannot locate vllm")
        args.vllm_root = Path(spec.origin).resolve().parent
    if importlib.util.find_spec("b12x") is None:
        raise SystemExit("native runtime check failed: cannot locate b12x")

    strict = not args.no_strict_pins and os.environ.get("DSV4FV_STRICT_PINS", "1") != "0"
    try:
        result = inspect_tree(args.vllm_root, args.metadata_root, strict)
    except RuntimeError as exc:
        raise SystemExit(f"native runtime check failed: {exc}") from exc
    print("native DeepSeek V4 Vision runtime: present")
    print("vLLM commit:", result["vllm_commit"])
    print("B12X commit:", result["b12x_commit"])


if __name__ == "__main__":
    main()
