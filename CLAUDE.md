# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

kdtools is a Kubernetes load simulation tool — a Docker container running a Python HTTP server (`server.py`) used to trigger CPU, memory, and lock contention pressure for testing Kubernetes HPA and network debugging.

## Build & Run

```bash
# Build and push multi-arch image (linux/amd64 + linux/arm64)
make push

# Build locally without push
make build

# Run locally
docker run -p 8080:80 kdtools

# Custom port
docker run -e PORT=8888 -p 8888:8888 kdtools

# Debug shell
docker run -it kdtools bash
```

Version is managed in `Makefile` (`VERSION := x.y.z`). There are no test suites or linting configurations — manual testing is done by hitting HTTP endpoints after starting the container.

The Makefile auto-detects the buildx builder: uses `desktop-linux` (Docker Desktop) if available, otherwise falls back to `default`. On Linux without Docker Desktop, if `default` doesn't support multi-arch, create one first and pass it explicitly:

```bash
docker buildx create --name multiarch --driver docker-container --use
BUILDER=multiarch make push
```

## Architecture

The entire application is `server.py` (~130 lines). It uses `http.server.ThreadingHTTPServer` (stdlib) with a single `Handler` class.

| Endpoint | Behaviour | Default |
|----------|-----------|---------|
| `/cpu[/<sec>]` | Spawns a subprocess to busy-loop one full CPU core | 5s |
| `/cpulock[/<sec>]` | Same, but serialized via a `threading.Lock` | 10s |
| `/mem[/<mb>]` | Spawns a persistent background process holding anonymous memory | 200MB |
| `/memfree` | Terminates all memory-holding processes | — |
| `/help` | Lists endpoints | — |

## Key Implementation Details

**CPU burn** uses `multiprocessing.Process` (not threads) to bypass Python's GIL — each concurrent `/cpu` request saturates one full core. The handler blocks with `p.join()` until the burn completes.

**Memory allocation** spawns a `daemon=False` background process that allocates a `bytearray` and touches every page to ensure physical allocation. This produces anonymous memory counted as `working_set` by cgroups, making it visible to metrics-server and HPA. The process persists until `/memfree` or server shutdown. `/dev/shm`-based (tmpfs) allocation is intentionally avoided as it lands in `inactive_file` and is excluded from `working_set`.

**`/cpulock`** serializes concurrent requests via a module-level `threading.Lock`, simulating lock contention / serialized resource access — distinct from `/cpu` which runs requests fully in parallel.

**Signal handling**: `SIGTERM`/`SIGINT` call `mem_free()` to terminate all background memory processes before shutting down the HTTP server — important for clean Kubernetes pod termination.

**`multiprocessing.set_start_method("fork")`** is set at startup so child processes inherit the parent's memory state without re-importing modules.

**Access control**: `/` is open to all sources. Every other endpoint requires the client to be localhost (`127.0.0.1`, `::1`, or `::ffff:127.0.0.1`) — non-localhost requests receive `403 Forbidden`.
