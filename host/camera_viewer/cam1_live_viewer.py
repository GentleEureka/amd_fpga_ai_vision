#!/usr/bin/env python3
"""Low-latency CAM1 viewer for the MC02 FPGA Ethernet video stream."""

from __future__ import annotations

import argparse
import ctypes
from dataclasses import dataclass
import io
from pathlib import Path
import queue
import re
import subprocess
import threading
import time
import tkinter as tk
from tkinter import font as tkfont

import numpy as np
from PIL import Image, ImageTk


LEGACY_WIDTH = 640
LEGACY_HEIGHT = 480
WIDTH = 1920
HEIGHT = 1080
FRAME_BYTES = LEGACY_WIDTH * LEGACY_HEIGHT * 2
FULL_PAYLOAD_BYTES = 1392
LAST_PAYLOAD_BYTES = 528
PACKETS_PER_FRAME = 442
SOURCE_IP = bytes((169, 254, 26, 95))
UDP_PORT = 5002
RGB565_MAGIC = b"OV56"
JPEG_MAGIC = b"OVJ2"
APP_HEADER_BYTES = 22


class TimeVal(ctypes.Structure):
    _fields_ = [("tv_sec", ctypes.c_long), ("tv_usec", ctypes.c_long)]


class PcapHeader(ctypes.Structure):
    _fields_ = [
        ("ts", TimeVal),
        ("caplen", ctypes.c_uint32),
        ("len", ctypes.c_uint32),
    ]


class BpfProgram(ctypes.Structure):
    _fields_ = [("bf_len", ctypes.c_uint), ("bf_insns", ctypes.c_void_p)]


class PcapStat(ctypes.Structure):
    _fields_ = [
        ("ps_recv", ctypes.c_uint),
        ("ps_drop", ctypes.c_uint),
        ("ps_ifdrop", ctypes.c_uint),
    ]


class PcapInterface(ctypes.Structure):
    pass


PcapInterface._fields_ = [
    ("next", ctypes.POINTER(PcapInterface)),
    ("name", ctypes.c_char_p),
    ("description", ctypes.c_char_p),
    ("addresses", ctypes.c_void_p),
    ("flags", ctypes.c_uint),
]


@dataclass(frozen=True)
class Frame:
    frame_id: int
    image_data: bytes
    encoding: str
    width: int
    height: int
    packet_count: int
    captured_at: float
    fpga_algorithm: int = 0
    fpga_threshold: int = 128
    fpga_sequence: int = 0
    fpga_metadata_valid: bool = False
    fpga_command_accepted_count: int = 0
    fpga_command_rejected_count: int = 0


@dataclass(frozen=True)
class PacketHeader:
    app_offset: int
    payload_bytes: int
    frame_id: int
    width: int
    height: int
    encoding: str
    sequence: int = 0
    flags: int = 0
    fpga_algorithm: int = 0
    fpga_threshold: int = 128
    fpga_sequence: int = 0
    fpga_metadata_valid: bool = False
    fpga_command_accepted_count: int = 0
    fpga_command_rejected_count: int = 0


