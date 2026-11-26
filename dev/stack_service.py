#!/usr/bin/env python3
"""Supervise one local dev process so separate sandboxed shells can stop it."""

import os
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path


def paths(state: Path, name: str) -> tuple[Path, Path, Path]:
    return (state / f"{name}.pid", state / f"{name}.sock", state / f"{name}.log")


def request(sock_path: Path, message: bytes) -> bytes:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(2)
        client.connect(str(sock_path))
        client.sendall(message)
        return client.recv(32)


def serve(state: Path, name: str, cwd: str, command: list[str]) -> None:
    pid_path, sock_path, _ = paths(state, name)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(sock_path))
    os.chmod(sock_path, 0o600)
    server.listen(2)
    server.settimeout(0.5)
    child = subprocess.Popen(command, cwd=cwd, start_new_session=True)
    pid_path.write_text(f"{os.getpid()}\n")

    try:
        while child.poll() is None:
            try:
                connection, _ = server.accept()
            except socket.timeout:
                continue
            with connection:
                message = connection.recv(32)
                if message == b"ping":
                    connection.sendall(b"up")
                elif message == b"stop":
                    connection.sendall(b"stopping")
                    break
    finally:
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=6)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
        server.close()
        sock_path.unlink(missing_ok=True)
        pid_path.unlink(missing_ok=True)


def start(state: Path, name: str, cwd: str, command: list[str]) -> None:
    pid_path, sock_path, log_path = paths(state, name)
    if sock_path.exists():
        try:
            if request(sock_path, b"ping") == b"up":
                return
        except OSError:
            sock_path.unlink(missing_ok=True)
    pid_path.unlink(missing_ok=True)
    with log_path.open("ab") as log:
        subprocess.Popen(
            [sys.executable, __file__, "serve", str(state), name, cwd, *command],
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    for _ in range(50):
        try:
            if request(sock_path, b"ping") == b"up":
                return
        except OSError:
            pass
        time.sleep(0.1)
    raise SystemExit(f"{name} supervisor did not start; see {log_path}")


def main() -> None:
    operation, state_text, name, *args = sys.argv[1:]
    state = Path(state_text)
    pid_path, sock_path, _ = paths(state, name)
    if operation == "start":
        start(state, name, args[0], args[1:])
    elif operation == "serve":
        serve(state, name, args[0], args[1:])
    elif operation in ("ping", "stop"):
        try:
            answer = request(sock_path, operation.encode())
        except OSError:
            raise SystemExit(1) from None
        if operation == "ping":
            if answer != b"up":
                raise SystemExit(1)
        else:
            for _ in range(60):
                if not sock_path.exists() and not pid_path.exists():
                    return
                time.sleep(0.1)
            raise SystemExit(f"{name} did not stop")
    else:
        raise SystemExit(f"unknown operation: {operation}")


if __name__ == "__main__":
    main()
