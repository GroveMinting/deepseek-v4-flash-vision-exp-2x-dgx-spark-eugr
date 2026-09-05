# Attribution and implementation boundary

## Runtime composition

The installed recipes execute:

```text
eugr/spark-vllm-docker orchestration
+ pinned shige0501/vllm native DeepSeek V4 Vision implementation
+ pinned B12X SM121 kernels
+ deepseek-ai/DeepSeek-V4-Flash-Vision-Exp
+ package recipes and a read-only compatibility gate
```

This package does not distribute model weights, vLLM, B12X, or a container
image. Each fetched component remains subject to its own license and terms.

## Model

`deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` is referenced at revision
`e46e16bf6035c6f317eb2ac7458eb0362926d402`. Its repository declares the MIT
license and includes approximately 167.8 GB of SafeTensors shards. The
checkpoint itself contains the language model, 32-layer vision encoder,
aligner, image sentinel embeddings, modality-specific `bias_vl` routing, and
three DSpark prediction layers.

## Runtime sources

- `eugr/spark-vllm-docker` supplies MIT-licensed DGX Spark image builds,
  recipes, model distribution, and TP2 no-Ray orchestration. The package pins
  commit `acd5d2a253704ad71096c5f23ac45e7cf57442af`. The measured reference's
  recorded eugr commit is no longer fetchable from the public repository.
- `shige0501/vllm` is an Apache-2.0-licensed vLLM fork. Commit
  `f6892f8fed7cb01e7df8d96f09c7f96167f0ef43` contains the native Vision-Exp
  implementation derived from upstream PR #54566 plus documented GB10 fixes.
  No vLLM source is injected at container startup.
- `shige0501/b12x` commit `fbba9c93b37191d258b89a40962603cc4c68b085`
  is the Apache-2.0-licensed `topk512-dual` branch. It is built as a package by
  eugr's source-build process.

## Structural references

- `shige0501/dsv4-vision-spark` supplied the complete runtime pins and informed
  the 327,680-token TP2 operating point, B12X backend selection, 0.84 memory
  reservation, image-span attention requirements, and published 36.0/66.4
  tok/s prose/structured measurements.
- `PixelML/DeepSeek-V4-Flash-Vision-Exp-DGX-Spark` informed native image smoke
  validation, concurrency benchmarking, and the published two-Spark throughput
  range. Its third-party runtime is not included.
- `sfxnz/DeepSeek-V4-Flash-Vision-Exp-vLLM-2x-DGX-Spark` informed long-context
  operational cautions. Its plugin overlay is not included.
- Local `Qwen3.8dflash2` and `deepseek-v4-0731-eugr_patch` packages informed the
  standalone installer, collision backup, uninstaller, staged recipes, smoke
  tests, inspector, benchmark, manifest, and fail-closed validation layout.

## Package-owned work

The recipes, build wrapper, read-only native-runtime checker, lifecycle
scripts, smoke tests, benchmark, and documentation are integration work
released under this package's MIT license. No third-party patch file or model
implementation is copied into this package.

## Boundaries

This package does not include a vision overlay, model sidecar, alternate model
weights, 1M-context default, NVFP4 KV cache, or locally measured performance.
All throughput numbers in the documentation are explicitly identified as
external reference measurements.

## Links

- <https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash-Vision-Exp>
- <https://github.com/vllm-project/vllm/pull/54566>
- <https://github.com/eugr/spark-vllm-docker>
- <https://github.com/local-inference-lab/b12x/pull/301>
- <https://github.com/local-inference-lab/b12x/pull/306>
- <https://github.com/shige0501/dsv4-vision-spark>
- <https://github.com/PixelML/DeepSeek-V4-Flash-Vision-Exp-DGX-Spark>
- <https://github.com/sfxnz/DeepSeek-V4-Flash-Vision-Exp-vLLM-2x-DGX-Spark>
