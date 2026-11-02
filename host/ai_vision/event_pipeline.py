"""Motion-candidate state machine and bounded priority queue for CAM1 events."""

from __future__ import annotations

from dataclasses import asdict, dataclass
import heapq
import json
from pathlib import Path
import threading
import time
from typing import Any, Callable
from collections import deque


@dataclass
class MotionCandidate:
    candidate_id: str
    onset_epoch: float
    onset_time: str
    last_motion_epoch: float
    last_motion_time: str
    peak_epoch: float
    peak_time: str
    peak_score: float
    peak_motion_ratio: float
    peak_local_ratio: float
    sample_count: int
    status: str = "collecting"
    finalized_epoch: float | None = None
    finalized_time: str | None = None
    motion_end_epoch: float | None = None
    motion_end_time: str | None = None
    finalization_reason: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class EventAuditLogger:
    """Append-only JSONL record of every stage in an event candidate's life."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()

    def record(self, stage: str, candidate_id: str | None = None, **data: Any) -> None:
        entry = {
            "audit_epoch": time.time(),
            "audit_time": _iso_time(),
            "stage": stage,
            "candidate_id": candidate_id,
            **data,
        }
        line = json.dumps(entry, ensure_ascii=False, default=str) + "\n"
        with self._lock:
            with self.path.open("a", encoding="utf-8") as handle:
                handle.write(line)

    def recent(self, limit: int = 100, candidate_id: str | None = None) -> list[dict[str, Any]]:
        """Read recent audit entries for diagnostics without keeping them in memory."""
        if not self.path.exists():
            return []
        with self._lock:
            with self.path.open("r", encoding="utf-8") as handle:
                lines = deque(handle, maxlen=max(1, min(limit * 4, 4000)))
        values: list[dict[str, Any]] = []
        for line in lines:
            try:
                item = json.loads(line)
            except ValueError:
                continue
            if candidate_id and item.get("candidate_id") != candidate_id:
                continue
            values.append(item)
        return values[-max(1, limit) :]


def _iso_time(epoch: float | None = None) -> str:
    from datetime import datetime

    value = time.time() if epoch is None else epoch
    return datetime.fromtimestamp(value).astimezone().isoformat(timespec="milliseconds")


class MotionEventDetector:
    """Hysteretic local-motion detector that proposes, but never names, actions."""

    def __init__(
        self,
        config: dict[str, Any],
        on_finalized: Callable[[MotionCandidate], None],
        audit: EventAuditLogger,
    ) -> None:
        self.start_ratio = float(config["start_motion_ratio"])
        self.start_local = float(config["start_local_ratio"])
        self.continue_ratio = float(config["continue_motion_ratio"])
        self.continue_local = float(config["continue_local_ratio"])
        self.start_samples = int(config["start_consecutive_samples"])
        self.post_seconds = float(config["post_seconds"])
        self.min_duration = float(config["minimum_duration_seconds"])
        self.max_duration = float(config["maximum_duration_seconds"])
        self.cooldown_seconds = float(config["cooldown_seconds"])
        self.baseline_alpha = float(config.get("baseline_alpha", 0.02))
        self.start_baseline_multiplier = float(
            config.get("start_baseline_multiplier", 1.8)
        )
        self.start_baseline_margin = float(config.get("start_baseline_margin", 0.002))
        self.continue_baseline_multiplier = float(
            config.get("continue_baseline_multiplier", 1.25)
        )
        self.continue_baseline_margin = float(
            config.get("continue_baseline_margin", 0.001)
        )
        self.warmup_samples = int(config.get("warmup_samples", 12))
        self.on_finalized = on_finalized
        self.audit = audit
        self.active: MotionCandidate | None = None
        self._start_streak = 0
        self._candidate_counter = 0
        self._cooldown_until = 0.0
        self._baseline_ratio = 0.0
        self._baseline_local = 0.0
        self._baseline_samples = 0

    @staticmethod
    def score(motion_ratio: float, local_ratio: float) -> float:
        # Both terms are fractions in [0, 1]. Localized hand/object motion should
        # remain visible even when global mean difference is tiny.
        return max(motion_ratio * 5.0, local_ratio)

    def observe(self, frame: Any) -> None:
        epoch = float(frame.timestamp_epoch)
        ratio = float(frame.motion_ratio)
        local = float(frame.motion_local_ratio)
        dynamic_start_ratio = max(
            self.start_ratio,
            self._baseline_ratio * self.start_baseline_multiplier
            + self.start_baseline_margin,
        )
        dynamic_start_local = max(
            self.start_local,
            self._baseline_local * self.start_baseline_multiplier
            + self.start_baseline_margin,
        )
        dynamic_continue_ratio = max(
            self.continue_ratio,
            self._baseline_ratio * self.continue_baseline_multiplier
            + self.continue_baseline_margin,
        )
        dynamic_continue_local = max(
            self.continue_local,
            self._baseline_local * self.continue_baseline_multiplier
            + self.continue_baseline_margin,
        )
        warmed_up = self._baseline_samples >= self.warmup_samples
        start_signal = warmed_up and (
            ratio >= dynamic_start_ratio or local >= dynamic_start_local
        )
        continue_signal = (
            ratio >= dynamic_continue_ratio or local >= dynamic_continue_local
        )
        # Learn only quiet background. A possible action must not raise its own
        # threshold while waiting for the required consecutive start samples.
        if self.active is None and (not warmed_up or (not start_signal and self._start_streak == 0)):
            if self._baseline_samples == 0:
                self._baseline_ratio = ratio
                self._baseline_local = local
            else:
                alpha = self.baseline_alpha
                self._baseline_ratio = (1.0 - alpha) * self._baseline_ratio + alpha * ratio
                self._baseline_local = (1.0 - alpha) * self._baseline_local + alpha * local
            self._baseline_samples += 1
        score = self.score(ratio, local)

        if self.active is None:
            if epoch < self._cooldown_until:
                return
            self._start_streak = self._start_streak + 1 if start_signal else 0
            if self._start_streak < self.start_samples:
                return
            self._candidate_counter += 1
            candidate_id = f"motion-{int(epoch * 1000)}-{self._candidate_counter}"
            self.active = MotionCandidate(
                candidate_id=candidate_id,
                onset_epoch=epoch,
                onset_time=frame.timestamp,
                last_motion_epoch=epoch,
                last_motion_time=frame.timestamp,
                peak_epoch=epoch,
                peak_time=frame.timestamp,
                peak_score=score,
                peak_motion_ratio=ratio,
                peak_local_ratio=local,
                sample_count=self._start_streak,
            )
            self._start_streak = 0
            self.audit.record(
                "motion_trigger",
                candidate_id,
                onset_time=frame.timestamp,
                frame_id=frame.frame_id,
                motion_ratio=round(ratio, 6),
                local_motion_ratio=round(local, 6),
                score=round(score, 6),
                baseline_motion_ratio=round(self._baseline_ratio, 6),
                baseline_local_ratio=round(self._baseline_local, 6),
                start_motion_threshold=round(dynamic_start_ratio, 6),
                start_local_threshold=round(dynamic_start_local, 6),
                continue_motion_threshold=round(dynamic_continue_ratio, 6),
                continue_local_threshold=round(dynamic_continue_local, 6),
            )
            return

        candidate = self.active
        candidate.sample_count += 1
        duration = epoch - candidate.onset_epoch
        if candidate.status == "collecting":
            if continue_signal:
                candidate.last_motion_epoch = epoch
                candidate.last_motion_time = frame.timestamp
            if score > candidate.peak_score:
                candidate.peak_score = score
                candidate.peak_epoch = epoch
                candidate.peak_time = frame.timestamp
                candidate.peak_motion_ratio = ratio
                candidate.peak_local_ratio = local
            quiet = epoch - candidate.last_motion_epoch
            if duration >= self.max_duration:
                # Freeze the semantic motion end, then deliberately keep sampling
                # for a short post-action view. This avoids a 7 s window whose last
                # frame is still labelled as motion and reduces report latency.
                candidate.status = "post_capture"
                candidate.motion_end_epoch = epoch
                candidate.motion_end_time = frame.timestamp
                candidate.last_motion_epoch = epoch
                candidate.last_motion_time = frame.timestamp
                candidate.finalization_reason = "maximum_duration"
                self.audit.record(
                    "post_action_capture_started",
                    candidate.candidate_id,
                    motion_end_time=frame.timestamp,
                    duration_seconds=round(duration, 3),
                )
                return
            if not (duration >= self.min_duration and quiet >= self.post_seconds):
                return
            candidate.motion_end_epoch = candidate.last_motion_epoch
            candidate.motion_end_time = candidate.last_motion_time
            candidate.finalization_reason = "motion_settled"
        else:
            quiet = epoch - float(candidate.motion_end_epoch or epoch)
            if quiet < self.post_seconds:
                return

        candidate.status = "frames_ready"
        candidate.finalized_epoch = epoch
        candidate.finalized_time = frame.timestamp
        self.active = None
        self._cooldown_until = epoch + self.cooldown_seconds
        self.audit.record(
            "motion_candidate_finalized",
            candidate.candidate_id,
            onset_time=candidate.onset_time,
            last_motion_time=candidate.last_motion_time,
            finalized_time=candidate.finalized_time,
            duration_seconds=round(duration, 3),
            quiet_seconds=round(quiet, 3),
            peak_score=round(candidate.peak_score, 6),
            reason=candidate.finalization_reason,
        )
        self.on_finalized(candidate)


class BoundedPriorityEventQueue:
    """Bounded event queue that keeps the newest pending observation."""

    def __init__(self, capacity: int) -> None:
        self.capacity = max(1, capacity)
        self._heap: list[tuple[float, int, Any]] = []
        self._condition = threading.Condition()
        self._sequence = 0
        self._closed = False
        self.rejected = 0
        self.evicted = 0

    def put(self, task: Any, priority: float) -> tuple[bool, Any | None, str]:
        """Return accepted, displaced task, and decision reason."""
        with self._condition:
            self._sequence += 1
            item = (float(priority), self._sequence, task)
            if len(self._heap) < self.capacity:
                heapq.heappush(self._heap, item)
                self._condition.notify()
                return True, None, "capacity_available"
            # Once inference is slower than motion arrivals, processing old
            # candidates makes the live UI lag further behind every second.
            oldest = min(range(len(self._heap)), key=lambda i: self._heap[i][1])
            displaced = self._heap[oldest][2]
            self._heap[oldest] = item
            heapq.heapify(self._heap)
            self.evicted += 1
            self._condition.notify()
            return True, displaced, "replaced_oldest_pending_event"

    def get_nowait(self) -> Any | None:
        with self._condition:
            if not self._heap:
                return None
            # With capacity one the only pending event is always the latest.
            index = min(range(len(self._heap)), key=lambda i: self._heap[i][1])
            _, _, task = self._heap[index]
            self._heap[index] = self._heap[-1]
            self._heap.pop()
            if self._heap:
                heapq.heapify(self._heap)
            return task

    def close(self) -> None:
        with self._condition:
            self._closed = True
            self._condition.notify_all()

    def metrics(self) -> dict[str, Any]:
        with self._condition:
            oldest_age = 0.0
            if self._heap:
                submitted = getattr(
                    min(self._heap, key=lambda item: item[1])[2],
                    "submitted_epoch",
                    time.time(),
                )
                oldest_age = max(0.0, time.time() - float(submitted))
            return {
                "capacity": self.capacity,
                "pending": len(self._heap),
                "rejected": self.rejected,
                "evicted": self.evicted,
                "oldest_age_seconds": round(oldest_age, 3),
            }
