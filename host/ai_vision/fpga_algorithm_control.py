#!/usr/bin/env python3
"""Send OV5640 image-effect commands through the FPGA over raw Ethernet."""

from __future__ import annotations

import ctypes
from dataclasses import dataclass
import os
import threading
import time
from typing import Final

from cam1_live_viewer import configure_wpcap, find_capture_interface, load_wpcap


# The source address is configurable and defaults to a neutral locally
# administered address; do not bake a developer machine's NIC MAC into the repo.
FPGA_MAC: Final[bytes] = bytes.fromhex("020000000025")
HOST_MAC: Final[bytes] = bytes.fromhex(
    os.environ.get("CAM1_HOST_MAC", "020000000001").replace(":", "").replace("-", "")
)
CONTROL_ETHERTYPE: Final[bytes] = bytes.fromhex("88B5")
MODE_NAMES: Final[dict[int, str]] = {
    0: "彩色",
    1: "灰度",
    2: "OV5640黑白效果",
    3: "OV5640负片效果",
}
MODE_VALUES: Final[dict[str, int]] = {
    "color": 0,
    "gray": 1,
    "binary": 2,
    "blackwhite": 2,
    "invert": 3,
}


@dataclass(frozen=True)
class AlgorithmRequest:
    mode: int
    threshold: int
    sequence: int
    sent_at: float


def build_control_frame(
    mode: int,
    threshold: int,
    sequence: int,
    source_mac: bytes = HOST_MAC,
    destination_mac: bytes = FPGA_MAC,
) -> bytes:
    if mode not in MODE_NAMES:
        raise ValueError("OV5640 image mode must be 0..3")
    if not 0 <= threshold <= 255 or not 0 <= sequence <= 255:
        raise ValueError("threshold and sequence must be bytes")
    if len(source_mac) != 6 or len(destination_mac) != 6:
        raise ValueError("Ethernet MAC addresses must contain six bytes")
    checksum = 0xA5 ^ sequence ^ mode ^ threshold
    command = b"FALG" + bytes((1, sequence, mode, threshold, checksum))
    return destination_mac + source_mac + CONTROL_ETHERTYPE + command + bytes(60 - 14 - len(command))


class FpgaAlgorithmController:
    """Thread-safe Npcap sender for OV5640 image effects handled by the FPGA."""

    def __init__(self, interface_selector: str | None = None) -> None:
        self.interface_selector = interface_selector
        self._lock = threading.Lock()
        self._sequence = 0

    def synchronize_sequence(self, sequence: int) -> None:
        with self._lock:
            self._sequence = sequence & 0xFF

    def select(self, mode: int | str, threshold: int = 128) -> AlgorithmRequest:
        numeric_mode = MODE_VALUES[mode] if isinstance(mode, str) else mode
        with self._lock:
            self._sequence = (self._sequence + 1) & 0xFF
            request = AlgorithmRequest(
                mode=numeric_mode,
                threshold=threshold,
                sequence=self._sequence,
                sent_at=time.monotonic(),
            )
            self._send(build_control_frame(numeric_mode, threshold, self._sequence))
            return request

    def _send(self, frame: bytes) -> None:
        wpcap = load_wpcap()
        configure_wpcap(wpcap)
        interface = find_capture_interface(wpcap, self.interface_selector)
        error_buffer = ctypes.create_string_buffer(256)
        handle = wpcap.pcap_create(interface.name, error_buffer)
        if not handle:
            raise RuntimeError(error_buffer.value.decode(errors="replace"))
        try:
            if wpcap.pcap_set_snaplen(handle, 1600) != 0:
                raise RuntimeError("Npcap control snaplen setup failed")
            if wpcap.pcap_set_promisc(handle, 1) != 0:
                raise RuntimeError("Npcap control promiscuous setup failed")
            if wpcap.pcap_set_timeout(handle, 10) != 0:
                raise RuntimeError("Npcap control timeout setup failed")
            if wpcap.pcap_activate(handle) < 0:
                raise RuntimeError(wpcap.pcap_geterr(handle).decode(errors="replace"))
            array = (ctypes.c_ubyte * len(frame)).from_buffer_copy(frame)
            if wpcap.pcap_sendpacket(handle, array, len(frame)) != 0:
                raise RuntimeError(wpcap.pcap_geterr(handle).decode(errors="replace"))
        finally:
            wpcap.pcap_close(handle)


