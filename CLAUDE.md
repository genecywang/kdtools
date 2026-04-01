# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

kdtools is a Kubernetes network debug tool — a Docker container that runs an HTTP server (`socat_server.sh`) to simulate CPU, memory, and lock contention loads. It's used for Kubernetes resource testing and network debugging.

## Build & Run

```bash
# Build the Docker image
docker build -t kdtools .

# Run the container (default port 80)
docker run -p 8080:80 kdtools

# Run with a custom port
docker run -e PORT=8888 -p 8888:8888 kdtools

# Debug: run a shell instead of the server
docker run -it kdtools bash
```

There are no test suites or linting configurations. Manual testing is done by hitting the HTTP endpoints after starting the container.

## Architecture

The entire application is `socat_server.sh`. It uses `socat` to implement a raw HTTP/1.1 server that routes requests to load-simulation functions:

| Endpoint | Function | Default |
|----------|----------|---------|
| `/cpu[/<sec>]` | Busy-loop CPU burn | 5s |
| `/cpulock[/<sec>]` | Serialized CPU burn via file lock (`/tmp/locks/global.lock`) | 10s |
| `/mem[/<mb>]` | Allocate memory in `/dev/shm/load/` | 200MB |
| `/memfree` | Free all files under `/dev/shm/load/` | — |
| `/help` | List endpoints | — |

**Signal handling**: The server traps `SIGTERM`/`SIGINT` to kill the socat child process and exit cleanly — important for Kubernetes pod lifecycle.

**Memory note**: `/dev/shm` is a tmpfs limited to 64MB by default in containers. To test larger allocations, mount a Kubernetes `emptyDir` volume at `/dev/shm`.

## Key Implementation Details

- The server forks a socat process per request; the main loop manages the PID for cleanup.
- CPU lock contention is implemented using `flock` on `/tmp/locks/global.lock`, serializing concurrent `/cpulock` requests.
- Response headers include path, timestamp, hostname, and socket info — useful for debugging routing and load balancing in Kubernetes.
