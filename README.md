# Meetily Debian Builder

Builds an installable Linux `.deb` for Meetily from the upstream source repo:

https://github.com/Zackriya-Solutions/meetily

The workflow builds Meetily on Ubuntu 24.04 and then repacks the generated Tauri
package so it installs under `/opt/meetily` instead of conflicting with system
files such as `/usr/bin/ffmpeg`.

GitHub-hosted runners do not provide an NVIDIA/AMD GPU, so the default artifact
is a portable CPU-only Linux package. GPU-enabled packages need a self-hosted
runner with the matching GPU SDK installed, such as CUDA for NVIDIA or ROCm for
AMD.

## GPU Runbook

Official upstream Linux GPU build notes:

https://github.com/Zackriya-Solutions/meetily/blob/main/docs/building_in_linux.md

For NVIDIA, drivers alone are not enough. A CUDA-capable build needs `nvidia-smi`
plus the CUDA toolkit / `nvcc`, and the running binaries must be CUDA-linked.

On the local workstation, the June 16, 2026 issue was a mixed install:

- `/opt/meetily/bin/meetily`
- `/opt/meetily/bin/llama-helper`

That path launched a CPU-only `llama-helper`. The CUDA-enabled build was already
installed at:

- `/opt/meetily/current/bin/meetily`
- `/opt/meetily/current/bin/llama-helper`

The local user-level override is:

- `/home/lucky-verma/.local/bin/meetily`
- `/home/lucky-verma/.local/share/applications/meetily.desktop`

It launches `/opt/meetily/current/bin/meetily`, sets
`MEETILY_LLAMA_HELPER=/opt/meetily/current/bin/llama-helper`, and prepends
`/usr/local/cuda/lib64` to `LD_LIBRARY_PATH`.

Verify while regenerating a summary:

```bash
ps -eo pid,comm,args | rg 'meetily|llama-helper'
nvidia-smi
```

Expected signs:

- process path: `/opt/meetily/current/bin/llama-helper`
- `nvidia-smi` process type: `C`
- GPU memory around 3 GB for the Qwen3.5 4B summary model

`ggml_cuda_graph_set_enabled: disabling CUDA graphs due to GPU architecture` is
normal on the RTX 2070 SUPER and does not mean CPU fallback.

## Build

Run **Actions -> Build Meetily Debian package -> Run workflow**.

The finished package is uploaded as a workflow artifact:

`meetily-deb/meetily_<version>+meetily1_amd64.deb`

## Install

```bash
sudo apt install ./meetily_<version>_amd64.deb
meetily
```

## Update

The package installs:

- `/usr/local/bin/meetily`
- `/usr/local/bin/meetily-update`

`meetily-update` looks for a Linux `.deb` release asset. If no release asset
exists yet, run this workflow and install the uploaded artifact, or publish a
release from this builder repo.
