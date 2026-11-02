#!/usr/bin/env python3
"""Continuous multi-frame perception beside the CAM1 1080p JPEG receiver.

This process deliberately reuses CaptureWorker and never changes FPGA transport or
display code. It samples OV5640 JPEG frames into a bounded temporal ring buffer, submits
only the newest temporal window to Qwen3-VL, and persists confirmed events.
"""

from __future__ import annotations

import base64
from collections import deque
from dataclasses import asdict, dataclass
from datetime import datetime
from difflib import SequenceMatcher
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import logging
import os
from pathlib import Path
import queue
import re
import sys
import threading
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlparse
from urllib.request import Request, urlopen

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parent
VIEWER_DIR = ROOT.parent / "camera_viewer"
if str(VIEWER_DIR) not in sys.path:
    sys.path.insert(0, str(VIEWER_DIR))

from cam1_live_viewer import CaptureWorker, Frame  # noqa: E402
from fpga_algorithm_control import (  # noqa: E402
    FpgaAlgorithmController,
    MODE_NAMES,
    MODE_VALUES,
)
from event_pipeline import (  # noqa: E402
    BoundedPriorityEventQueue,
    EventAuditLogger,
    MotionCandidate,
    MotionEventDetector,
)


def iso_time(epoch: float | None = None) -> str:
    value = time.time() if epoch is None else epoch
    return datetime.fromtimestamp(value).astimezone().isoformat(timespec="milliseconds")


def timestamp_epoch(value: Any, default: float = 0.0) -> float:
    """Parse an ISO timestamp without losing its explicit timezone."""
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return datetime.fromisoformat(str(value)).timestamp()
    except (TypeError, ValueError):
        return default


