#!/usr/bin/env python3
"""kdtools - HTTP server for Kubernetes load simulation and HPA testing."""

import os
import signal
import socket
import threading
import time
import multiprocessing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", 80))

cpu_lock = threading.Lock()
mem_procs: list[multiprocessing.Process] = []
mem_lock = threading.Lock()


# --- Load workers (run in separate processes) ---

def _cpu_worker(seconds: float) -> None:
    end = time.time() + seconds
    while time.time() < end:
        pass


def _mem_worker(mb: int) -> None:
    """Hold anonymous memory until terminated. Ignores SIGHUP."""
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    size = mb * 1024 * 1024
    buf = bytearray(size)
    # Touch every page to ensure physical allocation (not just virtual)
    for i in range(0, size, 4096):
        buf[i] = 1
    signal.pause()


# --- Load functions called by HTTP handlers ---

def burn_cpu(seconds: float) -> None:
    """Burn one full CPU core for the given duration (blocks until done)."""
    p = multiprocessing.Process(target=_cpu_worker, args=(seconds,), daemon=True)
    p.start()
    p.join()


def mem_alloc(mb: int) -> None:
    """Allocate anonymous memory in a background process."""
    p = multiprocessing.Process(target=_mem_worker, args=(mb,), daemon=False)
    p.start()
    with mem_lock:
        mem_procs.append(p)


def mem_free() -> None:
    """Terminate all memory-holding processes."""
    with mem_lock:
        for p in mem_procs:
            p.terminate()
        mem_procs.clear()


# --- HTTP handler ---

HELP = """\
Available endpoints:

  /help               Show this help message.
  /cpu                Burn CPU for 5s (one core per request).
  /cpu/<sec>          Burn CPU for <sec> seconds.
  /cpulock            Serialized CPU burn for 10s (global lock).
  /cpulock/<sec>      Serialized CPU burn for <sec> seconds.
  /mem                Allocate 200MB anonymous memory.
  /mem/<mb>           Allocate <mb> MB anonymous memory.
  /memfree            Free all allocated memory.

Notes:
  - Each concurrent /cpu request saturates one core.
    Send multiple requests in parallel to raise total CPU pressure.
  - /mem uses anonymous memory counted as working_set by cgroups,
    making it visible to metrics-server for HPA memory scaling.
"""


# IPv4, IPv6, and IPv4-mapped IPv6 loopback addresses
LOCALHOST = {"127.0.0.1", "::1", "::ffff:127.0.0.1"}


def _to_int(s: str, default: int) -> int:
    try:
        return int(s)
    except ValueError:
        return default


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        parts = [p for p in path.split("/") if p]

        if path != "/" and self.client_address[0] not in LOCALHOST:
            self._send_forbidden()
            return

        match parts:
            case ["help"] | [] if path in ("/help", "/"):
                body = HELP
            case ["cpu"]:
                burn_cpu(5)
                body = "CPU burn 5s"
            case ["cpu", secs]:
                n = _to_int(secs, 5)
                burn_cpu(n)
                body = f"CPU burn {n}s"
            case ["cpulock"]:
                with cpu_lock:
                    burn_cpu(10)
                body = "CPU lock (serialized) + burn 10s"
            case ["cpulock", secs]:
                n = _to_int(secs, 10)
                with cpu_lock:
                    burn_cpu(n)
                body = f"CPU lock (serialized) + burn {n}s"
            case ["mem"]:
                mem_alloc(200)
                body = "MEM alloc 200MB"
            case ["mem", mb]:
                n = _to_int(mb, 200)
                mem_alloc(n)
                body = f"MEM alloc {n}MB"
            case ["memfree"]:
                mem_free()
                body = "MEM freed"
            case _:
                body = "OK"

        self._send(body)

    def _send(self, body: str) -> None:
        content = "\n".join([
            f"Path: {self.path}",
            f"Date: {time.strftime('%a %b %d %H:%M:%S UTC %Y', time.gmtime())}",
            f"HostName: {socket.gethostname()}",
            f"Server: {self.server.server_address[0]}:{self.server.server_address[1]}",
            f"Client: {self.client_address[0]}:{self.client_address[1]}",
            "",
            body,
            "",
        ]).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def _send_forbidden(self) -> None:
        self.send_response(403)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", "14")
        self.end_headers()
        self.wfile.write(b"403 Forbidden\n")

    def do_HEAD(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} - {fmt % args}", flush=True)


def main():
    multiprocessing.set_start_method("fork")
    server = ThreadingHTTPServer(("", PORT), Handler)

    def shutdown(signum, frame):
        print("Shutting down...", flush=True)
        mem_free()
        threading.Thread(target=server.shutdown).start()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    print(f"Listening on port {PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
