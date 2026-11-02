#!/usr/bin/env python3
"""Agent tools for CAM1 1080p JPEG video perception."""

from __future__ import annotations

import io
import os
from pathlib import Path
import queue
import sys
import threading
from typing import Literal
import time
import warnings

import numpy as np
from PIL import Image as PillowImage

ROOT = Path(__file__).resolve().parent
VIEWER_DIR = ROOT.parent / "camera_viewer"
if str(VIEWER_DIR) not in sys.path:
    sys.path.insert(0, str(VIEWER_DIR))

warnings.filterwarnings(
    "ignore", message=r"Field 'lifespan' has an incomplete definition.*"
)

from mcp.server.fastmcp import FastMCP, Image as McpImage

from fpga_algorithm_control import FpgaAlgorithmController, MODE_NAMES
from cam1_live_viewer import CaptureWorker, Frame
import continuous_perception_client as continuous


server = FastMCP(
    "cam1-vision-control",
    instructions=(
        "CAM1 has two evidence sources. For current questions such as 现在看到了什么, "
        "use get_current_scene and check scene_age_seconds; fetch a live frame only if "
        "the user explicitly needs current pixels. When answering about the current view, "
        "describe scene_type, environment, visible objects, their positions and current states; "
        "do not answer with action narration alone. State when these details are unavailable. "
        "For historical questions such as "
        "刚才发生了什么 or 我拿起了什么, use search_scene_memory or "
        "get_recent_scene_events and never infer history from a new frame. Treat only "
        "status=confirmed as fact. Pending evidence must be reported as an unconfirmed "
        "clue, not omitted. If no confirmed or pending matching evidence exists, say "
        "there is no reliable record. This build streams 1920x1080 JPEG frames from the OV5640 "
        "through the FPGA over 10GbE. Image-effect selections are sent to the FPGA, which "
        "applies them to the OV5640 over SCCB; subsequent JPEG frame metadata reports the mode."
    ),
    log_level="ERROR",
)


class _StatusSink:
    def __init__(self) -> None:
        self.latest: tuple[str, object] | None = None

    def put(self, value: tuple[str, object]) -> None:
        self.latest = value


class LiveFrameSource:
    """Lazily capture the current OV5640 JPEG stream for Hermes image tools."""

    def __init__(self) -> None:
        self.frame_queue: queue.Queue[Frame] = queue.Queue(maxsize=1)
        self.status_sink = _StatusSink()
        self.stop_event = threading.Event()
        self.worker: CaptureWorker | None = None
        self.lock = threading.Lock()
        self.last_frame: Frame | None = None

    def _ensure_started(self) -> None:
        with self.lock:
            if self.worker is not None and self.worker.is_alive():
                return
            self.stop_event = threading.Event()
            self.worker = CaptureWorker(
                self.frame_queue,
                self.status_sink,  # type: ignore[arg-type]
                self.stop_event,
                os.environ.get("CAM1_PCAP_INTERFACE") or None,
            )
            self.worker.start()

    def get(self, timeout: float = 5.0) -> Frame:
        self._ensure_started()
        try:
            frame = self.frame_queue.get(timeout=timeout)
        except queue.Empty as error:
            detail = self.status_sink.latest
            raise RuntimeError(f"CAM1 frame timeout; capture status={detail}") from error
        while True:
            try:
                frame = self.frame_queue.get_nowait()
            except queue.Empty:
                break
        self.last_frame = frame
        return frame


frame_source = LiveFrameSource()


# Starting an MCP server starts perception in the background, but does not delay MCP
# registration while the camera or model warms up.
threading.Thread(
    target=continuous.ensure_running,
    name="continuous-perception-bootstrap",
    daemon=True,
).start()


def _continuous_ready() -> None:
    if not continuous.ensure_running():
        raise RuntimeError(
            "continuous perception service is unavailable; see runtime/continuous_perception.log"
        )


