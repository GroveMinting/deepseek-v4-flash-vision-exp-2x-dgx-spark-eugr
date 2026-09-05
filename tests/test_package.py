#!/usr/bin/env python3
"""Validate the DeepSeek V4 Vision package contract."""

from __future__ import annotations

import subprocess
import tempfile
import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]


def load_lock() -> dict[str, str]:
    values = {}
    pattern = re.compile(r'^([A-Z][A-Z0-9_]*)="([^"]+)"$')
    for line in (ROOT / "VERSIONS.lock").read_text(encoding="utf-8").splitlines():
        match = pattern.fullmatch(line.strip())
        if match:
            values[match.group(1)] = match.group(2)
    return values


PINS = load_lock()
MODEL = PINS["MODEL_ID"]
MODEL_REVISION = PINS["MODEL_REVISION"]
EUGR_COMMIT = PINS["EUGR_COMMIT"]
VLLM_COMMIT = PINS["VLLM_COMMIT"]
B12X_COMMIT = PINS["B12X_COMMIT"]


def test_recipes() -> None:
    recipes = sorted((ROOT / "recipes").glob("*.yaml"))
    assert len(recipes) == 2
    for path in recipes:
        recipe = yaml.safe_load(path.read_text(encoding="utf-8"))
        command = recipe["command"]
        assert recipe["model"] == MODEL
        assert recipe["container"] == "vllm-node-dsv4fv"
        assert recipe["cluster_only"] is True
        assert recipe["defaults"]["tensor_parallel"] == 2
        assert recipe["defaults"]["max_model_len"] == 327680
        assert "--kv-cache-dtype fp8" in command
        assert f"--revision {MODEL_REVISION}" in command
        assert "--attention-backend B12X_MLA_SPARSE" in command
        assert "--limit-mm-per-prompt" in command
        assert "--trust-remote-code" not in command
        assert "DeepseekV4ForConditionalGeneration" in command
        assert recipe["env"]["VLLM_USE_B12X_MHC"] == "1"
        assert recipe["mods"][0] == "mods/deepseek-v4-vision-native-check"

    base = yaml.safe_load(recipes[0].read_text(encoding="utf-8"))
    dspark = yaml.safe_load(recipes[1].read_text(encoding="utf-8"))
    assert "--speculative-config" not in base["command"]
    assert dspark["defaults"]["num_speculative_tokens"] == 6
    assert '"num_speculative_tokens":{num_speculative_tokens}' in dspark["command"]
    assert "mods/instanttensor-hybrid-draft-loader" in dspark["mods"]


