#!/usr/bin/env python3
"""Unit tests for the read-only native Vision runtime gate."""

from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "mods/deepseek-v4-vision-native-check/check_native_runtime.py"


def load_checker():
    spec = importlib.util.spec_from_file_location("native_runtime_checker", CHECKER)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fixture(root: Path, checker) -> tuple[Path, Path]:
    vllm = root / "vllm"
    metadata = root / "workspace"
    (vllm / "models").mkdir(parents=True)
    metadata.mkdir()
    markers = "\n".join(sorted(checker.REQUIRED_SOURCE_MARKERS))
    (vllm / "models/native.py").write_text(markers, encoding="utf-8")
    (vllm / "models/registry.py").write_text(
        "_MULTIMODAL_MODELS = {'DeepseekV4ForConditionalGeneration': 'native'}\n",
        encoding="utf-8",
    )
    (metadata / "build-metadata.yaml").write_text(
        f"vllm_commit: {checker.VLLM_COMMIT}\n", encoding="utf-8"
    )
    (metadata / "b12x-source-commit").write_text(
        checker.B12X_COMMIT + "\n", encoding="utf-8"
    )
    return vllm, metadata


def test_complete_and_pin_states() -> None:
    checker = load_checker()
    with tempfile.TemporaryDirectory() as temporary:
        vllm, metadata = fixture(Path(temporary), checker)
        result = checker.inspect_tree(vllm, metadata, True)
        assert result == {
            "vllm_commit": checker.VLLM_COMMIT,
            "b12x_commit": checker.B12X_COMMIT,
        }

        (metadata / "b12x-source-commit").write_text("wrong\n", encoding="utf-8")
        try:
            checker.inspect_tree(vllm, metadata, True)
        except RuntimeError as exc:
            assert "pinned B12X commit" in str(exc)
        else:
            raise AssertionError("mismatched B12X pin was accepted")
        checker.inspect_tree(vllm, metadata, False)


def test_missing_native_marker_fails() -> None:
    checker = load_checker()
    with tempfile.TemporaryDirectory() as temporary:
        vllm, metadata = fixture(Path(temporary), checker)
        path = vllm / "models/native.py"
        path.write_text(
            path.read_text(encoding="utf-8").replace("DeepseekV4Aligner", ""),
            encoding="utf-8",
        )
        try:
            checker.inspect_tree(vllm, metadata, True)
        except RuntimeError as exc:
            assert "DeepseekV4Aligner" in str(exc)
        else:
            raise AssertionError("missing native marker was accepted")


if __name__ == "__main__":
    test_complete_and_pin_states()
    test_missing_native_marker_fails()
    print("Native runtime checker tests passed")
