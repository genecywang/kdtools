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
  python3 -c "
import time
end = time.time() + $seconds
while time.time() < end:
    pass
"
}

# Simulate CPU blocking via global lock contention.
# All concurrent requests compete for the same lock and are serialized.
cpu_lock() {
  local seconds="${1:-10}"
  mkdir -p /tmp/locks
  local lockfd
  exec {lockfd}>/tmp/locks/global.lock
  flock "$lockfd"
  # Hold the lock while burning CPU to simulate blocking + CPU pressure
  burn_cpu "$seconds"
  flock -u "$lockfd"
  exec {lockfd}>&-
}

# Allocate anonymous memory via a background Python process.
# Anonymous memory is counted as working_set by cgroups, so it is visible
# to metrics-server and triggers HPA scaling.
mem_alloc_mb() {
  local mb="${1:-200}"
  local bytes=$(( mb * 1024 * 1024 ))
  mkdir -p /tmp/memhold
  python3 -c "
import os, signal
signal.signal(signal.SIGHUP, signal.SIG_IGN)
buf = bytearray($bytes)
for i in range(0, $bytes, 4096):
    buf[i] = 1
open(f'/tmp/memhold/{os.getpid()}.pid', 'w').close()
signal.pause()
" &
  disown
}

# Kill all background memory-holding processes
mem_free() {
  if [ -d /tmp/memhold ]; then
    for pidfile in /tmp/memhold/*.pid; do
      [ -f "$pidfile" ] || continue
      pid="${pidfile%.pid}"
      pid="${pid##*/}"
      kill "$pid" 2>/dev/null || true
    done
    rm -rf /tmp/memhold
  fi
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

# Consume remaining HTTP headers until blank line
while IFS= read -r header; do
  header="${header%%$'\r'}"
  [ -z "$header" ] && break
done

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
    [[ "$SECS" =~ ^[0-9]+$ ]] || SECS=5
    burn_cpu "$SECS"
    BODY="CPU burn ${SECS}s"
    ;;
  /cpulock)
    cpu_lock 10
    BODY="CPU lock (serialized) + burn 10s"
    ;;
  /cpulock/*)
    SECS=$(echo "$REQUEST_PATH" | cut -d/ -f3)
    [[ "$SECS" =~ ^[0-9]+$ ]] || SECS=10
    cpu_lock "$SECS"
    BODY="CPU lock (serialized) + burn ${SECS}s"
    ;;
  /mem)
    mem_alloc_mb 200
    BODY="MEM alloc 200MB (/dev/shm)"
    ;;
  /mem/*)
    MB=$(echo "$REQUEST_PATH" | cut -d/ -f3)
    [[ "$MB" =~ ^[0-9]+$ ]] || MB=200
    mem_alloc_mb "$MB"
    BODY="MEM alloc ${MB}MB (/dev/shm)"
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