def test_build_pins() -> None:
    output = subprocess.run(
        [str(ROOT / "tools/deepseek-v4-vision-build.sh"), "--print-pins"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    for value in (EUGR_COMMIT, VLLM_COMMIT, B12X_COMMIT, "vllm-node-dsv4fv"):
        assert value in output
    download_output = subprocess.run(
        [str(ROOT / "tools/deepseek-v4-vision-download.sh"), "--print-pins"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    assert MODEL in download_output
    assert MODEL_REVISION in download_output


def test_lock_is_authoritative() -> None:
    assert set(PINS) == {
        "EUGR_REPO", "EUGR_COMMIT", "VLLM_REPO", "VLLM_COMMIT",
        "B12X_REPO", "B12X_COMMIT", "MODEL_ID", "MODEL_REVISION", "IMAGE_TAG",
    }
    build = (ROOT / "tools/deepseek-v4-vision-build.sh").read_text(encoding="utf-8")
    checker = (ROOT / "mods/deepseek-v4-vision-native-check/check_native_runtime.py").read_text(encoding="utf-8")
    for value in (EUGR_COMMIT, VLLM_COMMIT, B12X_COMMIT, MODEL_REVISION):
        assert value not in build
        assert value not in checker


def test_b12x_commit_fetch_rewrite() -> None:
    build = (ROOT / "tools/deepseek-v4-vision-build.sh").read_text(encoding="utf-8")
    assert "Dockerfile" in build
    assert 'fetch --depth 1 origin "$B12X_REF"' in build
    assert 'checkout --detach FETCH_HEAD' in build
    assert 'test "$B12X_COMMIT" = "$B12X_REF"' in build
    assert "git clone --depth 1 --branch" in build
    assert "$'Dockerfile\\nbuild-and-copy.sh'" in build
    assert 'cd "$CHECKOUT"' in build
    assert 'DSV4FV_WHEEL_CACHE_ROOT="$WHEEL_CACHE_ROOT"' in build
    assert 'DSV4FV_REUSE_VLLM_WHEEL="$REUSE_VLLM_WHEEL"' in build
    assert "--rebuild-vllm" not in build


def test_documentation_and_boundaries() -> None:
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    attribution = (ROOT / "ATTRIBUTION.md").read_text(encoding="utf-8")
    for value in (MODEL, MODEL_REVISION, EUGR_COMMIT, VLLM_COMMIT, B12X_COMMIT):
        assert value in readme
        assert value in attribution
    assert "no vision sidecar" in readme.lower()
    assert "not been benchmarked locally" in readme
    assert "No third-party patch file" in attribution


def test_repository_hygiene() -> None:
    ignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    for value in (".dsv4fv-build/", ".env", "__pycache__/", "*.py[cod]"):
        assert value in ignore
    workflow = (ROOT / ".github/workflows/validate.yml").read_text(encoding="utf-8")
    for value in ("test_native_check.py", "test_package.py", "test_wrapper.py", "--prepare-only", "--dry-run"):
        assert value in workflow
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    assert "independent community project" in readme
    assert "VERSIONS.lock" in readme
    assert (ROOT / "CHANGELOG.md").is_file()


def test_lifecycle_lists_owned_paths() -> None:
    install = (ROOT / "install.sh").read_text(encoding="utf-8")
    uninstall = (ROOT / "uninstall.sh").read_text(encoding="utf-8")
    owned = (
        "run-deepseek-v4-vision.sh",
        "deepseek-v4-flash-vision-exp-base-fp8.yaml",
        "deepseek-v4-flash-vision-exp-dspark-fp8.yaml",
        "deepseek-v4-vision-native-check",
        "deepseek-v4-vision-versions.lock",
        "deepseek-v4-vision-build.sh",
        "deepseek-v4-vision-download.sh",
        "deepseek-v4-vision-smoke.sh",
        "deepseek-v4-vision-inspect.sh",
        "deepseek-v4-vision-benchmark.py",
    )
    for name in owned:
        assert name in install
        assert name in uninstall


def test_installer_and_uninstaller() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        target = Path(temporary) / "spark-vllm-docker"
        recipes = target / "recipes"
        recipes.mkdir(parents=True)
        launcher = target / "run-recipe.sh"
        launcher.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
        launcher.chmod(0o755)
        (target / "run-recipe.py").write_text("# fixture\n", encoding="utf-8")
        collision = recipes / "deepseek-v4-flash-vision-exp-base-fp8.yaml"
        collision.write_text("original\n", encoding="utf-8")

        subprocess.run([str(ROOT / "install.sh"), str(target)], check=True)
        assert "recipe_version" in collision.read_text(encoding="utf-8")
        backups = list((target / ".local-backups").glob("deepseek-v4fv-eugr-*/recipes/*.yaml"))
        assert len(backups) == 1
        assert backups[0].read_text(encoding="utf-8") == "original\n"
        assert (target / "mods/deepseek-v4-vision-native-check/run.sh").is_file()
        assert (target / "run-deepseek-v4-vision.sh").is_file()
        assert (target / "tools/deepseek-v4-vision-build.sh").is_file()
        assert (target / "tools/deepseek-v4-vision-download.sh").is_file()
        canonical_lock = (ROOT / "VERSIONS.lock").read_text(encoding="utf-8")
        assert (target / "tools/deepseek-v4-vision-versions.lock").read_text(encoding="utf-8") == canonical_lock
        assert (target / "mods/deepseek-v4-vision-native-check/VERSIONS.lock").read_text(encoding="utf-8") == canonical_lock

        subprocess.run([str(ROOT / "uninstall.sh"), str(target)], check=True)
        assert not collision.exists()
        assert not (target / "run-deepseek-v4-vision.sh").exists()
        assert not (target / "mods/deepseek-v4-vision-native-check").exists()
        assert backups[0].is_file()


if __name__ == "__main__":
    test_recipes()
    test_build_pins()
    test_lock_is_authoritative()
    test_b12x_commit_fetch_rewrite()
    test_documentation_and_boundaries()
    test_repository_hygiene()
    test_lifecycle_lists_owned_paths()
    test_installer_and_uninstaller()
    print("Package tests passed")