def _frame_as_jpeg(frame: Frame) -> bytes:
    if frame.encoding == "JPEG":
        return frame.image_data
    words = np.frombuffer(frame.image_data, dtype=">u2")
    little_endian = words.astype("<u2", copy=True).tobytes()
    image = PillowImage.frombytes(
        "RGB", (frame.width, frame.height), little_endian, "raw", "BGR;16"
    )
    encoded = io.BytesIO()
    image.save(encoded, format="JPEG", quality=88)
    return encoded.getvalue()


def _frame_info(frame: Frame) -> dict[str, object]:
    return {
        "frame_id": frame.frame_id,
        "width": frame.width,
        "height": frame.height,
        "encoding": frame.encoding,
        "packet_count": frame.packet_count,
        "fpga_algorithm": frame.fpga_algorithm,
        "fpga_algorithm_name": (
            (
                f"1080p JPEG / OV5640 图像模式：{MODE_NAMES.get(frame.fpga_algorithm, 'unknown')}"
                if frame.fpga_metadata_valid
                else "1080p JPEG / 等待 OV5640 图像模式回读"
            )
            if frame.encoding == "JPEG"
            else MODE_NAMES.get(frame.fpga_algorithm, "unknown")
        ),
        "fpga_threshold": frame.fpga_threshold,
        "fpga_sequence": frame.fpga_sequence,
        "fpga_metadata_valid": frame.fpga_metadata_valid,
        "fpga_command_accepted_count": frame.fpga_command_accepted_count,
        "fpga_command_rejected_count": frame.fpga_command_rejected_count,
    }


@server.tool()
def list_vision_algorithms() -> dict[str, object]:
    """Report OV5640 image effects controlled by the FPGA over SCCB."""
    frame = frame_source.get()
    if frame.encoding == "JPEG":
        return {
            "algorithms": [
                {"mode": key, "name": value}
                for key, value in (("color", "彩色"), ("gray", "灰度"),
                                   ("binary", "OV5640黑白效果"), ("invert", "OV5640负片效果"))
            ],
            "applied_mode": frame.fpga_algorithm,
            "applied_name": MODE_NAMES.get(frame.fpga_algorithm, "unknown"),
            "software_processing": False,
            "switching_supported": frame.fpga_metadata_valid,
            "note": (
                "FPGA接收以太网命令并经SCCB在帧边界设置OV5640图像效果；模式/序号从后续JPEG视频帧元数据回读。"
                if frame.fpga_metadata_valid
                else "当前JPEG视频帧没有OV5640图像模式回读标记；请先烧录支持该接口的新固件。"
            ),
        }
    return {
        "algorithms": [
            {"mode": key, "name": value}
            for key, value in MODE_NAMES.items()
        ],
        "applied_mode": frame.fpga_algorithm,
        "applied_name": MODE_NAMES.get(frame.fpga_algorithm, "unknown"),
        "software_processing": False,
        "note": "FPGA经SCCB设置OV5640图像效果；JPEG视频帧元数据回读当前模式和序号。",
    }


@server.tool()
def get_vision_status() -> dict[str, object]:
    """Get acquisition, ring-buffer, inference, scene, and FPGA status."""
    try:
        status = continuous.status()
        status["detector"] = None
        status["continuous_temporal_perception"] = True
        return status
    except Exception:
        frame = frame_source.get()
        return {
            "running": True,
            "source": "CAM1 FPGA via SFP1/X520-DA2",
            "continuous_temporal_perception": False,
            "detector": None,
            **_frame_info(frame),
        }


@server.tool()
def get_live_camera_frame() -> McpImage:
    """Return a JPEG preview from the newest 1080p CAM1 frame."""
    try:
        _continuous_ready()
        return McpImage(data=continuous.get_frame(), format="jpeg")
    except Exception:
        frame = frame_source.get()
        return McpImage(data=_frame_as_jpeg(frame), format="jpeg")


@server.tool()
def get_live_camera_frame_info() -> dict[str, object]:
    """Return JPEG transport and OV5640 image-mode metadata for a new CAM1 frame."""
    try:
        _continuous_ready()
        return continuous.status().get("latest_frame", {})
    except Exception:
        return _frame_info(frame_source.get())


