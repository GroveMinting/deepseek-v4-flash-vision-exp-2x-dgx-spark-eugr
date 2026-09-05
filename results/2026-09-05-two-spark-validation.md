# Two-Spark Validation Receipt

Date: 2026-09-05

Status: PASS

This receipt records the first live validation of this package on two NVIDIA
DGX Sparks. Hostnames and network addresses are intentionally omitted.

## Configuration

| Item | Value |
|---|---|
| Model | `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` |
| Model revision | `e46e16bf6035c6f317eb2ac7458eb0362926d402` |
| Hardware | Two NVIDIA DGX Sparks |
| Parallelism | TP2 |
| Context limit | 327,680 tokens |
| KV cache | FP8 |
| Speculative decoding | DSpark K6 |
| Image | `vllm-node-dsv4fv` |
| Container restarts | 0 |

## Throughput

The dependency-free package benchmark used its default implementation-guide
prompt, `temperature=0`, thinking disabled, and exactly 512 generated tokens
per request. These are warm-server measurements.

Commands:

```bash
./tools/deepseek-v4-vision-benchmark.py \
  --warmups 2 --runs 3 --max-tokens 512

./tools/deepseek-v4-vision-benchmark.py \
  --concurrency 8 --warmups 1 --runs 3 --max-tokens 512
```

| Metric | C1 median | C8 median |
|---|---:|---:|
| TTFT | 0.352 s | 0.393 s |
| Per-request decode | 50.917 tok/s | 11.589 tok/s |
| Aggregate end-to-end | 49.204 tok/s | 89.908 tok/s |
| DSpark acceptance | 41.8% | 40.6% |

C1 aggregate samples were 49.20, 49.53, and 49.16 tok/s. C8 aggregate
samples were 89.37, 91.72, and 89.91 tok/s. C8 delivered 1.83 times the C1
aggregate throughput while median TTFT remained below 400 ms.

The measured DSpark counter deltas were:

| Run | Accepted | Drafted | Ratio |
|---|---:|---:|---:|
| C1 measured runs | 1,100 | 2,634 | 0.418 |
| C8 measured runs | 8,729 | 21,492 | 0.406 |

## Functional Smoke Test

Command:

```bash
REQUIRE_DSPARK=1 ./tools/deepseek-v4-vision-smoke.sh
```

Validated results:

| Gate | Result |
|---|---|
| Deterministic text | `DSV4_VISION_OK` |
| Native image understanding | `red blue` |
| Structured tool call | `report_probe {"status":"DSV4_TOOL_OK"}` |
| DSpark counters | 13,843 accepted / 33,803 drafted, ratio 0.410 |

The image gate used the smoke test's generated red/blue PNG through an OpenAI
`image_url` content block. It exercised the checkpoint's native ViT and
aligner rather than a sidecar or proxy.

## Runtime Provenance

| Component | Validated value |
|---|---|
| eugr build script | `acd5d2a253704ad71096c5f23ac45e7cf57442af` |
| vLLM | `0.1.dev20150+gf6892f8fe.d20260905` |
| vLLM commit | `f6892f8fed7cb01e7df8d96f09c7f96167f0ef43` |
| B12X commit | `fbba9c93b37191d258b89a40962603cc4c68b085` |
| FlashInfer commit | `18e5811d` |
| PyTorch | `2.13.0` |
| torchvision | `0.28.0` |
| torchaudio | `2.11.0` |
| CUTLASS DSL | `4.7.0` |
| GPU architecture | `12.1a` |
| Build time | `2026-09-05T13:23:41Z` |

The B12X package does not expose a useful `__version__` value in this build.
`/workspace/b12x-source-commit` independently confirmed the exact locked
commit above.

## Package CI

GitHub Actions workflow `Validate`, run 3, passed at commit
`4f73ec2bf8ad64155419af7aa040bc9f8a67b432`:

<https://github.com/GroveMinting/deepseek-v4-flash-vision-exp-2x-dgx-spark-eugr/actions/runs/33987495397>

## Scope And Limitations

- The API advertised the configured 327,680-token context limit, but this
  receipt did not submit a near-limit prompt.
- Every measured response reached the requested 512-token output cap.
- The benchmark prompt is implementation-oriented; these numbers should not
  be relabeled as unconstrained natural-prose measurements.
- Prefix-cache metrics reported zero hits. The validation prompts were shorter
  than the configured 256-token cache block, so this does not test repeated
  long-prompt prefix caching.
- CUDA graph capture remained at the package's conservative size 32. Size 64
  is reserved for a separately measured v2 experiment.
- Driver, firmware, interconnect, power, and clock telemetry were not captured
  in this receipt and should not be inferred.
