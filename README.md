# DeepSeek V4 Flash Vision for two DGX Sparks

[![Validate](https://github.com/GroveMinting/deepseek-v4-flash-vision-exp-2x-dgx-spark-eugr/actions/workflows/validate.yml/badge.svg)](https://github.com/GroveMinting/deepseek-v4-flash-vision-exp-2x-dgx-spark-eugr/actions/workflows/validate.yml)

This package installs native multimodal recipes for
`deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` into an existing
[`eugr/spark-vllm-docker`](https://github.com/eugr/spark-vllm-docker)
checkout.

This is an independent community project. It is not affiliated with or
endorsed by DeepSeek, NVIDIA, eugr, vLLM, or the B12X maintainers.

The operating target is fixed:

| Setting | Value |
|---|---|
| Hardware | Two NVIDIA DGX Sparks |
| Parallelism | Tensor parallel 2 |
| Context | 327,680 tokens |
| KV cache | FP8 |
| Vision | Checkpoint's native ViT and aligner |
| Speculation | Fused DSpark, six proposals |
| Model revision | `e46e16bf6035c6f317eb2ac7458eb0362926d402` |

There is no vision sidecar, proxy, or runtime-injected vision overlay. The
source-built vLLM runtime contains `DeepseekV4ForConditionalGeneration`, the
ViT, aligner, image processor, and modality-specific routing as native model
code. The recipe selects that class because the checkpoint retains the same
architecture metadata string as its text-only predecessor.

## Profiles

| Recipe | DSpark | Sequences | Purpose |
|---|---:|---:|---|
| `deepseek-v4-flash-vision-exp-base-fp8` | Off | 4 | First boot and fault isolation |
| `deepseek-v4-flash-vision-exp-dspark-fp8` | K6 | 8 | Recommended serving profile |

Both profiles retain image input, tools, reasoning, prefix caching, chunked
prefill, B12X attention/MoE/linear acceleration, and InstantTensor loading.
The pinned B12X branch includes FP8 dual-cache prefill at `index_topk=512`,
the cross-cache K-RoPE correction, and fused mHC support for the checkpoint's
`rms_norm_eps=1e-20`.

## Runtime pins

The installed build tool creates `vllm-node-dsv4fv` from:

| Component | Revision |
|---|---|
| eugr/spark-vllm-docker | `acd5d2a253704ad71096c5f23ac45e7cf57442af` |
| shige0501/vllm | `f6892f8fed7cb01e7df8d96f09c7f96167f0ef43` |
| shige0501/b12x | `fbba9c93b37191d258b89a40962603cc4c68b085` |

The vLLM, B12X, and model pins are the published, measured
`dsv4-vision-spark` combination. Its recorded eugr commit is no longer
fetchable, so this builder uses the closest public eugr revision from the same
date. The model/runtime forks contain the native Vision implementation, GB10
bring-up fixes, and `index_topk=512` kernel corrections. The build occurs
separately and does not edit the user's checkout.

`VERSIONS.lock` is the authoritative pin manifest. Update it first when
qualifying a new source or model revision; package tests ensure the recipes,
builder, runtime gate, and documentation remain synchronized.

## Requirements

- Two DGX Sparks with Docker, NVIDIA Container Toolkit, and the interconnect
  configured for eugr no-Ray operation.
- Passwordless SSH and an eugr `.env` with the head node first.
- Approximately 168 GB of model storage on each node plus image/build space.
- Swap enabled and unnecessary desktop/GPU workloads stopped during loading.

## Install

Clone the package, then install it into an existing eugr checkout:

```bash
git clone https://github.com/GroveMinting/deepseek-v4-flash-vision-exp-2x-dgx-spark-eugr.git
cd deepseek-v4-flash-vision-exp-2x-dgx-spark-eugr
bash install.sh ~/spark-vllm-docker
cd ~/spark-vllm-docker
```

Existing paths with the same names are backed up below
`.local-backups/deepseek-v4fv-eugr-<timestamp>/`.

## One-Command Quick Start

From the eugr checkout on the head Spark:

```bash
./run-deepseek-v4-vision.sh --setup -d
```

On the first run, the wrapper uses normal eugr discovery if `.env` is absent,
builds and distributes the pinned runtime image, downloads and verifies the
locked 48-shard model snapshot, copies it to the worker, and launches the
recommended DSpark recipe. Existing images are reused and only synchronized to
workers, so repeating `--setup` does not rebuild unnecessarily.

Later launches need only:

```bash
./run-deepseek-v4-vision.sh -d
```

Launch the diagnostic non-DSpark profile instead:

```bash
./run-deepseek-v4-vision.sh --setup --base -d
```

The wrapper accepts familiar eugr options such as `-n`, `--port`, `--gpu-mem`,
`--max-model-len`, and `-d`. It also supports:

```text
--build-only       prepare and distribute only the runtime image
--download-only    prepare and distribute only the pinned model
--force-build      rebuild instead of reusing the local image
--config FILE      use a non-default eugr cluster configuration
--dry-run          print setup actions and dry-run the selected recipe
```

## Manual Runtime Build

Build the pinned runtime on the head and copy it to the worker:

```bash
./tools/deepseek-v4-vision-build.sh \
  -c --copy-parallel --config "$PWD/.env"
```

The initial source build can take tens of minutes. Later invocations reuse the
isolated `.dsv4fv-build` wheel and Docker caches. Print pins without building:

```bash
./tools/deepseek-v4-vision-build.sh --print-pins
```

Use `--prepare-only` to fetch and validate the orchestration source without
starting a Docker build.

Use the wrapper rather than `run-recipe.sh --setup`: generic eugr setup does
not understand the pinned B12X fork and can replace the custom tag with the
normal eugr image. After setup, direct `run-recipe.sh` launches remain valid.

## Manual Model Staging

Download and copy only the immutable revision:

```bash
./tools/deepseek-v4-vision-download.sh \
  -c --copy-parallel --config "$PWD/.env"
```

The downloader verifies all 48 shards before copying the Hugging Face cache.
The recipe passes the same immutable, externally validated revision to the
target; DSpark weights come from that checkpoint. It never downloads the
model repository's moving default revision.

## Manual Staged Launch

Start with the non-speculative diagnostic profile:

```bash
./run-recipe.sh deepseek-v4-flash-vision-exp-base-fp8 --no-ray -d
./tools/deepseek-v4-vision-smoke.sh http://127.0.0.1:8000
```

Stop it, then launch DSpark:

```bash
./launch-cluster.sh stop
./run-recipe.sh deepseek-v4-flash-vision-exp-dspark-fp8 --no-ray -d
REQUIRE_DSPARK=1 ./tools/deepseek-v4-vision-smoke.sh http://127.0.0.1:8000
```

The smoke test checks deterministic text, a generated red/blue PNG through an
OpenAI `image_url` content block, structured tool calling, and DSpark metrics
when required.

## Inspect And Benchmark

```bash
./tools/deepseek-v4-vision-inspect.sh
./tools/deepseek-v4-vision-benchmark.py --warmups 2 --runs 3 --max-tokens 512
./tools/deepseek-v4-vision-benchmark.py --concurrency 8 --runs 3 --max-tokens 512
```

The benchmark reports TTFT, per-request decode rate, aggregate throughput, and
DSpark acceptance-counter deltas. Use the same prompt and generation settings
when comparing profiles.

## Validated Performance

This package was validated on two DGX Sparks on 2026-09-05. The benchmark used
its default implementation-guide prompt, `temperature=0`, thinking disabled,
and exactly 512 generated tokens per request.

| Metric | C1 median | C8 median |
|---|---:|---:|
| TTFT | 0.352 s | 0.393 s |
| Per-request decode | 50.917 tok/s | 11.589 tok/s |
| Aggregate end-to-end | 49.204 tok/s | 89.908 tok/s |
| DSpark acceptance | 41.8% | 40.6% |

C8 delivered 1.83 times the C1 aggregate throughput. The functional smoke
test also passed deterministic text, native red/blue image understanding,
structured tool calling, and active DSpark counters. The container remained
running with zero restarts and advertised the configured 327,680-token limit.

The complete sanitized commands, samples, smoke results, provenance, CI run,
and limitations are recorded in
[`results/2026-09-05-two-spark-validation.md`](results/2026-09-05-two-spark-validation.md).

The matching external vLLM/B12X/model reference reports 36.0 tok/s prose and
66.4 tok/s structured output with DSpark K6. Workload and measurement
boundaries differ, so those values should not be directly compared to this
implementation-oriented benchmark.

The packaged orchestration revision differs from the now-unfetchable eugr
commit recorded by that reference, but the successful live build confirmed
the locked vLLM, B12X, model, and SM121 composition used by this package.

## Context And Memory

The checkpoint advertises 1,048,576 tokens, but 327,680 is the base because it
is the published full-quality two-Spark operating point with useful memory
margin. A reference run measured a roughly 399K-token KV pool at comparable
settings. A 524,288 override therefore requires re-profiling and higher memory
pressure; unified-memory exhaustion can hang a Spark instead of producing a
clean process OOM.

Do not raise context until both text and image smoke tests pass and the
inspector shows stable memory. Lower `max_num_seqs` before reducing the base
context if startup is tight.

## Native Runtime Gate

`mods/deepseek-v4-vision-native-check` is check-only. It verifies the native
ViT, aligner, image sentinels, `bias_vl`, multimodal registry, DSpark class,
and exact vLLM/B12X build provenance before the server starts. It never writes
to the container. An ordinary prebuilt `vllm-node-b12x` fails this gate rather
than silently loading the checkpoint as text-only.

Set `DSV4FV_STRICT_PINS=0` only when deliberately testing a rebuilt image with
reviewed source revisions. Native feature checks still run.

## Troubleshooting

- `There is no module or parameter named 'aligner'` means a text-only vLLM
  build was used. Rebuild `vllm-node-dsv4fv`; do not suppress the native gate.
- `Could not find remote branch <commit>` while cloning B12X means an older
  package version passed the immutable SHA to `git clone --branch`. Reinstall
  version 0.1.2 or later and rerun setup. Version 0.1.2 also ensures the build
  runs from the patched checkout rather than resolving the user's unpatched
  top-level Dockerfile.
- A native-gate pin failure means the image tag points to a different build.
  Run the inspector and rebuild/copy the custom image to both nodes.
- A B12X mHC epsilon error means the image does not contain the pinned B12X branch.
- If model loading is killed, stop other workloads, confirm swap, and verify
  InstantTensor is active. Do not increase `gpu_memory_utilization` first.
- If DSpark counters remain zero, inspect logs for the DSpark draft class and
  confirm the three MTP layers loaded from the same pinned checkpoint.
- If image requests fail while text passes, inspect for
  `DeepseekV4ForConditionalGeneration`, image-sentinel, and `bias_vl` log lines.

## Uninstall

```bash
bash uninstall.sh ~/spark-vllm-docker
```

This removes only package-owned installed paths. It leaves backups, the
`.dsv4fv-build` cache, model weights, Docker images, and running containers.

## Development Validation

```bash
python3 -m pip install pyyaml
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_native_check.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_package.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_wrapper.py
DSV4FV_BUILD_DIR=/tmp/dsv4fv-build \
  bash tools/deepseek-v4-vision-build.sh --prepare-only
```

GitHub Actions additionally installs the package into the prepared pinned
eugr checkout and dry-runs both recipes on every push and pull request.

## References

- <https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash-Vision-Exp>
- <https://github.com/vllm-project/vllm/pull/54566>
- <https://recipes.vllm.ai/deepseek-ai/DeepSeek-V4-Flash-Vision-Exp>
- <https://github.com/eugr/spark-vllm-docker>
- <https://github.com/shige0501/dsv4-vision-spark>
- <https://github.com/PixelML/DeepSeek-V4-Flash-Vision-Exp-DGX-Spark>
- <https://github.com/sfxnz/DeepSeek-V4-Flash-Vision-Exp-vLLM-2x-DGX-Spark>
- <https://github.com/local-inference-lab/b12x/pull/301>
- <https://github.com/local-inference-lab/b12x/pull/306>