@server.tool()
def get_continuous_perception_status() -> dict[str, object]:
    """Return capture FPS, buffer depth, inference latency, and semantic freshness."""
    _continuous_ready()
    return continuous.status()


@server.tool()
def get_current_scene() -> dict[str, object]:
    """Return scene type, environment, visible objects/current states, and freshness; current view only."""
    _continuous_ready()
    return continuous.scene()


@server.tool()
def get_recent_scene_events(
    seconds: float = 900.0, limit: int = 30, include_pending: bool = False
) -> dict[str, object]:
    """For past-action questions, return persisted confirmed and optionally pending evidence by evidence time; never fetch a new frame."""
    _continuous_ready()
    return continuous.events(
        seconds=max(1.0, seconds),
        limit=max(1, min(limit, 100)),
        include_pending=include_pending,
    )


@server.tool()
def get_recent_event_candidates(
    seconds: float = 120.0, limit: int = 50
) -> dict[str, object]:
    """Show motion candidates and exactly where each event pipeline stopped."""
    _continuous_ready()
    return continuous.candidates(
        seconds=max(1.0, seconds), limit=max(1, min(limit, 200))
    )


@server.tool()
def get_event_processing_log(
    limit: int = 100, candidate_id: str = ""
) -> dict[str, object]:
    """Return event stages: trigger, frames, queue, model, parse, threshold, dedup, write."""
    _continuous_ready()
    return continuous.event_audit(
        limit=max(1, min(limit, 500)), candidate_id=candidate_id or None
    )


@server.tool()
def get_recent_video_understanding(
    seconds: float = 20.0, limit: int = 10
) -> dict[str, object]:
    """Return recent ordered multi-frame model results and their video timestamps."""
    _continuous_ready()
    return continuous.understandings(
        seconds=max(1.0, seconds), limit=max(1, min(limit, 50))
    )


@server.tool()
def search_scene_memory(
    question: str, seconds: float = 1800.0, limit: int = 30
) -> dict[str, object]:
    """Search persisted history. Return confirmed events and pending clues separately; never infer past from a new frame."""
    _continuous_ready()
    return continuous.search_memory(
        question, seconds=max(1.0, seconds), limit=max(1, min(limit, 100))
    )


@server.tool()
def select_fpga_algorithm(
    mode: Literal["color", "gray", "binary", "invert"],
) -> dict[str, object]:
    before = continuous.status()
    latest = before.get("latest_frame") or {}
    if not latest:
        return {"ok": False, "hardware_verified": False,
                "error": "没有收到JPEG视频帧，无法发送并验证OV5640图像模式。"}
    if not latest.get("fpga_metadata_valid"):
        return {"ok": False, "hardware_verified": False,
                "error": "当前固件未提供OV5640图像模式回读标记；请先烧录此工程生成的新固件。"}
    controller = FpgaAlgorithmController(os.environ.get("CAM1_PCAP_INTERFACE") or None)
    controller.synchronize_sequence(int(latest.get("fpga_sequence", 0) or 0))
    request = controller.select(mode)
    deadline = time.monotonic() + 3.0
    observed: dict[str, object] = {}
    while time.monotonic() < deadline:
        observed = continuous.status().get("latest_frame") or {}
        if (observed.get("fpga_sequence") == request.sequence and
                observed.get("fpga_algorithm") == request.mode):
            return {
                "ok": True,
                "hardware_verified": True,
                "mode": mode,
                "applied_name": MODE_NAMES[request.mode],
                "sequence": request.sequence,
                "note": "FPGA已通过SCCB更新OV5640图像效果，并从后续JPEG帧元数据回读确认。",
            }
        time.sleep(0.05)
    return {
        "ok": False,
        "hardware_verified": False,
        "requested_mode": mode,
        "sequence": request.sequence,
        "observed_mode": observed.get("fpga_algorithm"),
        "observed_sequence": observed.get("fpga_sequence"),
        "error": "命令已发送，但在超时前没有从后续 FPGA 视频帧读回对应模式。",
    }


if __name__ == "__main__":
    server.run(transport="stdio")
