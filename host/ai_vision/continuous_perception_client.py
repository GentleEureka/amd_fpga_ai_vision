"""Small localhost client used by the CAM1 MCP bridge."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import time
from typing import Any
from urllib.error import URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


BASE_URL = "http://127.0.0.1:8765"
ROOT = Path(__file__).resolve().parent


def _request(path: str, *, timeout: float = 3.0) -> bytes:
    request = Request(f"{BASE_URL}{path}", headers={"Accept": "application/json"})
    with urlopen(request, timeout=timeout) as response:
        return response.read()


def get_json(path: str, *, timeout: float = 3.0) -> dict[str, Any]:
    return json.loads(_request(path, timeout=timeout).decode("utf-8"))


def get_frame(timeout: float = 3.0) -> bytes:
    return _request("/frame.jpg", timeout=timeout)


def health() -> dict[str, Any]:
    return get_json("/health")


def is_running() -> bool:
    try:
        return bool(get_json("/health", timeout=0.5).get("ok"))
    except (OSError, URLError, ValueError):
        return False


def ensure_running(wait_seconds: float = 8.0) -> bool:
    """Start the independent perception daemon if its local API is absent."""
    if is_running():
        return True
    script = ROOT / "continuous_perception.py"
    pythonw = Path(sys.executable).with_name("pythonw.exe")
    executable = pythonw if pythonw.exists() else Path(sys.executable)
    creation_flags = 0
    if os.name == "nt":
        creation_flags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
    try:
        subprocess.Popen(
            [str(executable), str(script)],
            cwd=str(ROOT),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            close_fds=True,
            creationflags=creation_flags,
        )
    except OSError:
        return False
    deadline = time.monotonic() + wait_seconds
    while time.monotonic() < deadline:
        if is_running():
            return True
        time.sleep(0.2)
    return False


def status() -> dict[str, Any]:
    return get_json("/status")


def scene() -> dict[str, Any]:
    return get_json("/scene")


def events(
    seconds: float = 900.0, limit: int = 30, include_pending: bool = False
) -> dict[str, Any]:
    return get_json(
        f"/events?{urlencode({'seconds': seconds, 'limit': limit, 'include_pending': str(include_pending).lower()})}"
    )


def candidates(seconds: float = 120.0, limit: int = 50) -> dict[str, Any]:
    return get_json(f"/candidates?{urlencode({'seconds': seconds, 'limit': limit})}")


def event_audit(limit: int = 100, candidate_id: str | None = None) -> dict[str, Any]:
    values: dict[str, Any] = {"limit": limit}
    if candidate_id:
        values["candidate_id"] = candidate_id
    return get_json(f"/event-audit?{urlencode(values)}")


def understandings(seconds: float = 10.0, limit: int = 10) -> dict[str, Any]:
    return get_json(
        f"/understandings?{urlencode({'seconds': seconds, 'limit': limit})}"
    )


def search_memory(query: str, seconds: float = 1800.0, limit: int = 30) -> dict[str, Any]:
    return get_json(
        f"/search?{urlencode({'q': query, 'seconds': seconds, 'limit': limit})}"
    )
