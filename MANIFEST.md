# Package manifest

- `README.md` - runtime pins, build, staging, launch, validation, performance, and troubleshooting.
- `.gitignore` - excludes local secrets, Python caches, and the large runtime build tree.
- `.github/workflows/validate.yml` - package, source-preparation, lifecycle, and recipe validation.
- `ATTRIBUTION.md` - third-party sources, measurements, licenses, and implementation boundaries.
- `CHANGELOG.md` - release history.
- `LICENSE` - MIT license for package integration work.
- `MANIFEST.md` - this file.
- `VERSIONS.lock` - authoritative source, model, and image pins.
- `run-deepseek-v4-vision.sh` - one-command setup and eugr launch wrapper.
- `install.sh` - installs package files into an eugr checkout with collision backups.
- `uninstall.sh` - removes only package-owned installed paths.
- `recipes/deepseek-v4-flash-vision-exp-base-fp8.yaml` - TP2 native-vision diagnostic recipe without DSpark.
- `recipes/deepseek-v4-flash-vision-exp-dspark-fp8.yaml` - TP2 native-vision DSpark K6 serving recipe.
- `results/2026-09-05-two-spark-validation.md` - sanitized live functional, performance, provenance, and CI receipt.
- `mods/deepseek-v4-vision-native-check/run.sh` - read-only startup gate entry point.
- `mods/deepseek-v4-vision-native-check/check_native_runtime.py` - native feature and image-provenance checker.
- `tools/deepseek-v4-vision-build.sh` - isolated, pinned eugr/vLLM/B12X image builder.
- `tools/deepseek-v4-vision-download.sh` - revision-aware model downloader and worker cache distributor.
- `tools/deepseek-v4-vision-smoke.sh` - deterministic text, image, tool, and DSpark checks.
- `tools/deepseek-v4-vision-inspect.sh` - API, metrics, image provenance, and startup-log inspection.
- `tools/deepseek-v4-vision-benchmark.py` - dependency-free streaming and concurrent throughput benchmark.
- `tests/test_package.py` - recipe, pin, documentation, lifecycle, and security assertions.
- `tests/test_native_check.py` - unit tests for complete, missing, and mismatched native-runtime states.
- `tests/test_wrapper.py` - side-effect-free setup planning, profile selection, and passthrough tests.

## Installed composition

```text
eugr/spark-vllm-docker
+ two recipes
+ one setup-and-run wrapper
+ one read-only native-runtime gate
+ one pinned runtime builder
+ one revision-aware model distributor
+ three runtime validation tools
```

Tests and package documentation remain in this source package and are not
copied into the eugr checkout. The installer places synchronized lockfile
copies beside the installed builder and runtime checker.
