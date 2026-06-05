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