class FrameAssembler:
    """Strict packet-order assembler for OVJ2, with legacy OV56 support."""

    def __init__(self) -> None:
        self.current_frame_id: int | None = None
        self.data = bytearray()
        self.packet_count = 0
        self.next_sequence = 0
        self.width = 0
        self.height = 0
        self.encoding = ""
        self.fpga_algorithm = 0
        self.fpga_threshold = 128
        self.fpga_sequence = 0
        self.fpga_metadata_valid = False
        self.fpga_command_accepted_count = 0
        self.fpga_command_rejected_count = 0
        self.complete_frames = 0
        self.partial_frames = 0
        self.malformed_packets = 0

    def reset(self) -> None:
        self.current_frame_id = None
        self.data = bytearray()
        self.packet_count = 0
        self.next_sequence = 0

    def consume(
        self, packet: PacketHeader, payload: bytes, captured_at: float
    ) -> Frame | None:
        if len(payload) != packet.payload_bytes:
            self.malformed_packets += 1
            return None
        if packet.encoding == "JPEG":
            return self._consume_jpeg(packet, payload, captured_at)
        return self._consume_legacy(packet, payload, captured_at)

    def _consume_jpeg(
        self, packet: PacketHeader, payload: bytes, captured_at: float
    ) -> Frame | None:
        start_of_frame = bool(packet.flags & 0x01)
        end_of_frame = bool(packet.flags & 0x02)
        if start_of_frame:
            if packet.sequence != 0 or not payload.startswith(b"\xff\xd8"):
                self.malformed_packets += 1
                self.reset()
                return None
            if self.current_frame_id is not None:
                self.partial_frames += 1
            self.current_frame_id = packet.frame_id
            self.data = bytearray()
            self.packet_count = 0
            self.next_sequence = 0
            self.width = packet.width
            self.height = packet.height
            self.encoding = packet.encoding
            self.fpga_algorithm = packet.fpga_algorithm
            self.fpga_threshold = packet.fpga_threshold
            self.fpga_sequence = packet.fpga_sequence
            self.fpga_metadata_valid = packet.fpga_metadata_valid
            self.fpga_command_accepted_count = packet.fpga_command_accepted_count
            self.fpga_command_rejected_count = packet.fpga_command_rejected_count
        elif self.current_frame_id is None:
            self.malformed_packets += 1
            return None

        if (
            packet.frame_id != self.current_frame_id
            or packet.sequence != self.next_sequence
            or packet.width != self.width
            or packet.height != self.height
        ):
            self.partial_frames += 1
            self.reset()
            return None

        self.data.extend(payload)
        self.packet_count += 1
        self.next_sequence += 1
        if len(self.data) > 8 * 1024 * 1024:
            self.malformed_packets += 1
            self.reset()
            return None
        if not end_of_frame:
            return None
        if not self.data.endswith(b"\xff\xd9"):
            self.malformed_packets += 1
            self.reset()
            return None

        frame = Frame(
            frame_id=packet.frame_id,
            image_data=bytes(self.data),
            encoding="JPEG",
            width=self.width,
            height=self.height,
            packet_count=self.packet_count,
            captured_at=captured_at,
            fpga_algorithm=self.fpga_algorithm,
            fpga_threshold=self.fpga_threshold,
            fpga_sequence=self.fpga_sequence,
            fpga_metadata_valid=self.fpga_metadata_valid,
            fpga_command_accepted_count=self.fpga_command_accepted_count,
            fpga_command_rejected_count=self.fpga_command_rejected_count,
        )
        self.complete_frames += 1
        self.reset()
        return frame

    def _consume_legacy(
        self, packet: PacketHeader, payload: bytes, captured_at: float
    ) -> Frame | None:
        if self.current_frame_id != packet.frame_id:
            if self.current_frame_id is not None and self.data:
                self.partial_frames += 1
            self.current_frame_id = packet.frame_id
            self.data = bytearray()
            self.packet_count = 0
            self.width = packet.width
            self.height = packet.height
            self.encoding = packet.encoding
            self.fpga_algorithm = packet.fpga_algorithm
            self.fpga_threshold = packet.fpga_threshold
            self.fpga_sequence = packet.fpga_sequence
            self.fpga_metadata_valid = packet.fpga_metadata_valid
            self.fpga_command_accepted_count = packet.fpga_command_accepted_count
            self.fpga_command_rejected_count = packet.fpga_command_rejected_count
        frame_bytes = packet.width * packet.height * 2
        packets_per_frame = (
            frame_bytes + FULL_PAYLOAD_BYTES - 1
        ) // FULL_PAYLOAD_BYTES
        last_payload_bytes = frame_bytes - (
            (packets_per_frame - 1) * FULL_PAYLOAD_BYTES
        )
        expected = (
            FULL_PAYLOAD_BYTES
            if self.packet_count < packets_per_frame - 1
            else last_payload_bytes
        )
        if packet.payload_bytes != expected:
            self.malformed_packets += 1
            self.reset()
            return None
        self.data.extend(payload)
        self.packet_count += 1
        if self.packet_count != packets_per_frame:
            return None
        if len(self.data) != frame_bytes:
            self.partial_frames += 1
            self.reset()
            return None
        frame = Frame(
            frame_id=packet.frame_id,
            image_data=bytes(self.data),
            encoding="RGB565",
            width=packet.width,
            height=packet.height,
            packet_count=self.packet_count,
            captured_at=captured_at,
            fpga_algorithm=self.fpga_algorithm,
            fpga_threshold=self.fpga_threshold,
            fpga_sequence=self.fpga_sequence,
            fpga_metadata_valid=self.fpga_metadata_valid,
            fpga_command_accepted_count=self.fpga_command_accepted_count,
            fpga_command_rejected_count=self.fpga_command_rejected_count,
        )
        self.complete_frames += 1
        self.reset()
        return frame


