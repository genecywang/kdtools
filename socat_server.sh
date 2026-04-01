#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-80}"
SOCAT_PID=""

cleanup() {
  echo "Cleaning up..."
  if [ -n "${SOCAT_PID}" ] && kill -0 "${SOCAT_PID}" 2>/dev/null; then
    kill -SIGTERM "${SOCAT_PID}" || true
    wait "${SOCAT_PID}" || true
  fi
  exit 0
}

trap cleanup INT TERM

# Burn CPU for the given number of seconds (busy loop).
# Each request consumes ~100% of one CPU core.
burn_cpu() {
  local seconds="${1:-5}"
  local end=$(( $(date +%s) + seconds ))
  while [ "$(date +%s)" -lt "$end" ]; do :; done
}

# Simulate CPU blocking via global lock contention.
# All concurrent requests compete for the same lock and are serialized.
cpu_lock() {
  local seconds="${1:-10}"
  mkdir -p /tmp/locks
  exec 9>/tmp/locks/global.lock
  flock 9
  # Hold the lock while burning CPU to simulate blocking + CPU pressure
  burn_cpu "$seconds"
  flock -u 9
}

# Allocate memory by writing files into /dev/shm (tmpfs, memory-backed).
# This increases memory usage and is useful for testing memory pressure / OOM.
mem_alloc_mb() {
  local mb="${1:-200}"
  mkdir -p /dev/shm/load

  # Use peer port + PID to avoid filename collisions
  local f="/dev/shm/load/${SOCAT_PEERPORT:-unknown}-${$}-${mb}mb.bin"

  # Write <mb> MB to /dev/shm to consume memory
  dd if=/dev/zero of="$f" bs=1M count="$mb" status=none
}

# Free all allocated memory files under /dev/shm/load
mem_free() {
  rm -rf /dev/shm/load 2>/dev/null || true
}

# Help text displayed at /help
help_text() {
  cat <<'EOF'
Available endpoints:

  /help
    Show this help message.

  /cpu
    Burn CPU for 5 seconds (one core per request).

  /cpu/<sec>
    Burn CPU for <sec> seconds.

  /cpulock
    Acquire a global lock, then burn CPU for 10 seconds.
    All concurrent /cpulock requests will block and run serially.

  /cpulock/<sec>
    Same as /cpulock, but with a custom duration.

  /mem
    Allocate 200MB in /dev/shm (memory-backed filesystem).

  /mem/<mb>
    Allocate <mb> MB in /dev/shm.

  /memfree
    Free all allocated memory under /dev/shm/load.

Notes:
- /dev/shm size inside containers may default to 64MB.
  For larger memory tests, mount an emptyDir with:
    medium: Memory
    sizeLimit: <size>
  to /dev/shm.
- /cpu burns one CPU core per request.
  Increase concurrency to raise total CPU pressure.
EOF
}

web() {
  local handler
  handler=$(mktemp /tmp/kdtools-handler.XXXXXX.sh)

  cat > "$handler" << 'HANDLER_EOF'
#!/usr/bin/env bash
# Read the first HTTP request line, e.g.: GET /path HTTP/1.1
read -r REQUEST_LINE || exit 0
REQUEST_PATH=$(echo "$REQUEST_LINE" | awk '{print $2}')

case "$REQUEST_PATH" in
  /help)
    BODY="$(help_text)"
    ;;
  /cpu)
    burn_cpu 5
    BODY="CPU burn 5s"
    ;;
  /cpu/*)
    SECS=$(echo "$REQUEST_PATH" | cut -d/ -f3)
    burn_cpu "${SECS:-5}"
    BODY="CPU burn ${SECS:-5}s"
    ;;
  /cpulock)
    cpu_lock 10
    BODY="CPU lock (serialized) + burn 10s"
    ;;
  /cpulock/*)
    SECS=$(echo "$REQUEST_PATH" | cut -d/ -f3)
    cpu_lock "${SECS:-10}"
    BODY="CPU lock (serialized) + burn ${SECS:-10}s"
    ;;
  /mem)
    mem_alloc_mb 200
    BODY="MEM alloc 200MB (/dev/shm)"
    ;;
  /mem/*)
    MB=$(echo "$REQUEST_PATH" | cut -d/ -f3)
    mem_alloc_mb "${MB:-200}"
    BODY="MEM alloc ${MB:-200}MB (/dev/shm)"
    ;;
  /memfree)
    mem_free
    BODY="MEM freed (/dev/shm/load removed)"
    ;;
  *)
    BODY="OK"
    ;;
esac

echo "HTTP/1.1 200 OK"
echo "Content-Type: text/plain"
echo
echo "Path: $REQUEST_PATH"
echo "Date: $(date)"
echo "HostName: $(uname -n)"
echo "Server: $SOCAT_SOCKADDR:$SOCAT_SOCKPORT"
echo "Client: $SOCAT_PEERADDR:$SOCAT_PEERPORT"
echo
echo "$BODY"
HANDLER_EOF

  socat -v -d -d \
    TCP-LISTEN:${PORT},reuseaddr,fork \
    SYSTEM:"bash $handler" &
  SOCAT_PID=$!
  wait "${SOCAT_PID}"
  rm -f "$handler"
}

case "${1:-start}" in
  start)
    # Export functions so they are available to socat SYSTEM
    export -f burn_cpu cpu_lock mem_alloc_mb mem_free help_text
    web
    ;;
  *)
    exec "$@"
    ;;
esac
