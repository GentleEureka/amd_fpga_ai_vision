#!/usr/bin/env python3
"""Validate OVJ2/legacy CAM1 packets and decoded frames without a window."""

from __future__ import annotations

import argparse
from collections import Counter, OrderedDict
import ctypes
import io
from pathlib import Path
import queue
import threading
import time

from PIL import Image
import numpy as np

from cam1_live_viewer import (
    CaptureWorker,
    FrameAssembler,
    APP_HEADER_BYTES,
    PcapHeader,
    PcapStat,
    configure_wpcap,
    find_capture_interface,
    load_wpcap,
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--interface", required=True)
    parser.add_argument("--seconds", type=float, default=3.0)
    parser.add_argument("--save", type=Path, help="save the newest verified frame")
    parser.add_argument(
        "--verify-1080p30",
        action="store_true",
        help="fail unless the capture meets the 1920x1080@29-31 clean-stream gate",
    )
    args = parser.parse_args()

    wpcap = load_wpcap()
    configure_wpcap(wpcap)
    interface = find_capture_interface(wpcap, args.interface)
    worker = CaptureWorker(queue.Queue(), queue.Queue(), threading.Event())
    handle = worker.open_capture(wpcap, interface.name)

    frames: OrderedDict[int, dict[str, object]] = OrderedDict()
    payload_lengths: Counter[int] = Counter()
    fpga_modes: Counter[int] = Counter()
    dimensions: Counter[tuple[int, int]] = Counter()
    sensor_register_readbacks: Counter[tuple[int, int]] = Counter()
    camera_fifo_overflow_packets = 0
    fpga_thresholds: Counter[int] = Counter()
    fpga_sequences: Counter[int] = Counter()
    first_packet_id: int | None = None
    last_packet_id: int | None = None
    packet_id_gaps = 0
    malformed = 0
    assembler = FrameAssembler()
    completed_times: list[float] = []
    decoded_frames = 0
    decode_errors = 0
    newest_image: Image.Image | None = None
    newest_raw: bytes | None = None
    last_resolution: tuple[int, int] | None = None
    stream_started = False
    deadline = time.monotonic() + args.seconds

    try:
        while time.monotonic() < deadline:
            header_pointer = ctypes.POINTER(PcapHeader)()
            data_pointer = ctypes.POINTER(ctypes.c_ubyte)()
            result = wpcap.pcap_next_ex(
                handle, ctypes.byref(header_pointer), ctypes.byref(data_pointer)
            )
            if result == 0:
                continue
            if result < 0:
                raise RuntimeError(wpcap.pcap_geterr(handle).decode(errors="replace"))

            caplen = header_pointer.contents.caplen
            address = ctypes.cast(data_pointer, ctypes.c_void_p).value
            if address is None or caplen < 64:
                malformed += 1
                continue
            header = ctypes.string_at(address, 64)
            parsed = worker.parse_packet_header(header, caplen)
            if parsed is None:
                malformed += 1
                continue

            # Capture can begin in the middle of a JPEG frame.  Ignore that
            # unavoidable prefix until the first explicit SOF, so integrity
            # counters describe complete frames observed during the test.
            if not stream_started:
                if parsed.encoding == "JPEG" and not (parsed.flags & 0x01):
                    continue
                stream_started = True

            payload_bytes = parsed.payload_bytes
            dimensions[(parsed.width, parsed.height)] += 1
            app_header = ctypes.string_at(
                address + parsed.app_offset, APP_HEADER_BYTES
            )
            if app_header[21] & 0x01:
                diag_status = app_header[21]
                if diag_status & 0x01:
                    diag_tag = (diag_status >> 1) & 0x3F
                    diag_value = int.from_bytes(app_header[19:21], "big")
                    sensor_register_readbacks[(diag_tag, diag_value)] += 1
                camera_fifo_overflow_packets += (diag_status >> 7) & 1
            frame_id = parsed.frame_id
            packet_id = int.from_bytes(header[18:20], "big")
            if first_packet_id is None:
                first_packet_id = packet_id
            if last_packet_id is not None and packet_id != ((last_packet_id + 1) & 0xFFFF):
                packet_id_gaps += 1
            last_packet_id = packet_id

            record = frames.setdefault(
                frame_id,
                {"packets": 0, "bytes": 0, "first_pid": packet_id, "last_pid": packet_id},
            )
            record["packets"] = int(record["packets"]) + 1
            record["bytes"] = int(record["bytes"]) + payload_bytes
            record["last_pid"] = packet_id
            payload_lengths[payload_bytes] += 1
            if parsed.encoding == "RGB565":
                fpga_modes[parsed.fpga_algorithm] += 1
                fpga_thresholds[parsed.fpga_threshold] += 1
                fpga_sequences[parsed.fpga_sequence] += 1
            payload = ctypes.string_at(
                address + parsed.app_offset + APP_HEADER_BYTES,
                parsed.payload_bytes,
            )
            now = time.monotonic()
            frame = assembler.consume(parsed, payload, now)
            if frame is not None:
                try:
                    newest_raw = frame.image_data
                    if frame.encoding == "JPEG":
                        with Image.open(io.BytesIO(frame.image_data)) as decoded:
                            decoded.load()
                            if decoded.size != (frame.width, frame.height):
                                raise ValueError(
                                    f"decoded {decoded.size}, header "
                                    f"{frame.width}x{frame.height}"
                                )
                            newest_image = decoded.convert("RGB")
                    else:
                        words = np.frombuffer(frame.image_data, dtype=">u2")
                        newest_image = Image.frombytes(
                            "RGB",
                            (frame.width, frame.height),
                            words.astype("<u2", copy=True).tobytes(),
                            "raw",
                            "BGR;16",
                        )
                    decoded_frames += 1
                    last_resolution = (frame.width, frame.height)
                    completed_times.append(now)
                except (OSError, ValueError):
                    decode_errors += 1
    finally:
        stats = PcapStat()
        wpcap.pcap_stats(handle, ctypes.byref(stats))
        wpcap.pcap_close(handle)

    print(f"interface={interface.description}")
    fps = 0.0
    if len(completed_times) > 1:
        fps = (len(completed_times) - 1) / (
            completed_times[-1] - completed_times[0]
        )
    resolution_text = (
        f"{last_resolution[0]}x{last_resolution[1]}"
        if last_resolution is not None
        else "none"
    )
    print(
        f"frames_seen={len(frames)} complete={assembler.complete_frames} "
        f"partial={assembler.partial_frames} malformed="
        f"{malformed + assembler.malformed_packets}"
    )
    print(
        f"decoded_frames={decoded_frames} decode_errors={decode_errors} "
        f"measured_fps={fps:.2f} resolution={resolution_text}"
    )
    print(f"payload_lengths={dict(sorted(payload_lengths.items()))}")
    print(f"header_dimensions={dict(dimensions.most_common(12))}")
    print(f"sensor_register_readbacks={dict(sensor_register_readbacks)}")
    print(f"fpga_camera_fifo_overflow_packets={camera_fifo_overflow_packets}")
    if fpga_modes:
        print(
            f"fpga_modes={dict(sorted(fpga_modes.items()))} "
            f"fpga_thresholds={dict(sorted(fpga_thresholds.items()))} "
            f"fpga_sequences={dict(sorted(fpga_sequences.items()))}"
        )
    print(
        f"packet_id_first={first_packet_id} packet_id_last={last_packet_id} "
        f"packet_id_gaps={packet_id_gaps} pcap_drop={stats.ps_drop} "
        f"interface_drop={stats.ps_ifdrop}"
    )
    for frame_id, record in list(frames.items())[:12]:
        print(
            f"frame={frame_id} packets={record['packets']} bytes={record['bytes']} "
            f"pid={record['first_pid']}..{record['last_pid']}"
        )
    if args.save and newest_image is not None:
        args.save.parent.mkdir(parents=True, exist_ok=True)
        newest_image.save(args.save)
        if newest_raw is not None and last_resolution is not None:
            args.save.with_suffix(".rgb565").write_bytes(newest_raw)
        print(f"saved={args.save.resolve()}")

    if args.verify_1080p30:
        failures: list[str] = []
        if decoded_frames < 2:
            failures.append(f"decoded_frames={decoded_frames}, need at least 2")
        if last_resolution != (1920, 1080):
            failures.append(f"resolution={resolution_text}, expected 1920x1080")
        if not 29.0 <= fps <= 31.0:
            failures.append(f"measured_fps={fps:.2f}, expected 29.00..31.00")
        if assembler.partial_frames != 0:
            failures.append(f"partial={assembler.partial_frames}")
        total_malformed = malformed + assembler.malformed_packets
        if total_malformed != 0:
            failures.append(f"malformed={total_malformed}")
        if decode_errors != 0:
            failures.append(f"decode_errors={decode_errors}")
        if packet_id_gaps != 0:
            failures.append(f"packet_id_gaps={packet_id_gaps}")
        if stats.ps_drop != 0:
            failures.append(f"pcap_drop={stats.ps_drop}")
        if stats.ps_ifdrop != 0:
            failures.append(f"interface_drop={stats.ps_ifdrop}")
        if failures:
            print("VERIFY_1080P30_FAIL=" + "; ".join(failures))
            raise SystemExit(2)
        print("VERIFY_1080P30_PASS")


if __name__ == "__main__":
    main()