def load_config(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def frame_to_image(frame: Frame) -> Image.Image:
    if frame.encoding == "JPEG":
        with Image.open(io.BytesIO(frame.image_data)) as decoded:
            return decoded.convert("RGB")
    words = np.frombuffer(frame.image_data, dtype=">u2")
    little_endian = words.astype("<u2", copy=True).tobytes()
    return Image.frombytes(
        "RGB", (frame.width, frame.height), little_endian, "raw", "BGR;16"
    )


def resize_to_width(image: Image.Image, width: int) -> Image.Image:
    if width <= 0 or image.width <= width:
        return image
    height = max(1, round(image.height * width / image.width))
    return image.resize((width, height), Image.Resampling.BILINEAR)


def encode_jpeg(image: Image.Image, quality: int) -> bytes:
    output = io.BytesIO()
    image.save(output, format="JPEG", quality=quality, optimize=False)
    return output.getvalue()


@dataclass(frozen=True)
class BufferedFrame:
    frame_id: int
    timestamp_epoch: float
    timestamp: str
    width: int
    height: int
    jpeg: bytes
    motion_score: float
    motion_ratio: float
    motion_local_ratio: float
    fpga_algorithm: int
    fpga_threshold: int
    fpga_sequence: int


class VideoRingBuffer:
    def __init__(self, duration_seconds: float) -> None:
        self.duration_seconds = duration_seconds
        self._frames: deque[BufferedFrame] = deque()
        self._bytes = 0
        self._lock = threading.RLock()

    def append(self, frame: BufferedFrame) -> None:
        cutoff = frame.timestamp_epoch - self.duration_seconds
        with self._lock:
            self._frames.append(frame)
            self._bytes += len(frame.jpeg)
            while self._frames and self._frames[0].timestamp_epoch < cutoff:
                self._bytes -= len(self._frames.popleft().jpeg)

    def latest(self) -> BufferedFrame | None:
        with self._lock:
            return self._frames[-1] if self._frames else None

    def select_window(
        self, seconds: float, count: int, minimum: int
    ) -> list[BufferedFrame]:
        with self._lock:
            if not self._frames:
                return []
            cutoff = self._frames[-1].timestamp_epoch - seconds
            candidates = [item for item in self._frames if item.timestamp_epoch >= cutoff]
        if len(candidates) < minimum:
            return []
        count = min(count, len(candidates))
        if count == 1:
            return [candidates[-1]]
        indices = [round(i * (len(candidates) - 1) / (count - 1)) for i in range(count)]
        return [candidates[index] for index in indices]

    def select_event_frames(
        self,
        candidate: MotionCandidate,
        pre_seconds: float,
        count: int,
    ) -> list[BufferedFrame]:
        """Select phase-aware evidence around a completed motion candidate."""
        with self._lock:
            start = candidate.onset_epoch - pre_seconds
            end = candidate.finalized_epoch or candidate.last_motion_epoch
            candidates = [
                item for item in self._frames if start <= item.timestamp_epoch <= end
            ]
        if len(candidates) < 3:
            return []
        # A short event request still needs before, peak, and after evidence.
        if count <= 3:
            anchors = [start, candidate.peak_epoch, end]
        elif count == 4:
            anchors = [start, candidate.onset_epoch, candidate.peak_epoch, end]
        else:
            anchors = [
                start,
                candidate.onset_epoch,
                candidate.peak_epoch,
                candidate.last_motion_epoch,
                end,
            ]
        selected: list[BufferedFrame] = []
        for anchor in anchors:
            nearest = min(candidates, key=lambda item: abs(item.timestamp_epoch - anchor))
            if nearest not in selected:
                selected.append(nearest)
        # Fill remaining slots uniformly across the complete before→after range.
        if len(selected) < count:
            for index in [
                round(i * (len(candidates) - 1) / max(count - 1, 1))
                for i in range(count)
            ]:
                item = candidates[index]
                if item not in selected:
                    selected.append(item)
                if len(selected) >= count:
                    break
        selected.sort(key=lambda item: item.timestamp_epoch)
        return selected[:count]

    def metrics(self) -> dict[str, Any]:
        with self._lock:
            first = self._frames[0].timestamp_epoch if self._frames else None
            last = self._frames[-1].timestamp_epoch if self._frames else None
            return {
                "frame_count": len(self._frames),
                "duration_seconds": round((last - first), 3) if first and last else 0.0,
                "memory_bytes": self._bytes,
            }


@dataclass(frozen=True)
class AnalysisTask:
    task_id: int
    submitted_epoch: float
    trigger: str
    frames: tuple[BufferedFrame, ...]
    kind: str = "scene"
    candidate_id: str | None = None
    candidate: dict[str, Any] | None = None


class LatestTaskSlot:
    """One pending slot: a newer video window replaces a stale pending window."""

    def __init__(self) -> None:
        self._condition = threading.Condition()
        self._task: AnalysisTask | None = None
        self._closed = False
        self.replaced = 0

    def put(self, task: AnalysisTask) -> None:
        with self._condition:
            if self._task is not None:
                self.replaced += 1
            self._task = task
            self._condition.notify()

    def get(self, timeout: float = 0.5) -> AnalysisTask | None:
        with self._condition:
            if self._task is None and not self._closed:
                self._condition.wait(timeout)
            task, self._task = self._task, None
            return task

    def close(self) -> None:
        with self._condition:
            self._closed = True
            self._condition.notify_all()


def _number(value: Any, default: float = 0.0) -> float:
    try:
        return max(0.0, min(1.0, float(value)))
    except (TypeError, ValueError):
        return default


def parse_json_response(text: str) -> dict[str, Any]:
    cleaned = text.strip()
    cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s*```$", "", cleaned)
    start = cleaned.find("{")
    if start < 0:
        raise ValueError("model response did not contain a JSON object")
    value, _ = json.JSONDecoder().raw_decode(cleaned[start:])
    if not isinstance(value, dict):
        raise ValueError("model response JSON was not an object")
    return value


class SceneMemory:
    def __init__(self, config: dict[str, Any]) -> None:
        self.path = ROOT / config["state_file"]
        self.minimum_confidence = float(config["minimum_event_confidence"])
        self.dedup_seconds = float(config["event_dedup_seconds"])
        self.max_events = int(config["max_events"])
        self.max_understandings = int(config["max_understandings"])
        self.max_pending_events = int(config.get("max_pending_events", 300))
        self.max_candidates = int(config.get("max_candidates", 300))
        self._lock = threading.RLock()
        self._state: dict[str, Any] = {
            "version": 3,
            "started_at": iso_time(),
            "current_scene": {},
            "events": [],
            "understandings": [],
            "uncertain_events": [],
            "pending_events": [],
            "event_candidates": [],
        }
        self._load()

    def _load(self) -> None:
        try:
            with self.path.open("r", encoding="utf-8") as handle:
                loaded = json.load(handle)
            if isinstance(loaded, dict):
                self._state.update(loaded)
                self._state["version"] = 3
                candidates = {
                    item.get("candidate_id"): item
                    for item in self._state.get("event_candidates", [])
                    if item.get("candidate_id")
                }
                confirmed_ids = {
                    id(item) for item in self._state.get("events", [])
                }
                for event in (
                    list(self._state.get("events", []))
                    + list(self._state.get("pending_events", []))
                ):
                    event.setdefault(
                        "status",
                        "legacy_confirmed"
                        if id(event) in confirmed_ids
                        else "pending_confirmation",
                    )
                    event.setdefault("confirmation_source", "legacy_scene_window")
                    candidate = candidates.get(event.get("candidate_id")) or {}
                    evidence_epochs = [
                        timestamp_epoch(value)
                        for value in event.get("evidence_timestamps", [])
                    ]
                    evidence_epochs = [value for value in evidence_epochs if value > 0]
                    event.setdefault(
                        "evidence_start_epoch",
                        min(evidence_epochs) if evidence_epochs else 0.0,
                    )
                    event.setdefault(
                        "evidence_end_epoch",
                        max(evidence_epochs) if evidence_epochs else 0.0,
                    )
                    event.setdefault(
                        "occurred_at_epoch",
                        float(candidate.get("peak_epoch", 0.0))
                        or timestamp_epoch(event.get("occurred_at"))
                        or event.get("evidence_end_epoch", 0.0)
                        or float(event.get("recorded_at_epoch", 0.0)),
                    )
        except (OSError, ValueError):
            pass

    @staticmethod
    def _event_key(event: dict[str, Any]) -> str:
        fields = [event.get("type"), event.get("subject"), event.get("object")]
        return "|".join(str(value or "").strip().lower() for value in fields)

    @staticmethod
    def _similar(left: dict[str, Any], right: dict[str, Any]) -> bool:
        if SceneMemory._event_key(left) != SceneMemory._event_key(right):
            return False
        a = str(left.get("description") or "").strip().lower()
        b = str(right.get("description") or "").strip().lower()
        if not a or not b:
            return True
        return SequenceMatcher(None, a, b).ratio() >= 0.72

    def register_candidate(self, candidate: MotionCandidate) -> None:
        value = candidate.to_dict()
        with self._lock:
            candidates = self._state.setdefault("event_candidates", [])
            candidates.append(value)
            self._state["event_candidates"] = candidates[-self.max_candidates :]
            self._persist_locked()

    def update_candidate(self, candidate_id: str, status: str, **fields: Any) -> None:
        with self._lock:
            candidates = self._state.setdefault("event_candidates", [])
            match = next(
                (item for item in reversed(candidates) if item.get("candidate_id") == candidate_id),
                None,
            )
            if match is None:
                match = {"candidate_id": candidate_id}
                candidates.append(match)
            match.update(fields)
            match["status"] = status
            match["status_updated_at"] = iso_time()
            self._state["event_candidates"] = candidates[-self.max_candidates :]
            self._persist_locked()

    def apply(
        self,
        result: dict[str, Any],
        task: AnalysisTask,
        inference_seconds: float,
        usage: dict[str, Any] | None,
        audit: EventAuditLogger | None = None,
        inference_started_epoch: float | None = None,
    ) -> dict[str, Any]:
        completed_epoch = time.time()
        inference_started_epoch = inference_started_epoch or (
            completed_epoch - inference_seconds
        )
        model_completed_epoch = inference_started_epoch + inference_seconds
        window_start = task.frames[0].timestamp
        window_end = task.frames[-1].timestamp
        candidate = task.candidate or {}
        candidate_onset_epoch = float(candidate.get("onset_epoch", task.frames[0].timestamp_epoch))
        candidate_finalized_epoch = float(
            candidate.get("finalized_epoch") or task.frames[-1].timestamp_epoch
        )
        timing = {
            "candidate_onset_epoch": candidate_onset_epoch,
            "candidate_finalized_epoch": candidate_finalized_epoch,
            "task_submitted_epoch": task.submitted_epoch,
            "inference_started_epoch": inference_started_epoch,
            "model_completed_epoch": model_completed_epoch,
            "memory_written_epoch": completed_epoch,
            "candidate_capture_seconds": round(
                max(0.0, candidate_finalized_epoch - candidate_onset_epoch), 3
            ),
            "queue_wait_seconds": round(
                max(0.0, inference_started_epoch - task.submitted_epoch), 3
            ),
            "inference_seconds": round(inference_seconds, 3),
            "parse_and_persist_seconds": round(
                max(0.0, completed_epoch - model_completed_epoch), 3
            ),
        }
        scene_confidence = _number(result.get("scene_confidence"), 0.5)
        observations = []
        for raw in result.get("observations") or []:
            if not isinstance(raw, dict):
                continue
            item = dict(raw)
            item["confidence"] = _number(item.get("confidence"), 0.0)
            item["confirmed"] = item["confidence"] >= self.minimum_confidence
            observations.append(item)
        understanding = {
            "task_id": task.task_id,
            "task_kind": task.kind,
            "candidate_id": task.candidate_id,
            "trigger": task.trigger,
            "window_start": window_start,
            "window_end": window_end,
            "frame_ids": [item.frame_id for item in task.frames],
            "frame_count": len(task.frames),
            "motion_score": round(max(item.motion_score for item in task.frames), 4),
            "motion_ratio": round(max(item.motion_ratio for item in task.frames), 6),
            "motion_local_ratio": round(
                max(item.motion_local_ratio for item in task.frames), 6
            ),
            "analysis_completed": iso_time(completed_epoch),
            "analysis_completed_epoch": completed_epoch,
            "inference_seconds": round(inference_seconds, 3),
            "timing": timing,
            "scene_type": str(result.get("scene_type") or "").strip(),
            "scene_summary": str(result.get("scene_summary") or "").strip(),
            "environment": str(result.get("environment") or "").strip(),
            "current_state": str(result.get("current_state") or "").strip(),
            "scene_confidence": scene_confidence,
            "observations": observations,
            "uncertainties": result.get("uncertainties") or [],
            "usage": usage or {},
        }
        confirmed: list[dict[str, Any]] = []
        pending: list[dict[str, Any]] = []
        for raw in result.get("events") or []:
            if not isinstance(raw, dict):
                continue
            event = dict(raw)
            event["type"] = str(event.get("type") or event.get("action_type") or "other")
            event["action_type"] = event["type"]
            event["confidence"] = _number(event.get("confidence"), 0.0)
            event["window_start"] = window_start
            event["window_end"] = window_end
            event["recorded_at"] = iso_time(completed_epoch)
            event["recorded_at_epoch"] = completed_epoch
            event["evidence_frame_ids"] = [item.frame_id for item in task.frames]
            event["evidence_timestamps"] = [item.timestamp for item in task.frames]
            event["candidate_id"] = task.candidate_id
            indexes = []
            for value in event.get("evidence_frames") or []:
                try:
                    index = int(value) - 1
                except (TypeError, ValueError):
                    continue
                if 0 <= index < len(task.frames):
                    indexes.append(index)
            evidence_frames = (
                [task.frames[index] for index in sorted(set(indexes))]
                if indexes
                else list(task.frames)
            )
            evidence_epochs = [item.timestamp_epoch for item in evidence_frames]
            event["semantic_evidence_frame_ids"] = [
                item.frame_id for item in evidence_frames
            ]
            event["semantic_evidence_timestamps"] = [
                item.timestamp for item in evidence_frames
            ]
            event["evidence_start_epoch"] = min(evidence_epochs)
            event["evidence_end_epoch"] = max(evidence_epochs)
            event["occurred_at_epoch"] = sum(evidence_epochs) / len(evidence_epochs)
            event["occurred_at"] = iso_time(event["occurred_at_epoch"])
            event["timing"] = {
                **timing,
                "event_report_delay_seconds": round(
                    max(0.0, completed_epoch - event["occurred_at_epoch"]), 3
                ),
            }
            event["objects"] = event.get("objects") or [
                value
                for value in [event.get("subject"), event.get("object")]
                if value
            ]
            event["before_state"] = str(event.get("before_state") or "").strip()
            event["after_state"] = str(event.get("after_state") or "").strip()
            # A periodic scene refresh may notice a possible action, but only a
            # motion-backed before/middle/after task may confirm it as fact.
            event["confirmed"] = (
                task.kind == "event"
                and event["confidence"] >= self.minimum_confidence
            )
            event["status"] = "confirmed" if event["confirmed"] else "pending_confirmation"
            event["confirmation_source"] = (
                "motion_candidate_multiframe"
                if task.kind == "event"
                else "scene_refresh_without_motion_candidate"
            )
            (confirmed if event["confirmed"] else pending).append(event)
        understanding["confirmed_events"] = confirmed
        understanding["pending_events"] = pending
        understanding["uncertain_events"] = pending
        memory_decisions: list[dict[str, Any]] = []

        with self._lock:
            events: list[dict[str, Any]] = self._state.setdefault("events", [])
            for event in confirmed:
                duplicate = None
                for old in reversed(events[-30:]):
                    old_epoch = float(
                        old.get("last_occurred_at_epoch")
                        or old.get("occurred_at_epoch")
                        or old.get("recorded_at_epoch", 0.0)
                    )
                    age = event["occurred_at_epoch"] - old_epoch
                    if age > self.dedup_seconds:
                        break
                    if age >= 0 and self._similar(old, event):
                        duplicate = old
                        break
                if duplicate is None:
                    event["event_id"] = f"event-{int(completed_epoch * 1000)}-{len(events) + 1}"
                    events.append(event)
                    decision = {
                        "event_id": event["event_id"],
                        "decision": "written_confirmed",
                        "confidence": event["confidence"],
                    }
                    memory_decisions.append(decision)
                    if audit:
                        audit.record(
                            "event_written",
                            task.candidate_id,
                            **decision,
                            action_type=event["type"],
                            object=event.get("object"),
                        )
                else:
                    duplicate.setdefault("first_occurred_at", duplicate.get("occurred_at"))
                    duplicate.setdefault(
                        "first_occurred_at_epoch", duplicate.get("occurred_at_epoch")
                    )
                    duplicate["last_seen"] = event["recorded_at"]
                    duplicate["last_seen_epoch"] = completed_epoch
                    duplicate["last_occurred_at"] = event["occurred_at"]
                    duplicate["last_occurred_at_epoch"] = event["occurred_at_epoch"]
                    for field in (
                        "occurred_at",
                        "occurred_at_epoch",
                        "evidence_start_epoch",
                        "evidence_end_epoch",
                        "evidence_frame_ids",
                        "evidence_timestamps",
                        "semantic_evidence_frame_ids",
                        "semantic_evidence_timestamps",
                        "candidate_id",
                        "window_start",
                        "window_end",
                        "before_state",
                        "after_state",
                        "description",
                        "timing",
                    ):
                        duplicate[field] = event.get(field)
                    duplicate["duplicate_count"] = int(duplicate.get("duplicate_count", 0)) + 1
                    duplicate["confidence"] = max(
                        float(duplicate.get("confidence", 0.0)), event["confidence"]
                    )
                    decision = {
                        "event_id": duplicate.get("event_id"),
                        "decision": "merged_duplicate",
                        "confidence": event["confidence"],
                    }
                    memory_decisions.append(decision)
                    if audit:
                        audit.record(
                            "dedup_merged",
                            task.candidate_id,
                            **decision,
                            description=event.get("description"),
                        )
            self._state["events"] = events[-self.max_events :]
            pending_events: list[dict[str, Any]] = self._state.setdefault(
                "pending_events", []
            )
            for event in pending:
                duplicate_pending = None
                for old in reversed(pending_events[-30:]):
                    old_epoch = float(
                        old.get("last_occurred_at_epoch")
                        or old.get("occurred_at_epoch")
                        or old.get("recorded_at_epoch", 0.0)
                    )
                    age = event["occurred_at_epoch"] - old_epoch
                    if age > self.dedup_seconds:
                        break
                    if age >= 0 and self._similar(old, event):
                        duplicate_pending = old
                        break
                if duplicate_pending is not None:
                    duplicate_pending["last_occurred_at"] = event["occurred_at"]
                    duplicate_pending["last_occurred_at_epoch"] = event[
                        "occurred_at_epoch"
                    ]
                    duplicate_pending["last_seen"] = event["recorded_at"]
                    duplicate_pending["last_seen_epoch"] = completed_epoch
                    duplicate_pending["duplicate_count"] = int(
                        duplicate_pending.get("duplicate_count", 0)
                    ) + 1
                    duplicate_pending["confidence"] = max(
                        float(duplicate_pending.get("confidence", 0.0)),
                        event["confidence"],
                    )
                    decision = {
                        "pending_id": duplicate_pending.get("pending_id"),
                        "decision": "merged_pending_duplicate",
                        "confidence": event["confidence"],
                    }
                    memory_decisions.append(decision)
                    if audit:
                        audit.record(
                            "pending_dedup_merged",
                            task.candidate_id,
                            **decision,
                            description=event.get("description"),
                        )
                    continue
                event["pending_id"] = (
                    f"pending-{int(completed_epoch * 1000)}-{len(pending_events) + 1}"
                )
                reason = (
                    "confidence_below_threshold"
                    if task.kind == "event"
                    else "no_motion_candidate_evidence"
                )
                event["pending_reason"] = reason
                pending_events.append(event)
                decision = {
                    "pending_id": event["pending_id"],
                    "decision": "written_pending",
                    "reason": reason,
                    "confidence": event["confidence"],
                }
                memory_decisions.append(decision)
                if audit:
                    audit.record(
                        "event_pending",
                        task.candidate_id,
                        **decision,
                        action_type=event["type"],
                        description=event.get("description"),
                    )
            self._state["pending_events"] = pending_events[-self.max_pending_events :]
            self._state["uncertain_events"] = pending[-20:]
            existing_scene = self._state.get("current_scene") or {}
            if task.frames[-1].timestamp_epoch >= float(
                existing_scene.get("frame_time_end_epoch", 0.0)
            ):
                self._state["current_scene"] = {
                    "scene_type": understanding["scene_type"],
                    "summary": understanding["scene_summary"],
                    "environment": understanding["environment"],
                    "current_state": understanding["current_state"],
                    "confidence": scene_confidence,
                    "confirmed": scene_confidence >= self.minimum_confidence,
                    "observations": observations,
                    "uncertainties": understanding["uncertainties"],
                    "frame_time_start": window_start,
                    "frame_time_end": window_end,
                    "frame_time_end_epoch": task.frames[-1].timestamp_epoch,
                    "updated_at": understanding["analysis_completed"],
                }
            history: list[dict[str, Any]] = self._state.setdefault("understandings", [])
            history.append(understanding)
            self._state["understandings"] = history[-self.max_understandings :]
            understanding["memory_decisions"] = memory_decisions
            if task.candidate_id:
                candidate_status = (
                    "confirmed"
                    if confirmed
                    else "pending_confirmation"
                    if pending
                    else "no_semantic_event"
                )
                candidates = self._state.setdefault("event_candidates", [])
                match = next(
                    (
                        item
                        for item in reversed(candidates)
                        if item.get("candidate_id") == task.candidate_id
                    ),
                    None,
                )
                if match is not None:
                    match.update(
                        {
                            "status": candidate_status,
                            "status_updated_at": iso_time(completed_epoch),
                            "confirmed_event_count": len(confirmed),
                            "pending_event_count": len(pending),
                        }
                    )
            self._persist_locked()
        return understanding

    def _persist_locked(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(".tmp")
        with temporary.open("w", encoding="utf-8") as handle:
            json.dump(self._state, handle, ensure_ascii=False, indent=2)
        os.replace(temporary, self.path)

    def current_scene(self) -> dict[str, Any]:
        with self._lock:
            return json.loads(json.dumps(self._state.get("current_scene") or {}))

    def stats(self) -> dict[str, Any]:
        with self._lock:
            return {
                "path": str(self.path.resolve()),
                "version": self._state.get("version"),
                "confirmed_event_count": len(self._state.get("events", [])),
                "pending_event_count": len(self._state.get("pending_events", [])),
                "candidate_count": len(self._state.get("event_candidates", [])),
                "understanding_count": len(self._state.get("understandings", [])),
            }

    def recent_events(
        self, seconds: float, limit: int, include_pending: bool = False
    ) -> list[dict[str, Any]]:
        cutoff = time.time() - max(0.0, seconds)
        with self._lock:
            values = [
                item
                for item in self._state.get("events", [])
                if self._event_epoch(item) >= cutoff
            ]
            if include_pending:
                values.extend(
                    item
                    for item in self._state.get("pending_events", [])
                    if self._event_epoch(item) >= cutoff
                )
            values.sort(key=self._event_epoch)
        return values[-max(1, limit) :]

    @staticmethod
    def _event_epoch(item: dict[str, Any]) -> float:
        return float(
            item.get("last_occurred_at_epoch")
            or item.get("occurred_at_epoch")
            or item.get("evidence_end_epoch")
            or item.get("recorded_at_epoch", 0.0)
        )

    def recent_candidates(self, seconds: float, limit: int) -> list[dict[str, Any]]:
        cutoff = time.time() - max(0.0, seconds)
        with self._lock:
            values = [
                item
                for item in self._state.get("event_candidates", [])
                if float(item.get("onset_epoch", 0.0)) >= cutoff
            ]
        return values[-max(1, limit) :]

    def recent_understandings(self, seconds: float, limit: int) -> list[dict[str, Any]]:
        cutoff = time.time() - max(0.0, seconds)
        with self._lock:
            values = [
                item
                for item in self._state.get("understandings", [])
                if float(item.get("analysis_completed_epoch", 0.0)) >= cutoff
            ]
        return values[-max(1, limit) :]

    def search(self, query: str, seconds: float, limit: int) -> dict[str, Any]:
        confirmed_events = self.recent_events(
            seconds, self.max_events, include_pending=False
        )
        all_events = self.recent_events(
            seconds,
            self.max_events + self.max_pending_events,
            include_pending=True,
        )
        pending_events = [
            item for item in all_events if item.get("status") == "pending_confirmation"
        ]
        needle = query.strip().lower()
        matches: list[dict[str, Any]] = []
        intent_types: set[str] = set()
        intent_terms = {
            "picked_up": ("拿", "取", "拾", "pick", "held", "hold"),
            "moved": ("移动", "移到", "move"),
            "put_down": ("放下", "放到", "put down", "placed"),
            "appeared": ("出现", "进入", "appear", "enter"),
            "disappeared": ("消失", "离开", "移出", "disappear", "leave"),
        }
        for event_type, terms in intent_terms.items():
            if any(term in needle for term in terms):
                intent_types.add(event_type)
        if any(term in needle for term in ("去哪", "哪里", "where did", "where is")):
            intent_types.update({"moved", "put_down", "disappeared"})
        if intent_types:
            matches = [
                item
                for item in confirmed_events
                if str(item.get("type") or item.get("action_type") or "")
                in intent_types
            ]
        elif needle:
            for item in confirmed_events:
                haystack = json.dumps(item, ensure_ascii=False).lower()
                if needle in haystack or any(
                    token in haystack for token in re.findall(r"[\w\u4e00-\u9fff]{2,}", needle)
                ):
                    matches.append(item)
        if not matches and not intent_types:
            matches = confirmed_events
        pending_matches = [
            item
            for item in pending_events
            if (
                not intent_types
                or str(item.get("type") or item.get("action_type") or "")
                in intent_types
            )
        ][-max(1, limit) :]
        return {
            "query": query,
            "matched_by_text": bool(needle and matches != confirmed_events),
            "intent_types": sorted(intent_types),
            "events": matches[-max(1, limit) :],
            "pending_events": pending_matches,
            "current_scene": self.current_scene(),
            "query_epoch": time.time(),
            "query_time": iso_time(),
            "memory_path": str(self.path.resolve()),
            "note": (
                "Only events saved before this query are returned. Confirmed items have "
                "multi-frame evidence; pending items are clues and must be described as "
                "unconfirmed, not omitted. Only an empty confirmed and pending result "
                "means there is no matching saved evidence in the requested time range."
            ),
        }


class QwenMultiFrameClient:
    def __init__(
        self,
        config: dict[str, Any],
        image_width: int,
        algorithm_control_enabled: bool = True,
        scene_image_width: int | None = None,
    ) -> None:
        self.base_url = str(config["base_url"]).rstrip("/")
        self.model = str(config["model"])
        self.timeout = float(config["timeout_seconds"])
        self.temperature = float(config["temperature"])
        self.max_tokens = int(config["max_tokens"])
        self.max_retries = max(0, int(config.get("max_retries", 1)))
        self.retry_delay = max(0.0, float(config.get("retry_delay_seconds", 0.5)))
        self.image_width = image_width
        self.scene_image_width = max(image_width, int(scene_image_width or image_width))
        self.algorithm_control_enabled = algorithm_control_enabled

    def request_analysis(
        self, task: AnalysisTask, previous_scene: dict[str, Any]
    ) -> tuple[str, dict[str, Any]]:
        start_epoch = task.frames[0].timestamp_epoch
        previous_summary = json.dumps(
            {
                "场景类型": previous_scene.get("scene_type", ""),
                "场景": previous_scene.get("summary", ""),
                "环境": previous_scene.get("environment", ""),
                "当前状态": previous_scene.get("current_state", ""),
                "物体": previous_scene.get("observations", []),
            },
            ensure_ascii=False,
        )[:600]
        if task.kind == "event":
            task_context = (
                "这是像素变化候选，不等于动作事实。联合比较前/中/后帧，判断物体出现、消失、"
                "移动、拿起或放下。每个事件必须填写真正支持它的 evidence_frames；证据不足则"
                "events 为空或低置信，禁止靠常识补全。同一窗口可输出多个不同事实：若物体既"
                "被拿起又明显改变画面位置，应分别输出 picked_up 和 moved。为降低实时延迟，"
                "仍须描述窗口结束时的场景、背景和当前状态；observations 最多4项。"
                "每个事件的 before_state/after_state 要写清物体位置、可见性或人与物体的关系变化，"
                "description 保持简短，不超过30字。"
            )
            observation_limit = 4
        else:
            task_context = (
                "这是静态场景理解任务，不是动作描述任务。先判断场景类型（如卧室、办公室、厨房、"
                "室外或无法判断），再逐一列出画面中清晰可见的主要人物和物体，说明它们的位置、"
                "当前状态、是否被遮挡及彼此关系；不要只复述动作。即使完全静止也必须给出场景和物体清单。"
                "无法确认具体类别时写‘不确定’，可描述外观，不得漏掉明显的大型物体。没有动作证据时 events 为空。"
            )
            observation_limit = 8
        if self.algorithm_control_enabled:
            algorithm_instruction = (
                "另外评估当前场景是否需要切换 OV5640 传感器图像效果；FPGA 将主机命令经 SCCB 写入传感器并在帧边界应用，"
                "普通场景保持彩色；binary 对应 OV5640 黑白效果，不是 FPGA 逐像素阈值处理。只有明确收益时才提出 color、gray、binary、invert 建议。"
            )
            algorithm_schema = (
                '"fpga_recommendation":{"mode":"color|gray|binary|invert|none",'
                '"threshold":128,"confidence":0.0,"reason":"简短依据"},'
            )
        else:
            algorithm_instruction = (
                "本次配置未启用自动图像模式选择；将 fpga_recommendation.mode 设为 none，不要建议自动切换。"
            )
            algorithm_schema = (
                '"fpga_recommendation":{"mode":"none","threshold":128,'
                '"confidence":0.0,"reason":"自动OV5640图像模式选择未启用"},'
            )
        content: list[dict[str, Any]] = [
            {
                "type": "text",
                "text": (
                    "你是严格的视频时序观察器。输入是同一摄像头按时间排序的多帧。"
                    + task_context
                    + algorithm_instruction
                    + "只报告画面直接证明的内容，不确定内容写入 uncertainties。"
                    "scene_type 必须填写场景类别或‘无法判断’；scene_summary 用1-2句概括整个当前画面及整体状态；environment 描述可见的空间/"
                    "背景/稳定布局；current_state 描述此刻人和物体在哪里、姿态/可见性如何、彼此关系如何。"
                    f"observations 最多{observation_limit}项，按显著程度排列；events 最多3项。物体名称、状态和位置写具体短语。"
                    f"上次场景信息（仅用于比较，不可当成本次证据）:{previous_summary}\n"
                    "只返回紧凑 JSON，字段为："
                    '{"scene_type":"场景类别或无法判断","scene_summary":"当前场景与整体状态，1-2句","environment":"环境和背景布局",'
                    '"current_state":"当前人/物体的位置、姿态、可见性和关系", "scene_confidence":0.0,'
                    '"observations":[{"name":"物体名称","position":"具体位置","state":"当前可见状态", "confidence":0.0}],'
                    '"events":[{"type":"appeared|disappeared|moved|picked_up|put_down|interaction|scene_change|other","subject":"主体","object":"客体或空字符串","objects":["涉及物体"],"before_state":"动作前状态","after_state":"动作后状态","description":"事件","confidence":0.0,"evidence_frames":[1,2]}],'
                    + algorithm_schema
                    + '"uncertainties":["无法确认的内容"]}'
                ),
            }
        ]
        for index, frame in enumerate(task.frames, 1):
            with Image.open(io.BytesIO(frame.jpeg)) as source:
                image = source.convert("RGB")
            target_width = (
                self.scene_image_width if task.kind == "periodic" else self.image_width
            )
            image = resize_to_width(image, target_width)
            jpeg = encode_jpeg(image, 76)
            relative = frame.timestamp_epoch - start_epoch
            phase = "scene"
            if task.kind == "event" and task.candidate:
                onset = float(task.candidate["onset_epoch"])
                peak = float(task.candidate["peak_epoch"])
                last_motion = float(
                    task.candidate.get("motion_end_epoch")
                    or task.candidate["last_motion_epoch"]
                )
                if frame.timestamp_epoch < onset:
                    phase = "before"
                elif abs(frame.timestamp_epoch - peak) <= 0.25:
                    phase = "motion_peak"
                elif frame.timestamp_epoch <= last_motion:
                    phase = "during_motion"
                else:
                    phase = "after"
            content.append(
                {
                    "type": "text",
                    "text": f"帧{index}/{len(task.frames)}；阶段={phase}；时间={frame.timestamp}；相对窗口开始=+{relative:.3f}秒；帧号={frame.frame_id}",
                }
            )
            content.append(
                {
                    "type": "image_url",
                    "image_url": {
                        "url": "data:image/jpeg;base64,"
                        + base64.b64encode(jpeg).decode("ascii")
                    },
                }
            )
        payload = {
            "model": self.model,
            "messages": [{"role": "user", "content": content}],
            "temperature": self.temperature,
            "max_tokens": self.max_tokens,
            "response_format": {"type": "json_object"},
        }
        request = Request(
            f"{self.base_url}/chat/completions",
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        body: dict[str, Any] | None = None
        attempts = 0
        while body is None:
            attempts += 1
            try:
                with urlopen(request, timeout=self.timeout) as response:
                    body = json.loads(response.read().decode("utf-8"))
            except HTTPError as error:
                if error.code not in {502, 503, 504} or attempts > self.max_retries:
                    raise
                time.sleep(self.retry_delay)
            except URLError:
                if attempts > self.max_retries:
                    raise
                time.sleep(self.retry_delay)
        message = body["choices"][0]["message"]["content"]
        if isinstance(message, list):
            message = "".join(
                str(part.get("text") or "") for part in message if isinstance(part, dict)
            )
        usage = body.get("usage") or {}
        usage["client_attempts"] = attempts
        return str(message), usage


class ContinuousPerception:
    def __init__(self, config: dict[str, Any]) -> None:
        self.config = config
        capture = config["capture"]
        analysis = config["analysis"]
        self.stop_event = threading.Event()
        self.frame_queue: queue.Queue[Frame] = queue.Queue(maxsize=2)
        self.status_queue: queue.Queue[tuple[str, object]] = queue.Queue()
        self.buffer = VideoRingBuffer(float(capture["buffer_seconds"]))
        self.memory = SceneMemory(config["memory"])
        self.slot = LatestTaskSlot()
        events = config["events"]
        self.audit = EventAuditLogger(ROOT / events["audit_file"])
        self.event_queue = BoundedPriorityEventQueue(int(events["queue_capacity"]))
        self.motion_detector = MotionEventDetector(
            config["motion"], self._finalize_motion_candidate, self.audit
        )
        self.algorithm_config = config.get("algorithm_control", {})
        self.algorithm_queue: queue.Queue[dict[str, Any]] = queue.Queue(maxsize=1)
        self.algorithm_consensus_mode: str | None = None
        self.algorithm_consensus_count = 0
        self.algorithm_last_change = 0.0
        self.algorithm_thread: threading.Thread | None = None
        self.evidence_directory = ROOT / events["evidence_directory"]
        self.archive_evidence = bool(events.get("archive_evidence", True))
        self.model = QwenMultiFrameClient(
            config["model"],
            int(analysis["image_width"]),
            bool(self.algorithm_config.get("enabled", True)),
            int(analysis.get("scene_image_width", analysis["image_width"])),
        )
        self._capture_thread: threading.Thread | None = None
        self._scheduler_thread: threading.Thread | None = None
        self._inference_thread: threading.Thread | None = None
        self._lock = threading.RLock()
        self._frame_times: deque[float] = deque()
        self._latest_frame_meta: dict[str, Any] = {}
        # Keep a fresh, native-resolution preview independently from the
        # lower-rate AI ring buffer. The OV5640 JPEG stream can be served directly.
        self._latest_preview_jpeg: bytes | None = None
        self._latest_preview_timestamp = ""
        self._latest_preview_frame_id = 0
        self._last_preview_encode_time = 0.0
        self._capture_status: dict[str, Any] = {}
        self._last_motion_gray: np.ndarray | None = None
        self._last_sample_time = 0.0
        self._last_submit_time = 0.0
        self._task_counter = 0
        self.instance_id = f"cam1-{os.getpid()}-{int(time.time())}"
        self._event_timing_samples: deque[dict[str, float]] = deque(maxlen=100)
        self._metrics: dict[str, Any] = {
            "started_at": iso_time(),
            "semantic_state": "starting",
            "inference_count": 0,
            "scene_inference_count": 0,
            "event_inference_count": 0,
            "inference_errors": 0,
            "last_inference_seconds": None,
            "last_error": None,
            "last_analysis_window_end": None,
            "motion_candidates": 0,
            "event_tasks_enqueued": 0,
            "event_tasks_dropped": 0,
            "scene_refreshes_skipped_for_events": 0,
            "latest_motion_ratio": 0.0,
            "latest_local_motion_ratio": 0.0,
            "algorithm_auto_state": (
                "waiting_for_scene_evidence"
                if self.algorithm_config.get("enabled", True)
                else "disabled_jpeg_stream"
            ),
            "algorithm_auto_last_decision": None,
        }

    def start(self) -> None:
        self._capture_thread = threading.Thread(
            target=self._capture_loop, name="continuous-capture", daemon=True
        )
        self._scheduler_thread = threading.Thread(
            target=self._scheduler_loop, name="semantic-scheduler", daemon=True
        )
        self._inference_thread = threading.Thread(
            target=self._inference_loop, name="qwen-multiframe", daemon=True
        )
        if self.algorithm_config.get("enabled", True):
            self.algorithm_thread = threading.Thread(
                target=self._algorithm_control_loop,
                name="fpga-algorithm-agent",
                daemon=True,
            )
        self._capture_thread.start()
        self._scheduler_thread.start()
        self._inference_thread.start()
        if self.algorithm_thread is not None:
            self.algorithm_thread.start()

    def stop(self) -> None:
        self.stop_event.set()
        self.slot.close()
        self.event_queue.close()

    def _capture_loop(self) -> None:
        capture = self.config["capture"]
        sample_interval = 1.0 / float(capture["buffer_fps"])
        while not self.stop_event.is_set():
            worker = CaptureWorker(
                self.frame_queue,
                self.status_queue,
                self.stop_event,
                str(capture["interface"]),
            )
            worker.start()
            while not self.stop_event.is_set() and worker.is_alive():
                self._drain_capture_status()
                try:
                    frame = self.frame_queue.get(timeout=0.25)
                except queue.Empty:
                    continue
                now_mono = time.monotonic()
                now_epoch = time.time()
                timestamp = iso_time(now_epoch)
                preview_image: Image.Image | None = None
                preview_jpeg: bytes | None = None
                preview_fps = max(1.0, float(capture.get("preview_fps", 10.0)))
                if frame.encoding == "JPEG":
                    preview_jpeg = frame.image_data
                elif now_mono - self._last_preview_encode_time >= 1.0 / preview_fps:
                    preview_image = resize_to_width(
                        frame_to_image(frame),
                        int(capture.get("preview_width", 960)),
                    )
                    preview_jpeg = encode_jpeg(
                        preview_image,
                        int(capture.get("preview_jpeg_quality", 78)),
                    )
                    self._last_preview_encode_time = now_mono
                with self._lock:
                    if preview_jpeg is not None:
                        self._latest_preview_jpeg = preview_jpeg
                        self._latest_preview_timestamp = timestamp
                        self._latest_preview_frame_id = frame.frame_id
                    self._frame_times.append(now_mono)
                    cutoff = now_mono - 2.0
                    while self._frame_times and self._frame_times[0] < cutoff:
                        self._frame_times.popleft()
                    self._latest_frame_meta = {
                        "frame_id": frame.frame_id,
                        "width": frame.width,
                        "height": frame.height,
                        "encoding": frame.encoding,
                        "packet_count": frame.packet_count,
                        "timestamp": timestamp,
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
                if now_mono - self._last_sample_time < sample_interval:
                    continue
                self._last_sample_time = now_mono
                try:
                    full_image = (
                        preview_image
                        if preview_image is not None
                        else frame_to_image(frame)
                    )
                    image = resize_to_width(full_image, int(capture["buffer_width"]))
                    gray = np.asarray(
                        image.resize(
                            (int(capture["motion_width"]), int(capture["motion_height"])),
                            Image.Resampling.BILINEAR,
                        ).convert("L"),
                        dtype=np.float32,
                    )
                    motion = 0.0
                    motion_ratio = 0.0
                    local_motion_ratio = 0.0
                    if self._last_motion_gray is not None:
                        difference = np.abs(gray - self._last_motion_gray)
                        motion = float(np.mean(difference) / 255.0)
                        changed = difference >= float(self.config["motion"]["pixel_delta"])
                        motion_ratio = float(np.mean(changed))
                        rows = max(1, int(self.config["motion"]["grid_rows"]))
                        columns = max(1, int(self.config["motion"]["grid_columns"]))
                        local_values = [
                            float(np.mean(cell))
                            for row in np.array_split(changed, rows, axis=0)
                            for cell in np.array_split(row, columns, axis=1)
                            if cell.size
                        ]
                        local_motion_ratio = max(local_values, default=0.0)
                    self._last_motion_gray = gray
                    jpeg = encode_jpeg(image, int(capture["jpeg_quality"]))
                    buffered = BufferedFrame(
                        frame_id=frame.frame_id,
                        timestamp_epoch=now_epoch,
                        timestamp=iso_time(now_epoch),
                        width=image.width,
                        height=image.height,
                        jpeg=jpeg,
                        motion_score=motion,
                        motion_ratio=motion_ratio,
                        motion_local_ratio=local_motion_ratio,
                        fpga_algorithm=frame.fpga_algorithm,
                        fpga_threshold=frame.fpga_threshold,
                        fpga_sequence=frame.fpga_sequence,
                    )
                    self.buffer.append(buffered)
                    with self._lock:
                        self._metrics["latest_motion_score"] = round(motion, 6)
                        self._metrics["latest_motion_ratio"] = round(motion_ratio, 6)
                        self._metrics["latest_local_motion_ratio"] = round(
                            local_motion_ratio, 6
                        )
                    self.motion_detector.observe(buffered)
                except Exception as error:
                    logging.exception("frame sampling failed")
                    with self._lock:
                        self._metrics["last_error"] = f"frame sampling: {error}"
            self._drain_capture_status()
            if not self.stop_event.is_set():
                time.sleep(1.0)

    def _drain_capture_status(self) -> None:
        while True:
            try:
                kind, value = self.status_queue.get_nowait()
            except queue.Empty:
                return
            with self._lock:
                if kind == "stats" and hasattr(value, "__dataclass_fields__"):
                    self._capture_status[kind] = asdict(value)
                else:
                    self._capture_status[kind] = str(value)

    def _submit_window(self, trigger: str) -> bool:
        analysis = self.config["analysis"]
        frames = self.buffer.select_window(
            float(analysis["window_seconds"]),
            int(analysis["frame_count"]),
            int(analysis["minimum_frames"]),
        )
        if not frames:
            return False
        self._task_counter += 1
        self.slot.put(
            AnalysisTask(
                task_id=self._task_counter,
                submitted_epoch=time.time(),
                trigger=trigger,
                frames=tuple(frames),
            )
        )
        self._last_submit_time = time.monotonic()
        return True

    def _finalize_motion_candidate(self, candidate: MotionCandidate) -> None:
        """Freeze time-correct evidence and enqueue it independently of scene refreshes."""
        self.memory.register_candidate(candidate)
        with self._lock:
            self._metrics["motion_candidates"] += 1
        event_config = self.config["events"]
        frames = self.buffer.select_event_frames(
            candidate,
            float(self.config["motion"]["pre_seconds"]),
            int(event_config["frame_count"]),
        )
        self.audit.record(
            "keyframes_collected",
            candidate.candidate_id,
            requested=int(event_config["frame_count"]),
            selected=len(frames),
            frame_ids=[item.frame_id for item in frames],
            timestamps=[item.timestamp for item in frames],
        )
        if len(frames) < 3:
            self.memory.update_candidate(
                candidate.candidate_id,
                "insufficient_evidence_frames",
                selected_frame_count=len(frames),
            )
            self.audit.record(
                "event_task_not_enqueued",
                candidate.candidate_id,
                reason="insufficient_evidence_frames",
                selected_frame_count=len(frames),
            )
            return
        evidence_paths: list[str] = []
        if self.archive_evidence:
            evidence_dir = self.evidence_directory / candidate.candidate_id
            evidence_dir.mkdir(parents=True, exist_ok=True)
            for index, frame in enumerate(frames, 1):
                path = evidence_dir / f"frame_{index:02d}_{frame.frame_id}.jpg"
                path.write_bytes(frame.jpeg)
                evidence_paths.append(str(path))
            manifest = {
                "candidate": candidate.to_dict(),
                "frames": [
                    {
                        "frame_id": item.frame_id,
                        "timestamp": item.timestamp,
                        "timestamp_epoch": item.timestamp_epoch,
                        "motion_ratio": item.motion_ratio,
                        "motion_local_ratio": item.motion_local_ratio,
                        "path": evidence_paths[index],
                    }
                    for index, item in enumerate(frames)
                ],
            }
            (evidence_dir / "manifest.json").write_text(
                json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
            )
        self._task_counter += 1
        task = AnalysisTask(
            task_id=self._task_counter,
            submitted_epoch=time.time(),
            trigger="motion_candidate",
            frames=tuple(frames),
            kind="event",
            candidate_id=candidate.candidate_id,
            candidate=candidate.to_dict(),
        )
        accepted, displaced, reason = self.event_queue.put(task, candidate.peak_score)
        if accepted:
            self.memory.update_candidate(
                candidate.candidate_id,
                "queued_for_inference",
                evidence_frame_ids=[item.frame_id for item in frames],
                evidence_timestamps=[item.timestamp for item in frames],
                evidence_start_epoch=frames[0].timestamp_epoch,
                evidence_end_epoch=frames[-1].timestamp_epoch,
                evidence_paths=evidence_paths,
                queue_decision=reason,
                task_submitted_epoch=task.submitted_epoch,
            )
            with self._lock:
                self._metrics["event_tasks_enqueued"] += 1
            self.audit.record(
                "event_task_enqueued",
                candidate.candidate_id,
                task_id=task.task_id,
                priority=round(candidate.peak_score, 6),
                queue_decision=reason,
            )
            if displaced is not None:
                displaced_id = getattr(displaced, "candidate_id", None)
                if displaced_id:
                    self.memory.update_candidate(
                        displaced_id,
                        "dropped_queue_overload",
                        reason=reason,
                    )
                    self.audit.record(
                        "event_task_dropped",
                        displaced_id,
                        reason=reason,
                        replacement_candidate_id=candidate.candidate_id,
                    )
        else:
            self.memory.update_candidate(
                candidate.candidate_id,
                "dropped_queue_overload",
                reason=reason,
            )
            with self._lock:
                self._metrics["event_tasks_dropped"] += 1
            self.audit.record(
                "event_task_dropped", candidate.candidate_id, reason=reason
            )

    def _scheduler_loop(self) -> None:
        analysis = self.config["analysis"]
        interval = float(analysis["interval_seconds"])
        next_periodic = time.monotonic() + min(1.0, interval)
        while not self.stop_event.wait(0.1):
            now = time.monotonic()
            if now >= next_periodic:
                # A periodic scene refresh is replaceable; an action event is not.
                # Do not occupy the single Qwen lane while an action is being
                # collected, queued, or inferred. Event inference also refreshes
                # current_scene, so this does not leave a dynamic scene stale.
                queue_busy = self.event_queue.metrics()["pending"] > 0
                with self._lock:
                    inference_busy = "active_task_id" in self._metrics
                if self.motion_detector.active is None and not queue_busy and not inference_busy:
                    self._submit_window("periodic")
                else:
                    with self._lock:
                        self._metrics["scene_refreshes_skipped_for_events"] += 1
                next_periodic = now + interval

    def _inference_loop(self) -> None:
        cooldown = float(self.config["analysis"]["post_inference_cooldown_seconds"])
        while not self.stop_event.is_set():
            task = self.event_queue.get_nowait()
            if task is None:
                task = self.slot.get(0.25)
            if task is None:
                continue
            with self._lock:
                self._metrics["semantic_state"] = "inferencing"
                self._metrics["active_task_id"] = task.task_id
                self._metrics["active_task_kind"] = task.kind
                self._metrics["active_window_end"] = task.frames[-1].timestamp
            started = time.perf_counter()
            inference_started_epoch = time.time()
            try:
                if task.kind == "event":
                    self.memory.update_candidate(
                        task.candidate_id or "", "inferencing", task_id=task.task_id
                    )
                    self.audit.record(
                        "inference_started",
                        task.candidate_id,
                        task_id=task.task_id,
                        inference_started_epoch=inference_started_epoch,
                        queue_wait_seconds=round(
                            inference_started_epoch - task.submitted_epoch, 3
                        ),
                        evidence_timestamps=[item.timestamp for item in task.frames],
                    )
                raw, usage = self.model.request_analysis(
                    task, self.memory.current_scene()
                )
                elapsed = time.perf_counter() - started
                if task.kind == "event":
                    self.audit.record(
                        "model_response",
                        task.candidate_id,
                        task_id=task.task_id,
                        inference_seconds=round(elapsed, 3),
                        raw_response=raw[:8000],
                    )
                try:
                    result = parse_json_response(raw)
                except Exception as parse_error:
                    if task.kind == "event":
                        self.audit.record(
                            "json_parse_failed",
                            task.candidate_id,
                            error=str(parse_error),
                            raw_response=raw[:8000],
                        )
                    raise
                self._consider_algorithm_recommendation(result)
                if task.kind == "event":
                    self.audit.record(
                        "json_parsed",
                        task.candidate_id,
                        event_count=len(result.get("events") or []),
                        event_confidences=[
                            item.get("confidence")
                            for item in result.get("events") or []
                            if isinstance(item, dict)
                        ],
                    )
                understanding = self.memory.apply(
                    result,
                    task,
                    elapsed,
                    usage,
                    audit=self.audit,
                    inference_started_epoch=inference_started_epoch,
                )
                if task.kind == "event":
                    event_timings = [
                        dict(item.get("timing") or {})
                        for item in (
                            list(understanding.get("confirmed_events") or [])
                            + list(understanding.get("pending_events") or [])
                        )
                        if item.get("timing")
                    ]
                    if not event_timings:
                        event_timings = [dict(understanding.get("timing") or {})]
                    self._event_timing_samples.extend(event_timings)
                    if not understanding.get("memory_decisions"):
                        self.audit.record(
                            "event_not_saved",
                            task.candidate_id,
                            reason="model_returned_no_events",
                        )
                    self.audit.record(
                        "memory_decision_complete",
                        task.candidate_id,
                        decisions=understanding.get("memory_decisions", []),
                    )
                with self._lock:
                    self._metrics["inference_count"] += 1
                    self._metrics[f"{task.kind}_inference_count"] += 1
                    self._metrics["last_inference_seconds"] = round(elapsed, 3)
                    self._metrics["last_analysis_window_end"] = task.frames[-1].timestamp
                    self._metrics["last_analysis_completed"] = understanding[
                        "analysis_completed"
                    ]
                    self._metrics["last_error"] = None
            except Exception as error:
                logging.exception("multi-frame inference failed")
                if task.kind == "event":
                    self.memory.update_candidate(
                        task.candidate_id or "", "inference_error", error=str(error)
                    )
                    self.audit.record(
                        "inference_failed", task.candidate_id, error=str(error)
                    )
                with self._lock:
                    self._metrics["inference_errors"] += 1
                    self._metrics["last_error"] = str(error)
            finally:
                with self._lock:
                    self._metrics["semantic_state"] = "waiting_for_latest_window"
                    self._metrics.pop("active_task_id", None)
                    self._metrics.pop("active_task_kind", None)
                if cooldown > 0:
                    self.stop_event.wait(cooldown)

    def _consider_algorithm_recommendation(self, result: dict[str, Any]) -> None:
        """Require repeated, high-confidence visual evidence before changing FPGA mode."""
        if not self.algorithm_config.get("enabled", True):
            return
        recommendation = result.get("fpga_recommendation")
        if not isinstance(recommendation, dict):
            self.algorithm_consensus_mode = None
            self.algorithm_consensus_count = 0
            return
        mode = str(recommendation.get("mode", "none")).strip().lower()
        confidence = _number(recommendation.get("confidence"), 0.0)
        minimum = float(self.algorithm_config.get("minimum_confidence", 0.88))
        confirmations = max(1, int(self.algorithm_config.get("confirmations", 2)))
        reason = str(recommendation.get("reason", ""))[:160]
        if mode not in MODE_VALUES or confidence < minimum:
            self.algorithm_consensus_mode = None
            self.algorithm_consensus_count = 0
            with self._lock:
                self._metrics["algorithm_auto_state"] = "no_confident_change"
                self._metrics["algorithm_auto_last_decision"] = {
                    "mode": mode,
                    "confidence": confidence,
                    "reason": reason,
                }
            return

        with self._lock:
            current_mode = int(self._latest_frame_meta.get("fpga_algorithm", 0))
        if MODE_VALUES[mode] == current_mode:
            self.algorithm_consensus_mode = None
            self.algorithm_consensus_count = 0
            with self._lock:
                self._metrics["algorithm_auto_state"] = "current_mode_is_suitable"
                self._metrics["algorithm_auto_last_decision"] = {
                    "mode": mode,
                    "confidence": confidence,
                    "reason": reason,
                }
            return

        if mode == self.algorithm_consensus_mode:
            self.algorithm_consensus_count += 1
        else:
            self.algorithm_consensus_mode = mode
            self.algorithm_consensus_count = 1
        if self.algorithm_consensus_count < confirmations:
            with self._lock:
                self._metrics["algorithm_auto_state"] = (
                    f"confirming_{mode}_{self.algorithm_consensus_count}_of_{confirmations}"
                )
                self._metrics["algorithm_auto_last_decision"] = {
                    "mode": mode,
                    "confidence": confidence,
                    "reason": reason,
                }
            return

        cooldown = float(self.algorithm_config.get("cooldown_seconds", 45.0))
        if time.monotonic() - self.algorithm_last_change < cooldown:
            with self._lock:
                self._metrics["algorithm_auto_state"] = "cooldown"
            return
        command = {
            "mode": mode,
            "threshold": max(0, min(255, int(recommendation.get("threshold", 128)))),
            "confidence": confidence,
            "reason": reason,
        }
        try:
            self.algorithm_queue.put_nowait(command)
            self.algorithm_consensus_mode = None
            self.algorithm_consensus_count = 0
            with self._lock:
                self._metrics["algorithm_auto_state"] = f"switching_to_{mode}"
                self._metrics["algorithm_auto_last_decision"] = command
        except queue.Full:
            with self._lock:
                self._metrics["algorithm_auto_state"] = "control_queue_busy"

    def _algorithm_control_loop(self) -> None:
        interface = str(
            self.algorithm_config.get("interface")
            or os.environ.get("CAM1_PCAP_INTERFACE")
            or self.config["capture"].get("interface", "")
        )
        controller = FpgaAlgorithmController(interface)
        while not self.stop_event.is_set():
            try:
                command = self.algorithm_queue.get(timeout=0.25)
            except queue.Empty:
                continue
            mode = str(command["mode"])
            try:
                with self._lock:
                    last_meta = dict(self._latest_frame_meta)
                controller.synchronize_sequence(int(last_meta.get("fpga_sequence", 0)))
                request = controller.select(mode, int(command["threshold"]))
                deadline = time.monotonic() + float(
                    self.algorithm_config.get("readback_timeout_seconds", 3.0)
                )
                verified = False
                while not self.stop_event.is_set() and time.monotonic() < deadline:
                    with self._lock:
                        meta = dict(self._latest_frame_meta)
                    if (
                        int(meta.get("fpga_sequence", -1)) == request.sequence
                        and int(meta.get("fpga_algorithm", -1)) == request.mode
                    ):
                        verified = True
                        break
                    self.stop_event.wait(0.05)
                self.algorithm_last_change = time.monotonic()
                with self._lock:
                    self._metrics["algorithm_auto_state"] = (
                        f"applied_{mode}" if verified else f"readback_timeout_{mode}"
                    )
                    self._metrics["algorithm_auto_last_decision"] = {
                        **command,
                        "hardware_verified": verified,
                        "sequence": request.sequence,
                    }
                self.audit.record(
                    "fpga_algorithm_auto_change",
                    mode=mode,
                    confidence=command["confidence"],
                    reason=command["reason"],
                    threshold=command["threshold"],
                    sequence=request.sequence,
                    hardware_verified=verified,
                )
            except Exception as error:
                logging.exception("automatic FPGA algorithm switch failed")
                with self._lock:
                    self._metrics["algorithm_auto_state"] = "switch_failed"
                    self._metrics["algorithm_auto_last_decision"] = {
                        **command,
                        "error": str(error),
                    }

    def status(self) -> dict[str, Any]:
        now = time.monotonic()
        with self._lock:
            fps_times = list(self._frame_times)
            if len(fps_times) >= 2:
                acquisition_fps = (len(fps_times) - 1) / max(
                    fps_times[-1] - fps_times[0], 0.001
                )
            else:
                acquisition_fps = 0.0
            payload = {
                "running": not self.stop_event.is_set(),
                "service_behavior_version": 12,
                "service_instance_id": self.instance_id,
                "process_id": os.getpid(),
                "source": "CAM1 FPGA via SFP1/X520-DA2",
                "acquisition_fps": round(acquisition_fps, 2),
                "semantic_update_frequency": (
                    f"scene refresh every {self.config['analysis']['interval_seconds']}s; "
                    "motion candidates use an independent priority queue"
                ),
                "pending_windows": 1 if self.slot._task is not None else 0,
                "replaced_stale_windows": self.slot.replaced,
                "latest_frame": dict(self._latest_frame_meta),
                "capture_status": dict(self._capture_status),
                **self._metrics,
            }
        payload["buffer"] = self.buffer.metrics()
        payload["event_queue"] = self.event_queue.metrics()
        payload["memory"] = self.memory.stats()
        timing_samples = list(self._event_timing_samples)
        payload["event_latency"] = self._timing_summary(timing_samples)
        payload["active_motion_candidate"] = (
            self.motion_detector.active.to_dict()
            if self.motion_detector.active is not None
            else None
        )
        payload["current_scene"] = self.memory.current_scene()
        return payload

    @staticmethod
    def _timing_summary(samples: list[dict[str, float]]) -> dict[str, Any]:
        fields = (
            "candidate_capture_seconds",
            "queue_wait_seconds",
            "inference_seconds",
            "parse_and_persist_seconds",
            "event_report_delay_seconds",
        )
        result: dict[str, Any] = {"sample_count": len(samples)}
        for field in fields:
            values = sorted(
                float(item[field]) for item in samples if field in item
            )
            if not values:
                continue
            p95_index = max(0, min(len(values) - 1, int(np.ceil(len(values) * 0.95)) - 1))
            result[field] = {
                "mean": round(float(np.mean(values)), 3),
                "p95": round(values[p95_index], 3),
            }
        return result


class ApiHandler(BaseHTTPRequestHandler):
    engine: ContinuousPerception
    server_version = "CAM1ContinuousPerception/1.0"

    def log_message(self, _format: str, *_args: object) -> None:
        return

    def _json(self, value: Any, status: int = 200) -> None:
        data = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    @staticmethod
    def _float(query: dict[str, list[str]], name: str, default: float) -> float:
        try:
            return float(query.get(name, [str(default)])[0])
        except ValueError:
            return default

    @staticmethod
    def _int(query: dict[str, list[str]], name: str, default: int) -> int:
        try:
            return int(query.get(name, [str(default)])[0])
        except ValueError:
            return default

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        if parsed.path == "/health":
            self._json(
                {
                    "ok": True,
                    "service": "continuous-video-perception",
                    "service_instance_id": self.engine.instance_id,
                    "process_id": os.getpid(),
                    "config_path": getattr(self.engine, "config_path", None),
                    "memory": self.engine.memory.stats(),
                    "server_time": iso_time(),
                    "server_epoch": time.time(),
                }
            )
        elif parsed.path == "/status":
            status = self.engine.status()
            status["config_path"] = getattr(self.engine, "config_path", None)
            self._json(status)
        elif parsed.path == "/scene":
            scene = self.engine.memory.current_scene()
            frame_epoch = float(scene.get("frame_time_end_epoch", 0.0))
            self._json(
                {
                    "scene": scene,
                    "scene_age_seconds": round(max(0.0, time.time() - frame_epoch), 3)
                    if frame_epoch
                    else None,
                    "service_instance_id": self.engine.instance_id,
                    "memory": self.engine.memory.stats(),
                    "query_time": iso_time(),
                }
            )
        elif parsed.path == "/events":
            seconds = self._float(query, "seconds", 60.0)
            limit = self._int(query, "limit", 20)
            include_pending = query.get("include_pending", ["false"])[0].lower() in {
                "1", "true", "yes"
            }
            self._json(
                {
                    "seconds": seconds,
                    "include_pending": include_pending,
                    "query_time": iso_time(),
                    "service_instance_id": self.engine.instance_id,
                    "memory": self.engine.memory.stats(),
                    "events": self.engine.memory.recent_events(
                        seconds, limit, include_pending=include_pending
                    ),
                }
            )
        elif parsed.path == "/candidates":
            seconds = self._float(query, "seconds", 120.0)
            limit = self._int(query, "limit", 50)
            self._json(
                {
                    "seconds": seconds,
                    "candidates": self.engine.memory.recent_candidates(seconds, limit),
                }
            )
        elif parsed.path == "/event-audit":
            limit = self._int(query, "limit", 100)
            candidate_id = query.get("candidate_id", [None])[0]
            self._json(
                {
                    "candidate_id": candidate_id,
                    "entries": self.engine.audit.recent(limit, candidate_id),
                }
            )
        elif parsed.path == "/understandings":
            seconds = self._float(query, "seconds", 10.0)
            limit = self._int(query, "limit", 10)
            self._json(
                {
                    "seconds": seconds,
                    "understandings": self.engine.memory.recent_understandings(
                        seconds, limit
                    ),
                }
            )
        elif parsed.path == "/search":
            seconds = self._float(query, "seconds", 600.0)
            limit = self._int(query, "limit", 30)
            question = query.get("q", [""])[0]
            self._json(self.engine.memory.search(question, seconds, limit))
        elif parsed.path == "/frame.jpg":
            with self.engine._lock:
                preview_jpeg = self.engine._latest_preview_jpeg
                preview_timestamp = self.engine._latest_preview_timestamp
                preview_frame_id = self.engine._latest_preview_frame_id
            if preview_jpeg is not None:
                jpeg = preview_jpeg
                timestamp = preview_timestamp
            else:
                # Fallback for older receiver records that contain decoded frames.
                frame = self.engine.buffer.latest()
                if frame is None:
                    self._json({"error": "no video frame available yet"}, 503)
                    return
                jpeg = frame.jpeg
                timestamp = frame.timestamp
                preview_frame_id = frame.frame_id
            if not jpeg:
                self._json({"error": "no video frame available yet"}, 503)
                return
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self.send_header("X-CAM1-Frame-Time", timestamp)
            self.send_header("X-CAM1-Frame-ID", str(preview_frame_id))
            self.send_header("Content-Length", str(len(jpeg)))
            self.end_headers()
            self.wfile.write(jpeg)
        else:
            self._json({"error": "not found"}, 404)


def configure_logging() -> None:
    log_dir = ROOT / "runtime"
    log_dir.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        filename=log_dir / "continuous_perception.log",
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(threadName)s %(message)s",
        encoding="utf-8",
    )


def main() -> int:
    configure_logging()
    config_path = Path(os.environ.get("CAM1_PERCEPTION_CONFIG", ROOT / "continuous_perception_config.json"))
    config = load_config(config_path)
    if os.environ.get("CAM1_PCAP_INTERFACE"):
        config["capture"]["interface"] = os.environ["CAM1_PCAP_INTERFACE"]
    if os.environ.get("QWEN3VL_API_BASE"):
        config["model"]["base_url"] = os.environ["QWEN3VL_API_BASE"].rstrip("/")
    if os.environ.get("MODEL_NAME"):
        config["model"]["name"] = os.environ["MODEL_NAME"]
    ApiHandler.engine = ContinuousPerception(config)
    ApiHandler.engine.config_path = str(config_path.resolve())
    host = str(config["api"]["host"])
    port = int(config["api"]["port"])
    try:
        server = ThreadingHTTPServer((host, port), ApiHandler)
    except OSError as error:
        logging.info("service not started because API address is already in use: %s", error)
        return 0
    ApiHandler.engine.start()
    (ROOT / "runtime").mkdir(exist_ok=True)
    (ROOT / "runtime" / "continuous_perception.pid").write_text(
        str(os.getpid()), encoding="ascii"
    )
    logging.info("continuous perception started on http://%s:%d", host, port)
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        ApiHandler.engine.stop()
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
