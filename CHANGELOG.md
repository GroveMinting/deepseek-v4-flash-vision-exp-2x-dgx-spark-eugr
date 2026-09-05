# Changelog

All notable changes to this project will be documented here.

## 0.1.2 - 2026-09-05

- Run eugr's prepared `build-and-copy.sh` from the prepared checkout so its
  relative Dockerfile and build context resolve to the patched sources.
- Preserve relative `--config` behavior when entering the prepared checkout.
- Share the installed eugr wheel cache with the isolated build and reuse a
  complete vLLM wheel only when its commit and SM121 markers match the lock.
- Add build-context and wheel-reuse diagnostics to `--prepare-only`.
- Record successful two-Spark text, native vision, tool-calling, DSpark,
  provenance, and C1/C8 throughput validation.

## 0.1.1 - 2026-09-04

- Fix B12X source preparation when the immutable revision is a commit SHA.
  The pinned eugr Dockerfile now fetches and checks out that SHA instead of
  incorrectly passing it to `git clone --branch`.
- Verify the checked-out B12X commit inside the image build before installing
  the package.

## 0.1.0 - 2026-09-04

- Add native DeepSeek V4 Flash Vision recipes for two DGX Sparks with TP2,
  FP8 KV cache, and 327,680-token context.
- Add diagnostic and DSpark K6 profiles based on the published
  `shige0501/dsv4-vision-spark` runtime and model pins.
- Add isolated runtime building and revision-aware model distribution.
- Add `run-deepseek-v4-vision.sh` for one-command eugr-style setup and launch.
- Add fail-closed native Vision and build-provenance checks.
- Add text, image, tool-calling, DSpark, inspection, and benchmark utilities.
- Add lifecycle tests and eugr recipe dry-run validation.