@dataclass(frozen=True)
class CaptureStats:
    complete_frames: int = 0
    partial_frames: int = 0
    malformed_packets: int = 0
    pcap_drops: int = 0
    interface_drops: int = 0


@dataclass(frozen=True)
class CaptureInterface:
    name: bytes
    description: str
    flags: int
    windows_connected: bool | None = None

    @property
    def is_connected(self) -> bool:
        if self.windows_connected is not None:
            return self.windows_connected
        # libpcap/Npcap PCAP_IF_CONNECTION_STATUS_CONNECTED.
        return self.flags & 0x30 == 0x10

    @property
    def guid(self) -> str:
        decoded = self.name.decode(errors="replace")
        return decoded.rsplit("_", 1)[-1]


def load_wpcap() -> ctypes.WinDLL:
    candidates = (
        Path(r"C:\Windows\System32\Npcap\wpcap.dll"),
        Path(r"C:\Windows\System32\wpcap.dll"),
    )
    for candidate in candidates:
        if candidate.exists():
            return ctypes.WinDLL(str(candidate))
    return ctypes.WinDLL("wpcap.dll")


def configure_wpcap(wpcap: ctypes.WinDLL) -> None:
    wpcap.pcap_findalldevs.argtypes = [
        ctypes.POINTER(ctypes.POINTER(PcapInterface)),
        ctypes.c_char_p,
    ]
    wpcap.pcap_findalldevs.restype = ctypes.c_int
    wpcap.pcap_freealldevs.argtypes = [ctypes.POINTER(PcapInterface)]
    wpcap.pcap_create.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    wpcap.pcap_create.restype = ctypes.c_void_p
    wpcap.pcap_set_snaplen.argtypes = [ctypes.c_void_p, ctypes.c_int]
    wpcap.pcap_set_promisc.argtypes = [ctypes.c_void_p, ctypes.c_int]
    wpcap.pcap_set_timeout.argtypes = [ctypes.c_void_p, ctypes.c_int]
    wpcap.pcap_set_buffer_size.argtypes = [ctypes.c_void_p, ctypes.c_int]
    wpcap.pcap_activate.argtypes = [ctypes.c_void_p]
    wpcap.pcap_activate.restype = ctypes.c_int
    wpcap.pcap_compile.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(BpfProgram),
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_uint32,
    ]
    wpcap.pcap_compile.restype = ctypes.c_int
    wpcap.pcap_setfilter.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(BpfProgram),
    ]
    wpcap.pcap_setfilter.restype = ctypes.c_int
    wpcap.pcap_freecode.argtypes = [ctypes.POINTER(BpfProgram)]
    wpcap.pcap_next_ex.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.POINTER(PcapHeader)),
        ctypes.POINTER(ctypes.POINTER(ctypes.c_ubyte)),
    ]
    wpcap.pcap_next_ex.restype = ctypes.c_int
    wpcap.pcap_stats.argtypes = [ctypes.c_void_p, ctypes.POINTER(PcapStat)]
    wpcap.pcap_stats.restype = ctypes.c_int
    wpcap.pcap_geterr.argtypes = [ctypes.c_void_p]
    wpcap.pcap_geterr.restype = ctypes.c_char_p
    wpcap.pcap_sendpacket.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_ubyte),
        ctypes.c_int,
    ]
    wpcap.pcap_sendpacket.restype = ctypes.c_int
    wpcap.pcap_close.argtypes = [ctypes.c_void_p]


