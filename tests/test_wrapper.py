#!/usr/bin/env python3
"""Validate the one-command wrapper without building or downloading artifacts."""

from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def make_eugr(root: Path) -> Path:
    target = root / "spark-vllm-docker"
    (target / "recipes").mkdir(parents=True)
    launcher = target / "run-recipe.sh"
    launcher.write_text(
        '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$TEST_LOG"\n',
        encoding="utf-8",
    )
    launcher.chmod(0o755)
    (target / "run-recipe.py").write_text("# fixture\n", encoding="utf-8")
    (target / "build-and-copy.sh").write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    (target / "build-and-copy.sh").chmod(0o755)
    subprocess.run([str(ROOT / "install.sh"), str(target)], check=True, capture_output=True)
    return target


def run_wrapper(target: Path, log: Path, *args: str) -> subprocess.CompletedProcess[str]:
    env = os.environ | {"TEST_LOG": str(log)}
    return subprocess.run(
        [str(target / "run-deepseek-v4-vision.sh"), *args],
        env=env,
        capture_output=True,
        text=True,
    )


def test_setup_plan_and_passthrough() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        target = make_eugr(root)
        log = root / "commands.log"
        result = run_wrapper(
            target, log, "--setup", "--dry-run", "-n", "127.0.0.1,127.0.0.2", "-d"
        )
        assert result.returncode == 0, result.stderr
        assert "deepseek-v4-vision-build.sh" in result.stdout
        assert "deepseek-v4-vision-download.sh" in result.stdout
        assert "deepseek-v4-flash-vision-exp-dspark-fp8" in result.stdout
        command = log.read_text(encoding="utf-8")
        assert "deepseek-v4-flash-vision-exp-dspark-fp8" in command
        assert "--dry-run" in command
        assert "-d" in command


def test_base_profile_and_invalid_modes() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        target = make_eugr(root)
        log = root / "commands.log"
        result = run_wrapper(
            target, log, "--base", "--dry-run", "-n", "127.0.0.1,127.0.0.2"
        )
        assert result.returncode == 0, result.stderr
        assert "deepseek-v4-flash-vision-exp-base-fp8" in log.read_text(encoding="utf-8")

        invalid = run_wrapper(target, log, "--build-only", "--download-only")
        assert invalid.returncode == 2
        assert "cannot be combined" in invalid.stderr


if __name__ == "__main__":
    test_setup_plan_and_passthrough()
    test_base_profile_and_invalid_modes()
    print("Wrapper tests passed")