def connected_windows_interface_guids() -> set[str] | None:
    command = (
        "$ErrorActionPreference='Stop'; "
        "Get-NetAdapter | Where-Object Status -eq 'Up' | "
        "ForEach-Object {[string]$_.InterfaceGuid}"
    )
    try:
        output = subprocess.check_output(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", command],
            text=True,
            timeout=5,
            stderr=subprocess.DEVNULL,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return {line.strip().upper() for line in output.splitlines() if line.strip()}


def enumerate_capture_interfaces(wpcap: ctypes.WinDLL) -> list[CaptureInterface]:
    devices = ctypes.POINTER(PcapInterface)()
    error_buffer = ctypes.create_string_buffer(256)
    result = wpcap.pcap_findalldevs(ctypes.byref(devices), error_buffer)
    if result != 0:
        raise RuntimeError(error_buffer.value.decode(errors="replace"))

    interfaces: list[CaptureInterface] = []
    connected_guids = connected_windows_interface_guids()
    try:
        device = devices
        while device:
            item = device.contents
            name = item.name or b""
            description = (item.description or b"").decode(errors="replace")
            if b"NPF_" in name:
                decoded_name = name.decode(errors="replace")
                guid_match = re.search(r"\{[0-9A-Fa-f-]+\}", decoded_name)
                windows_connected = None
                if connected_guids is not None and guid_match:
                    windows_connected = guid_match.group(0).upper() in connected_guids
                interfaces.append(
                    CaptureInterface(
                        name=name,
                        description=description or "Unknown Npcap interface",
                        flags=item.flags,
                        windows_connected=windows_connected,
                    )
                )
            device = item.next
    finally:
        if devices:
            wpcap.pcap_freealldevs(devices)

    return interfaces


def format_interface_inventory(interfaces: list[CaptureInterface]) -> str:
    if not interfaces:
        return "  (none)"
    return "\n".join(
        f"  {'connected' if item.is_connected else 'not-connected':13} "
        f"{item.guid}: {item.description}"
        for item in interfaces
    )


def choose_capture_interface(
    interfaces: list[CaptureInterface], selector: str | None = None
) -> CaptureInterface:
    candidates = list(interfaces)
    if selector:
        needle = selector.casefold()
        candidates = [
            item
            for item in candidates
            if needle in item.description.casefold()
            or needle in item.name.decode(errors="replace").casefold()
        ]
        if not candidates:
            raise RuntimeError(
                f"No capture interface matches {selector!r}.\n"
                "Available capture interfaces:\n"
                + format_interface_inventory(interfaces)
            )
        if len(candidates) == 1:
            return candidates[0]
        connected = [item for item in candidates if item.is_connected]
        if len(connected) == 1:
            return connected[0]
    else:
        x520 = [item for item in candidates if "X520" in item.description.upper()]
        connected_x520 = [item for item in x520 if item.is_connected]
        if len(connected_x520) == 1:
            return connected_x520[0]
        if len(x520) == 1:
            return x520[0]
        if x520:
            candidates = x520
        else:
            connected = [item for item in candidates if item.is_connected]
            if len(connected) == 1:
                return connected[0]
            i225 = [item for item in candidates if "I225" in item.description.upper()]
            if len(i225) == 1:
                return i225[0]

    raise RuntimeError(
        "Capture interface selection is ambiguous; connect exactly one X520 port "
        "or use --interface with its GUID.\nAvailable capture interfaces:\n"
        + format_interface_inventory(interfaces)
    )


def find_capture_interface(
    wpcap: ctypes.WinDLL, selector: str | None = None
) -> CaptureInterface:
    return choose_capture_interface(enumerate_capture_interfaces(wpcap), selector)


class CaptureWorker(threading.Thread):
    def __init__(
        self,
        frame_queue: queue.Queue[Frame],
        status_queue: queue.Queue[tuple[str, object]],
        stop_event: threading.Event,
        interface_selector: str | None = None,
    ) -> None:
        super().__init__(name="cam1-npcap", daemon=True)
        self.frame_queue = frame_queue
        self.status_queue = status_queue
        self.stop_event = stop_event
        self.interface_selector = interface_selector
        self.stats = CaptureStats()

    def publish_status(self, kind: str, value: object) -> None:
        self.status_queue.put((kind, value))

    def publish_frame(self, frame: Frame) -> None:
        try:
            self.frame_queue.put_nowait(frame)
        except queue.Full:
            try:
                self.frame_queue.get_nowait()
            except queue.Empty:
                pass
            self.frame_queue.put_nowait(frame)

    def run(self) -> None:
        handle = None
        wpcap = None
        try:
            wpcap = load_wpcap()
            configure_wpcap(wpcap)
            interface = find_capture_interface(wpcap, self.interface_selector)
            self.publish_status("interface", interface.description)
            handle = self.open_capture(wpcap, interface.name)
            self.capture_loop(wpcap, handle)
        except Exception as error:
            self.publish_status("error", str(error))
        finally:
            if handle and wpcap:
                stats = PcapStat()
                if wpcap.pcap_stats(handle, ctypes.byref(stats)) == 0:
                    self.stats = CaptureStats(
                        complete_frames=self.stats.complete_frames,
                        partial_frames=self.stats.partial_frames,
                        malformed_packets=self.stats.malformed_packets,
                        pcap_drops=stats.ps_drop,
                        interface_drops=stats.ps_ifdrop,
                    )
                    self.publish_status("stats", self.stats)
                wpcap.pcap_close(handle)

    def open_capture(self, wpcap: ctypes.WinDLL, device_name: bytes) -> int:
        error_buffer = ctypes.create_string_buffer(256)
        handle = wpcap.pcap_create(device_name, error_buffer)
        if not handle:
            raise RuntimeError(error_buffer.value.decode(errors="replace"))

        settings = (
            (wpcap.pcap_set_snaplen, 1600),
            (wpcap.pcap_set_promisc, 1),
            (wpcap.pcap_set_timeout, 10),
            (wpcap.pcap_set_buffer_size, 64 * 1024 * 1024),
        )
        for setter, value in settings:
            if setter(handle, value) != 0:
                wpcap.pcap_close(handle)
                raise RuntimeError("Npcap capture setup failed")

        if wpcap.pcap_activate(handle) < 0:
            message = wpcap.pcap_geterr(handle).decode(errors="replace")
            wpcap.pcap_close(handle)
            raise RuntimeError(message)

        program = BpfProgram()
        filter_text = b"src host 169.254.26.95 and udp dst port 5002"
        if wpcap.pcap_compile(
            handle, ctypes.byref(program), filter_text, 1, 0xFFFFFFFF
        ) != 0:
            message = wpcap.pcap_geterr(handle).decode(errors="replace")
            wpcap.pcap_close(handle)
            raise RuntimeError(message)
        try:
            if wpcap.pcap_setfilter(handle, ctypes.byref(program)) != 0:
                raise RuntimeError(
                    wpcap.pcap_geterr(handle).decode(errors="replace")
                )
        finally:
            wpcap.pcap_freecode(ctypes.byref(program))
        return handle

    def capture_loop(self, wpcap: ctypes.WinDLL, handle: int) -> None:
        assembler = FrameAssembler()
        last_stats_time = time.monotonic()
        stream_started = False

        while not self.stop_event.is_set():
            header_pointer = ctypes.POINTER(PcapHeader)()
            data_pointer = ctypes.POINTER(ctypes.c_ubyte)()
            result = wpcap.pcap_next_ex(
                handle,
                ctypes.byref(header_pointer),
                ctypes.byref(data_pointer),
            )
            if result == 0:
                continue
            if result < 0:
                raise RuntimeError(
                    wpcap.pcap_geterr(handle).decode(errors="replace")
                )

            caplen = header_pointer.contents.caplen
            if caplen < 64:
                assembler.malformed_packets += 1
                continue
            address = ctypes.cast(data_pointer, ctypes.c_void_p).value
            if address is None:
                assembler.malformed_packets += 1
                continue
            header = ctypes.string_at(address, 64)
            parsed = self.parse_packet_header(header, caplen)
            if parsed is None:
                assembler.malformed_packets += 1
                continue
            # A capture handle can open in the middle of a JPEG frame. Ignore
            # that unavoidable prefix until the first explicit SOF so the
            # live integrity counter represents actual stream errors.
            if not stream_started:
                if parsed.encoding == "JPEG" and not (parsed.flags & 0x01):
                    continue
                stream_started = True
            payload = ctypes.string_at(
                address + parsed.app_offset + APP_HEADER_BYTES,
                parsed.payload_bytes,
            )
            frame = assembler.consume(parsed, payload, time.monotonic())
            if frame is not None:
                self.publish_frame(frame)

            now = time.monotonic()
            if now - last_stats_time >= 1.0:
                pcap_stats = PcapStat()
                if wpcap.pcap_stats(handle, ctypes.byref(pcap_stats)) == 0:
                    self.stats = CaptureStats(
                        complete_frames=assembler.complete_frames,
                        partial_frames=assembler.partial_frames,
                        malformed_packets=assembler.malformed_packets,
                        pcap_drops=pcap_stats.ps_drop,
                        interface_drops=pcap_stats.ps_ifdrop,
                    )
                    self.publish_status("stats", self.stats)
                last_stats_time = now

    @staticmethod
    def parse_packet_header(
        header: bytes, caplen: int
    ) -> PacketHeader | None:
        if len(header) < 64:
            return None
        if header[12:14] != b"\x08\x00" or header[23] != 17:
            return None
        if header[26:30] != SOURCE_IP:
            return None
        ip_header_bytes = (header[14] & 0x0F) * 4
        udp_offset = 14 + ip_header_bytes
        app_offset = udp_offset + 8
        if app_offset + APP_HEADER_BYTES > len(header):
            return None
        destination_port = int.from_bytes(
            header[udp_offset + 2 : udp_offset + 4], "big"
        )
        if destination_port != UDP_PORT:
            return None
        app_header = header[app_offset : app_offset + APP_HEADER_BYTES]
        payload_bytes = int.from_bytes(app_header[10:12], "big")
        frame_id = int.from_bytes(app_header[12:16], "big")
        if app_offset + APP_HEADER_BYTES + payload_bytes > caplen:
            return None
        if app_header[:4] == JPEG_MAGIC:
            width = int.from_bytes(app_header[4:6], "big")
            height = int.from_bytes(app_header[6:8], "big")
            if app_header[8] != 1 or app_header[9] != 2:
                return None
            fpga_metadata_valid = app_header[21] == 0xA5
            return PacketHeader(
                app_offset=app_offset,
                payload_bytes=payload_bytes,
                frame_id=frame_id,
                width=width,
                height=height,
                encoding="JPEG",
                sequence=int.from_bytes(app_header[16:18], "big"),
                flags=app_header[18] & 0x03,
                fpga_algorithm=(app_header[19] & 0x03) if fpga_metadata_valid else 0,
                fpga_threshold=128,
                fpga_sequence=app_header[20] if fpga_metadata_valid else 0,
                fpga_metadata_valid=fpga_metadata_valid,
                fpga_command_accepted_count=((app_header[19] >> 2) & 0x07) if fpga_metadata_valid else 0,
                fpga_command_rejected_count=((app_header[19] >> 5) & 0x07) if fpga_metadata_valid else 0,
            )
        if (app_header[:4] == RGB565_MAGIC and
                app_header[8] == 2 and app_header[9] == 1):
            return PacketHeader(
                app_offset=app_offset,
                payload_bytes=payload_bytes,
                frame_id=frame_id,
                width=int.from_bytes(app_header[4:6], "big"),
                height=int.from_bytes(app_header[6:8], "big"),
                encoding="RGB565",
                fpga_algorithm=app_header[16] & 0x03,
                fpga_threshold=app_header[17],
                fpga_sequence=app_header[18],
                fpga_metadata_valid=True,
            )
        return None


class LiveViewer:
    def __init__(self, root: tk.Tk, interface_selector: str | None = None) -> None:
        self.root = root
        self.root.title("CAM1 Live - Ethernet | Waiting")
        self.root.geometry("960x770")
        self.root.minsize(720, 590)
        self.root.configure(bg="#111111")

        self.frame_queue: queue.Queue[Frame] = queue.Queue(maxsize=1)
        self.status_queue: queue.Queue[tuple[str, object]] = queue.Queue()
        self.stop_event = threading.Event()
        self.worker = CaptureWorker(
            self.frame_queue,
            self.status_queue,
            self.stop_event,
            interface_selector,
        )
        self.last_frame: Frame | None = None
        self.photo: ImageTk.PhotoImage | None = None
        self.image_id: int | None = None
        self.frame_times: list[float] = []
        self.stats = CaptureStats()
        self.interface_name = "Selecting capture interface"
        self.error_text = ""
        self.last_canvas_size = (0, 0)
        self.last_title_update = 0.0

        self.build_ui()
        self.root.protocol("WM_DELETE_WINDOW", self.close)
        self.root.bind("<F11>", self.toggle_fullscreen)
        self.root.bind("<Escape>", self.leave_fullscreen)
        self.worker.start()
        self.root.after(15, self.refresh)

    def build_ui(self) -> None:
        header = tk.Frame(self.root, bg="#181818", height=48)
        header.grid(row=0, column=0, sticky="ew")
        header.grid_propagate(False)
        header.columnconfigure(0, weight=1)

        title_font = tkfont.Font(family="Segoe UI", size=14, weight="bold")
        status_font = tkfont.Font(family="Segoe UI", size=10, weight="bold")
        body_font = tkfont.Font(family="Segoe UI", size=10)

        tk.Label(
            header,
            text="CAM1 LIVE",
            bg="#181818",
            fg="#f4f4f4",
            font=title_font,
            padx=16,
        ).grid(row=0, column=0, sticky="w", ipady=11)

        self.state_label = tk.Label(
            header,
            text="WAITING FOR STREAM",
            bg="#181818",
            fg="#f2b84b",
            font=status_font,
            padx=16,
        )
        self.state_label.grid(row=0, column=1, sticky="e")

        self.canvas = tk.Canvas(
            self.root,
            bg="#090909",
            highlightthickness=0,
            bd=0,
        )
        self.canvas.grid(row=1, column=0, sticky="nsew")
        self.canvas.bind("<Configure>", self.on_canvas_resize)

        self.waiting_text = self.canvas.create_text(
            480,
            335,
            text="Waiting for CAM1 video...",
            fill="#8a8a8a",
            font=("Segoe UI", 15),
        )

        self.detail_label = tk.Label(
            self.root,
            text="169.254.26.95:5002  |  1920 x 1080 JPEG | OV5640 图像模式",
            bg="#181818",
            fg="#b8b8b8",
            font=body_font,
            anchor="w",
            padx=16,
            pady=9,
        )
        self.detail_label.grid(row=2, column=0, sticky="ew")

        self.root.rowconfigure(1, weight=1)
        self.root.columnconfigure(0, weight=1)

    def on_canvas_resize(self, event: tk.Event) -> None:
        self.last_canvas_size = (event.width, event.height)
        if self.last_frame is not None:
            self.render_frame(self.last_frame)
        else:
            self.canvas.coords(
                self.waiting_text, event.width // 2, event.height // 2
            )

    def refresh(self) -> None:
        while True:
            try:
                kind, value = self.status_queue.get_nowait()
            except queue.Empty:
                break
            if kind == "interface":
                self.interface_name = str(value)
            elif kind == "stats" and isinstance(value, CaptureStats):
                self.stats = value
            elif kind == "error":
                self.error_text = str(value)

        newest_frame = None
        while True:
            try:
                newest_frame = self.frame_queue.get_nowait()
            except queue.Empty:
                break
        if newest_frame is not None:
            self.last_frame = newest_frame
            self.frame_times.append(newest_frame.captured_at)
            cutoff = newest_frame.captured_at - 1.0
            self.frame_times = [t for t in self.frame_times if t >= cutoff]
            self.render_frame(newest_frame)

        self.update_status()
        if not self.stop_event.is_set():
            self.root.after(15, self.refresh)

    def render_frame(self, frame: Frame) -> None:
        if frame.encoding == "JPEG":
            with Image.open(io.BytesIO(frame.image_data)) as decoded:
                image = decoded.convert("RGB")
            if image.size != (frame.width, frame.height):
                raise ValueError(
                    f"JPEG size {image.size} does not match stream "
                    f"{frame.width}x{frame.height}"
                )
        else:
            words = np.frombuffer(frame.image_data, dtype=">u2")
            little_endian = words.astype("<u2", copy=True).tobytes()
            image = Image.frombytes(
                "RGB",
                (frame.width, frame.height),
                little_endian,
                "raw",
                "BGR;16",
            )

        canvas_width = max(self.last_canvas_size[0], 1)
        canvas_height = max(self.last_canvas_size[1], 1)
        scale = min(
            canvas_width / frame.width,
            canvas_height / frame.height,
        )
        display_size = (
            max(1, int(frame.width * scale)),
            max(1, int(frame.height * scale)),
        )
        if display_size != image.size:
            image = image.resize(display_size, Image.Resampling.BILINEAR)
        self.photo = ImageTk.PhotoImage(image)

        center = (canvas_width // 2, canvas_height // 2)
        if self.image_id is None:
            self.image_id = self.canvas.create_image(
                *center, image=self.photo, anchor="center"
            )
        else:
            self.canvas.coords(self.image_id, *center)
            self.canvas.itemconfigure(self.image_id, image=self.photo)
        self.canvas.itemconfigure(self.waiting_text, state="hidden")

    def update_status(self) -> None:
        if self.error_text:
            self.state_label.configure(text="CAPTURE ERROR", fg="#ff6b6b")
            self.detail_label.configure(text=self.error_text)
            self.set_window_title("CAM1 Live - Ethernet | ERROR", force=True)
            return

        if self.last_frame is None:
            self.state_label.configure(text="WAITING FOR STREAM", fg="#f2b84b")
            self.detail_label.configure(
                text="169.254.26.95:5002  |  1920 x 1080 JPEG | OV5640 图像模式  |  "
                + self.interface_name
            )
            self.set_window_title("CAM1 Live - Ethernet | Waiting")
            return

        fps = max(0, len(self.frame_times) - 1)
        self.state_label.configure(text="LIVE", fg="#39d98a")
        self.detail_label.configure(
            text=(
                f"Frame {self.last_frame.frame_id}  |  {fps:.0f} FPS  |  "
                f"{self.last_frame.width} x {self.last_frame.height} "
                f"{self.last_frame.encoding}  |  "
                f"Complete {self.stats.complete_frames}  |  "
                f"Partial {self.stats.partial_frames}  |  "
                f"Capture drops {self.stats.pcap_drops + self.stats.interface_drops}"
            )
        )
        self.set_window_title(
            f"CAM1 Live - Ethernet | LIVE | {fps:.0f} FPS | "
            f"Frame {self.last_frame.frame_id}"
        )

    def set_window_title(self, title: str, force: bool = False) -> None:
        now = time.monotonic()
        if force or now - self.last_title_update >= 0.5:
            self.root.title(title)
            self.last_title_update = now

    def toggle_fullscreen(self, _event: tk.Event | None = None) -> None:
        enabled = bool(self.root.attributes("-fullscreen"))
        self.root.attributes("-fullscreen", not enabled)

    def leave_fullscreen(self, _event: tk.Event | None = None) -> None:
        self.root.attributes("-fullscreen", False)

    def close(self) -> None:
        self.stop_event.set()
        self.root.after(50, self.wait_for_worker)

    def wait_for_worker(self) -> None:
        if self.worker.is_alive():
            self.root.after(50, self.wait_for_worker)
        else:
            self.root.destroy()


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--interface",
        help="Npcap interface description or GUID substring; auto-selects a connected X520",
    )
    parser.add_argument(
        "--list-interfaces",
        action="store_true",
        help="list Npcap interfaces and exit",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="validate OVJ2/legacy parsing and frame assembly without opening a window",
    )
    return parser.parse_args()


def self_test() -> None:
    header = bytearray(64)
    header[12:14] = b"\x08\x00"
    header[14] = 0x45
    header[23] = 17
    header[26:30] = SOURCE_IP
    header[36:38] = UDP_PORT.to_bytes(2, "big")
    header[42:46] = JPEG_MAGIC
    header[46:48] = WIDTH.to_bytes(2, "big")
    header[48:50] = HEIGHT.to_bytes(2, "big")
    header[50:52] = bytes((1, 2))
    header[52:54] = (4).to_bytes(2, "big")
    header[54:58] = (1234).to_bytes(4, "big")
    header[58:60] = (0).to_bytes(2, "big")
    header[60] = 3
    parsed = CaptureWorker.parse_packet_header(bytes(header), 68)
    assert parsed == PacketHeader(
        app_offset=42,
        payload_bytes=4,
        frame_id=1234,
        width=1920,
        height=1080,
        encoding="JPEG",
        sequence=0,
        flags=3,
    ), parsed
    assembler = FrameAssembler()
    frame = assembler.consume(parsed, b"\xff\xd8\xff\xd9", 1.0)
    assert frame is not None and frame.encoding == "JPEG"

    sample = bytes((0xF8, 0x00, 0x07, 0xE0, 0x00, 0x1F))
    words = np.frombuffer(sample, dtype=">u2")
    converted = Image.frombytes(
        "RGB", (3, 1), words.astype("<u2").tobytes(), "raw", "BGR;16"
    )
    pixels = [converted.getpixel((x, 0)) for x in range(3)]
    assert pixels[0][0] >= 248 and pixels[0][1:] == (0, 0), pixels
    assert pixels[1][1] >= 252 and pixels[1][0] == pixels[1][2] == 0, pixels
    assert pixels[2][2] >= 248 and pixels[2][:2] == (0, 0), pixels
    print("SELF_TEST_PASS OVJ2 parser/assembler and RGB565 conversion")


def main() -> None:
    arguments = parse_arguments()
    if arguments.list_interfaces:
        wpcap = load_wpcap()
        configure_wpcap(wpcap)
        print(format_interface_inventory(enumerate_capture_interfaces(wpcap)))
        return
    if arguments.self_test:
        self_test()
        return
    root = tk.Tk()
    LiveViewer(root, arguments.interface)
    root.mainloop()


if __name__ == "__main__":
    main()
