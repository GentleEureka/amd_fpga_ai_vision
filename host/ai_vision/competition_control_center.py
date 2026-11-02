#!/usr/bin/env python3
"""Single-window control center for the CAM1 1080p continuous vision system."""

from __future__ import annotations

import ctypes
from ctypes import wintypes
import io
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
from datetime import datetime, timedelta, timezone
import tkinter as tk
from tkinter import scrolledtext, ttk
from urllib.parse import urlsplit
from urllib.request import urlopen

from PIL import Image, ImageTk

import continuous_perception_client as vision


ROOT = Path(__file__).resolve().parent
PROJECT_ROOT = ROOT.parent.parent
CAMERA_VIEWER_DIR = ROOT.parent / "camera_viewer"
if str(CAMERA_VIEWER_DIR) not in sys.path:
    sys.path.insert(0, str(CAMERA_VIEWER_DIR))

from fpga_algorithm_control import FpgaAlgorithmController, MODE_NAMES


def _load_local_environment() -> None:
    """Load the installer-generated settings without showing a cmd window."""
    path = PROJECT_ROOT / "installation.json"
    if not path.exists():
        return
    try:
        settings = json.loads(path.read_text(encoding="utf-8-sig"))
        for key, value in settings.items():
            if value is not None:
                os.environ.setdefault(str(key), str(value))
    except Exception:
        return


_load_local_environment()
PYTHON = ROOT / ".venv" / "Scripts" / "python.exe"
PYTHONW = ROOT / ".venv" / "Scripts" / "pythonw.exe"
LOCAL_APPDATA = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
HERMES = Path(os.environ.get("HERMES_EXE", LOCAL_APPDATA / "Hermes" / "bin" / "hermes.exe"))
HERMES_STATE = Path(os.environ.get("HERMES_STATE", LOCAL_APPDATA / "Hermes" / "gateway_state.json"))
MODEL_MODE = os.environ.get("MODEL_MODE", "external").lower()
MODEL_SERVER_URL = os.environ.get("MODEL_SERVER_URL", "http://127.0.0.1:8081").rstrip("/")
try:
    MODEL_SERVER_PORT = int(
        os.environ.get("MODEL_SERVER_PORT", "")
        or urlsplit(MODEL_SERVER_URL).port
        or 8081
    )
except (TypeError, ValueError):
    MODEL_SERVER_PORT = 8081
MODEL_HEALTH_URL = MODEL_SERVER_URL + "/health"
ACTIVE_CONFIG = ROOT / "runtime" / "active_demo_config.txt"
VIDEO_REFRESH_MS = 50

CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
BEIJING_TZ = timezone(timedelta(hours=8))


def _beijing_event_time(item: dict[str, object]) -> str:
    value = item.get("occurred_at") or item.get("timestamp") or item.get("occurred_at_epoch")
    try:
        if isinstance(value, (int, float)):
            moment = datetime.fromtimestamp(float(value), BEIJING_TZ)
        else:
            moment = datetime.fromisoformat(str(value))
            moment = (
                moment.replace(tzinfo=BEIJING_TZ)
                if moment.tzinfo is None
                else moment.astimezone(BEIJING_TZ)
            )
        return moment.strftime("%Y-%m-%d %H:%M:%S")
    except (TypeError, ValueError, OverflowError):
        return str(value or "时间未知")
DETACHED_PROCESS = getattr(subprocess, "DETACHED_PROCESS", 0)
_INSTANCE_MUTEX = None


def ensure_single_instance() -> bool:
    """Return False and focus the existing control center when already open."""
    global _INSTANCE_MUTEX
    if os.name != "nt":
        return True
    kernel32 = ctypes.windll.kernel32
    _INSTANCE_MUTEX = kernel32.CreateMutexW(None, False, "Local\\CAM1CompetitionControlCenter")
    if kernel32.GetLastError() != 183:
        return True
    user32 = ctypes.windll.user32
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    def callback(hwnd: int, _lparam: int) -> bool:
        length = user32.GetWindowTextLengthW(hwnd)
        if not length:
            return True
        buffer = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, buffer, length + 1)
        if buffer.value in {"CAM1 FPGA 连续视觉总控", "CAM1 FPGA + AI 比赛总控"}:
            user32.ShowWindow(hwnd, 9)
            user32.SetForegroundWindow(hwnd)
            return False
        return True

    user32.EnumWindows(callback_type(callback), 0)
    return False


def _hidden_popen(command: list[str], **kwargs: object) -> subprocess.Popen[str]:
    return subprocess.Popen(
        command,
        creationflags=CREATE_NO_WINDOW,
        **kwargs,
    )


def _http_ok(url: str, timeout: float = 0.6) -> bool:
    try:
        with urlopen(url, timeout=timeout) as response:
            return 200 <= response.status < 300
    except Exception:
        return False


def _pid_running(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        handle = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)
        if not handle:
            return False
        ctypes.windll.kernel32.CloseHandle(handle)
        return True
    except Exception:
        return False


def _hermes_running() -> bool:
    try:
        state = json.loads(HERMES_STATE.read_text(encoding="utf-8"))
        return state.get("gateway_state") == "running" and _pid_running(int(state["pid"]))
    except Exception:
        return False


def _active_config() -> str | None:
    try:
        value = ACTIVE_CONFIG.read_text(encoding="utf-8-sig").strip()
        if not value or not Path(value).exists():
            return None
        active_path = Path(value)
        if not active_path.resolve().is_relative_to(ROOT.resolve()):
            return None
        active = json.loads(active_path.read_text(encoding="utf-8-sig"))
        defaults = json.loads(
            (ROOT / "continuous_perception_config.json").read_text(encoding="utf-8-sig")
        )
        active_analysis = active.setdefault("analysis", {})
        default_analysis = defaults.get("analysis", {})
        # Keep the isolated session's memory/audit paths, while applying the
        # current latency settings when an existing session is resumed.
        for key in ("interval_seconds", "scene_image_width", "image_width"):
            if key in default_analysis:
                active_analysis[key] = default_analysis[key]
        for section, keys in (
            ("capture", ("buffer_fps",)),
            ("motion", ("pre_seconds", "post_seconds", "maximum_duration_seconds", "cooldown_seconds")),
        ):
            active_section = active.setdefault(section, {})
            default_section = defaults.get(section, {})
            for key in keys:
                if key in default_section:
                    active_section[key] = default_section[key]
        active_events = active.setdefault("events", {})
        default_events = defaults.get("events", {})
        for key in ("frame_count", "queue_capacity"):
            if key in default_events:
                active_events[key] = default_events[key]
        active_path.write_text(
            json.dumps(active, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        return str(active_path)
    except OSError:
        return None
    except (ValueError, TypeError):
        return None


def _window_titles() -> list[str]:
    titles: list[str] = []
    user32 = ctypes.windll.user32
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    def callback(hwnd: int, _lparam: int) -> bool:
        if not user32.IsWindowVisible(hwnd):
            return True
        length = user32.GetWindowTextLengthW(hwnd)
        if length:
            buffer = ctypes.create_unicode_buffer(length + 1)
            user32.GetWindowTextW(hwnd, buffer, length + 1)
            titles.append(buffer.value)
        return True

    user32.EnumWindows(callback_type(callback), 0)
    return titles


def hide_service_consoles() -> int:
    patterns = (
        "Qwen3-VL",
        "Hermes Gateway",
        "CAM1 Final Acceptance LIVE",
        "CAM1 Competition Perception",
        "CAM1 Competition Monitor",
        "CAM1 Continuous Perception",
        "CAM1 Continuous Vision Monitor",
    )
    hidden = 0
    user32 = ctypes.windll.user32
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    def callback(hwnd: int, _lparam: int) -> bool:
        nonlocal hidden
        length = user32.GetWindowTextLengthW(hwnd)
        if not length:
            return True
        buffer = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, buffer, length + 1)
        if any(pattern in buffer.value for pattern in patterns):
            user32.ShowWindow(hwnd, 0)
            hidden += 1
        return True

    user32.EnumWindows(callback_type(callback), 0)
    return hidden


def close_external_viewer_windows() -> int:
    """Close the old standalone viewer now that video is embedded here."""
    closed = 0
    user32 = ctypes.windll.user32
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    def callback(hwnd: int, _lparam: int) -> bool:
        nonlocal closed
        length = user32.GetWindowTextLengthW(hwnd)
        if not length:
            return True
        buffer = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, buffer, length + 1)
        if "CAM1 Live - Ethernet" in buffer.value:
            user32.PostMessageW(hwnd, 0x0010, 0, 0)  # WM_CLOSE
            closed += 1
        return True

    user32.EnumWindows(callback_type(callback), 0)
    return closed


class ControlCenter:
    def __init__(self) -> None:
        self.root = tk.Tk()
        self.root.title("CAM1 FPGA 连续视觉总控")
        self.root.geometry("1600x1000")
        self.root.state("zoomed")
        self.root.minsize(1280, 820)
        self.root.configure(bg="#10151c")

        self.messages: queue.Queue[tuple[str, object]] = queue.Queue()
        self.refresh_busy = False
        self.video_busy = False
        self.video_photo: ImageTk.PhotoImage | None = None
        self.latest_video_image: Image.Image | None = None
        self.preview_lock = threading.Lock()
        self.preview_pending: Image.Image | None = None
        self.preview_target_size = (960, 540)
        self.last_video_error = ""
        self.last_event_signature = ""
        self.chat_busy = False
        self.algorithm_command_busy = False
        self.algorithm_buttons: dict[int, tk.Button] = {}
        self.algorithm_status = tk.StringVar(value="等待硬件回读")
        self.gpu_snapshot = "读取中"
        self.last_gpu_query = 0.0

        self._configure_style()
        self._build_ui()
        hide_service_consoles()
        closed = close_external_viewer_windows()
        self._log("连续视觉总控已启动；所有后台服务均静默运行。", "ok")
        if closed:
            self._log(f"已关闭 {closed} 个旧的独立实时画面窗口。", "ok")
        self.root.after(30, self._poll_messages)
        self.root.after(150, self._schedule_refresh)
        self.root.after(200, self._schedule_video_refresh)
        self.root.after(300, self.start_services)

    def _configure_style(self) -> None:
        style = ttk.Style()
        style.theme_use("clam")
        style.configure("TFrame", background="#10151c")
        style.configure("Card.TFrame", background="#18212b")
        style.configure("TLabel", background="#10151c", foreground="#e6edf3", font=("Microsoft YaHei UI", 10))
        style.configure("Title.TLabel", font=("Microsoft YaHei UI", 20, "bold"), foreground="#f0f6fc")
        style.configure("Sub.TLabel", foreground="#8b949e")
        style.configure("CardTitle.TLabel", background="#18212b", foreground="#8b949e", font=("Microsoft YaHei UI", 9))
        style.configure("CardValue.TLabel", background="#18212b", foreground="#58d6a8", font=("Microsoft YaHei UI", 13, "bold"))
        style.configure("Action.TButton", font=("Microsoft YaHei UI", 10, "bold"), padding=(14, 9))

    def _build_ui(self) -> None:
        top = ttk.Frame(self.root)
        top.pack(fill="x", padx=24, pady=(20, 12))
        ttk.Label(top, text="CAM1 FPGA 连续视觉总控", style="Title.TLabel").pack(side="left")
        self.overall = tk.StringVar(value="正在读取系统状态…")
        self.overall_box = tk.Frame(top, bg="#10151c")
        self.overall_box.pack(side="right", pady=8)
        self.overall_dot = tk.Canvas(
            self.overall_box, width=12, height=12, bg="#10151c", highlightthickness=0
        )
        self.overall_dot.pack(side="left", padx=(0, 7))
        self.overall_dot_id = self.overall_dot.create_oval(
            2, 2, 10, 10, fill="#8b949e", outline=""
        )
        self.overall_label = tk.Label(
            self.overall_box,
            textvariable=self.overall,
            bg="#10151c",
            fg="#8b949e",
            font=("Microsoft YaHei UI", 10),
        )
        self.overall_label.pack(side="left")

        toolbar = ttk.Frame(self.root)
        toolbar.pack(fill="x", padx=24, pady=(0, 12))
        ttk.Button(toolbar, text="自动修复服务", command=self.start_services).pack(side="left", padx=(0, 8))
        ttk.Button(toolbar, text="新建感知会话", command=self.new_demo_session).pack(side="left", padx=8)
        algorithm_controls = ttk.Frame(toolbar)
        algorithm_controls.pack(side="left", padx=(20, 8))
        ttk.Label(algorithm_controls, text="图像模式", style="Sub.TLabel").pack(
            side="left", padx=(0, 6)
        )
        for algorithm_id, algorithm_name, mode in (
            (0, "彩色", "color"),
            (1, "灰度", "gray"),
            (2, "黑白", "binary"),
            (3, "负片", "invert"),
        ):
            button = tk.Button(
                algorithm_controls,
                text=algorithm_name,
                state="normal",
                relief="flat",
                padx=8,
                pady=4,
                bg="#27313b",
                fg="#e6edf3",
                activebackground="#315443",
                activeforeground="#ffffff",
                borderwidth=0,
                command=lambda selected_mode=mode: self.select_fpga_algorithm(selected_mode),
            )
            button.pack(side="left", padx=2)
            self.algorithm_buttons[algorithm_id] = button
        ttk.Label(
            algorithm_controls,
            text="OV5640 传感器图像模式 ·",
            style="Sub.TLabel",
        ).pack(side="left", padx=(7, 0))
        ttk.Label(algorithm_controls, textvariable=self.algorithm_status, style="Sub.TLabel").pack(side="left")
        ttk.Label(
            toolbar,
            text=f"后台：Qwen3-VL 端口 {MODEL_SERVER_PORT} + 持续感知 + Hermes MCP（静默托管）",
            style="Sub.TLabel",
        ).pack(side="right")

        content = ttk.Frame(self.root)
        content.pack(fill="both", expand=True, padx=24, pady=(0, 18))
        content.columnconfigure(0, weight=13, uniform="columns")
        content.columnconfigure(1, weight=7, uniform="columns")
        content.rowconfigure(0, weight=2, uniform="rows")
        content.rowconfigure(1, weight=1, uniform="rows")

        video = ttk.Frame(content, style="Card.TFrame", padding=12)
        video.grid(row=0, column=0, sticky="nsew", padx=(0, 8), pady=(0, 8))
        video.columnconfigure(0, weight=1)
        video.rowconfigure(1, weight=1)

        video_header = ttk.Frame(video, style="Card.TFrame")
        video_header.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        ttk.Label(video_header, text="FPGA 实时视频画面", style="CardValue.TLabel").pack(side="left")
        self.video_status = tk.StringVar(value="正在连接持续感知视频源…")
        ttk.Label(video_header, textvariable=self.video_status, style="CardTitle.TLabel").pack(side="right")
        self.video_label = tk.Label(
            video,
            text="等待 FPGA 视频帧…",
            bg="#05080c",
            fg="#8b949e",
            font=("Microsoft YaHei UI", 12),
            relief="flat",
        )
        self.video_label.grid(row=1, column=0, sticky="nsew")

        left = ttk.Frame(content, style="Card.TFrame", padding=14)
        left.grid(row=1, column=0, sticky="nsew", padx=(0, 8), pady=(8, 0))
        performance = ttk.Frame(content, style="Card.TFrame", padding=16)
        performance.grid(row=0, column=1, sticky="nsew", padx=(8, 0), pady=(0, 8))
        chat = ttk.Frame(content, style="Card.TFrame", padding=14)
        chat.grid(row=1, column=1, sticky="nsew", padx=(8, 0), pady=(8, 0))

        ttk.Label(left, text="当前场景与最近事件", style="CardValue.TLabel").pack(anchor="w")
        self.scene_text = tk.StringVar(value="等待场景语义结果…")
        ttk.Label(left, textvariable=self.scene_text, style="CardTitle.TLabel", wraplength=820, justify="left").pack(fill="x", anchor="w", pady=(6, 8))
        self.events = tk.Text(left, height=6, bg="#0d1117", fg="#d6e1ea", insertbackground="white", relief="flat", font=("Microsoft YaHei UI", 9), padx=10, pady=8)
        self.events.pack(fill="both", expand=True)
        self.events.configure(state="disabled")

        ttk.Label(performance, text="实时性能参数", style="CardValue.TLabel").pack(anchor="w")
        self.performance_text = tk.StringVar(value="正在读取视频与 AI 性能…")
        ttk.Label(
            performance,
            textvariable=self.performance_text,
            style="CardTitle.TLabel",
            justify="left",
            anchor="nw",
            font=("Consolas", 10),
        ).pack(fill="x", pady=(10, 8))
        ttk.Label(performance, text="后台状态", style="CardTitle.TLabel").pack(anchor="w")
        self.log = tk.Text(performance, height=6, bg="#0d1117", fg="#c9d1d9", relief="flat", font=("Microsoft YaHei UI", 9), padx=8, pady=8)
        self.log.pack(fill="both", expand=True, pady=(5, 0))
        self.log.tag_configure("ok", foreground="#58d6a8")
        self.log.tag_configure("warn", foreground="#f2cc60")
        self.log.tag_configure("error", foreground="#ff7b72")
        self.log.configure(state="disabled")

        ttk.Label(chat, text="Hermes 场景记忆对话", style="CardValue.TLabel").pack(anchor="w")
        ttk.Label(chat, text="历史问题只查询已保存事件，不会临时截图猜测。", style="CardTitle.TLabel").pack(anchor="w", pady=(2, 6))
        self.chat_history = scrolledtext.ScrolledText(
            chat, height=8, bg="#0d1117", fg="#d6e1ea", insertbackground="white",
            relief="flat", wrap="word", font=("Microsoft YaHei UI", 10), padx=10, pady=8,
        )
        self.chat_history.pack(fill="both", expand=True)
        self.chat_history.insert("end", "系统：可以问“现在看到了什么”或“我刚才拿起了什么”。\n")
        self.chat_history.configure(state="disabled")
        chat_input = ttk.Frame(chat, style="Card.TFrame")
        chat_input.pack(fill="x", pady=(8, 0))
        self.chat_entry = ttk.Entry(chat_input, font=("Microsoft YaHei UI", 10))
        self.chat_entry.pack(side="left", fill="x", expand=True)
        self.chat_entry.bind("<Return>", lambda _event: self.send_chat())
        self.chat_button = ttk.Button(chat_input, text="发送", command=self.send_chat)
        self.chat_button.pack(side="right", padx=(8, 0))

    def _log(self, text: str, tag: str = "") -> None:
        timestamp = time.strftime("%H:%M:%S")
        self.log.configure(state="normal")
        self.log.insert("end", f"[{timestamp}] {text}\n", tag)
        self.log.see("end")
        self.log.configure(state="disabled")

    def _schedule_refresh(self) -> None:
        if not self.refresh_busy:
            self.refresh_busy = True
            threading.Thread(target=self._refresh_worker, daemon=True).start()
        self.root.after(800, self._schedule_refresh)

    def _refresh_worker(self) -> None:
        data: dict[str, object] = {"qwen": _http_ok(MODEL_HEALTH_URL), "hermes": _hermes_running()}
        if time.monotonic() - self.last_gpu_query >= 5.0:
            self.last_gpu_query = time.monotonic()
            try:
                result = subprocess.run(
                    ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total", "--format=csv,noheader,nounits"],
                    capture_output=True, text=True, timeout=2, creationflags=CREATE_NO_WINDOW,
                )
                values = [part.strip() for part in result.stdout.splitlines()[0].split(",")]
                self.gpu_snapshot = f"{values[0]}% · {values[1]}/{values[2]} MiB" if len(values) >= 3 else "不可用"
            except Exception:
                self.gpu_snapshot = "不可用"
        data["gpu"] = self.gpu_snapshot
        try:
            data["status"] = vision.status()
            data["scene"] = vision.scene()
            data["events"] = vision.events(900, 8, include_pending=True)
        except Exception as error:
            data["error"] = str(error)
        self.messages.put(("status", data))
        self.refresh_busy = False

    def _schedule_video_refresh(self) -> None:
        self.preview_target_size = (
            max(480, self.video_label.winfo_width()),
            max(270, self.video_label.winfo_height()),
        )
        if not self.video_busy:
            self.video_busy = True
            threading.Thread(
                target=self._video_worker,
                args=(self.preview_target_size,),
                daemon=True,
            ).start()
        self.root.after(VIDEO_REFRESH_MS, self._schedule_video_refresh)

    def _video_worker(self, target_size: tuple[int, int] | None = None) -> None:
        try:
            payload = vision.get_frame(timeout=1.0)
            target_width, target_height = target_size or self.preview_target_size
            with Image.open(io.BytesIO(payload)) as decoded:
                # Ask libjpeg for a half-resolution decode where supported;
                # keep the source aspect ratio and fit the complete image into
                # the current preview pane without cropping.
                decoded.draft("RGB", (960, 540))
                frame = decoded.convert("RGB")
                scale = min(target_width / frame.width, target_height / frame.height)
                display_size = (
                    max(1, round(frame.width * scale)),
                    max(1, round(frame.height * scale)),
                )
                if display_size != frame.size:
                    frame = frame.resize(display_size, Image.Resampling.BILINEAR)
            with self.preview_lock:
                # Keep only the newest decoded frame; stale previews are discarded.
                self.preview_pending = frame
        except Exception as error:
            self.messages.put(("video_error", str(error)))
        finally:
            self.video_busy = False

    def refresh_embedded_video(self) -> None:
        self.last_video_error = ""
        self.video_status.set("正在刷新…")
        if not self.video_busy:
            self.video_busy = True
            self.preview_target_size = (
                max(480, self.video_label.winfo_width()),
                max(270, self.video_label.winfo_height()),
            )
            threading.Thread(
                target=self._video_worker,
                args=(self.preview_target_size,),
                daemon=True,
            ).start()

    def _poll_messages(self) -> None:
        while True:
            try:
                kind, payload = self.messages.get_nowait()
            except queue.Empty:
                break
            if kind == "status":
                self._apply_status(payload)  # type: ignore[arg-type]
            elif kind == "video_frame":
                self._apply_video_frame(payload)  # type: ignore[arg-type]
            elif kind == "video_error":
                self._apply_video_error(str(payload))
            elif kind == "log":
                text, tag = payload  # type: ignore[misc]
                self._log(str(text), str(tag))
            elif kind == "chat_result":
                self._finish_chat(str(payload))
            elif kind == "algorithm_result":
                self._apply_algorithm_result(payload)  # type: ignore[arg-type]
        with self.preview_lock:
            preview = self.preview_pending
            self.preview_pending = None
        if preview is not None:
            self._apply_video_frame(preview)
        self.root.after(30, self._poll_messages)

    def _apply_video_frame(self, frame: Image.Image) -> None:
        try:
            self.latest_video_image = frame
            self.video_photo = ImageTk.PhotoImage(self.latest_video_image)
            self.video_label.configure(image=self.video_photo, text="")
            self.video_status.set(
                f"源画面 1920×1080 · 等比例完整显示 · {time.strftime('%H:%M:%S')}"
            )
            self.last_video_error = ""
        except Exception as error:
            self._apply_video_error(f"图像解码失败：{error}")

    def _apply_video_error(self, error: str) -> None:
        if error == self.last_video_error:
            return
        self.last_video_error = error
        self.video_status.set("等待视频服务")
        if self.video_photo is None:
            self.video_label.configure(image="", text="视频暂不可用，正在自动重连…")

    def _apply_status(self, data: dict[str, object]) -> None:
        qwen = bool(data.get("qwen"))
        hermes = bool(data.get("hermes"))
        status = data.get("status") if isinstance(data.get("status"), dict) else {}
        fps = float(status.get("acquisition_fps", 0) or 0)  # type: ignore[union-attr]
        latest = status.get("latest_frame") or {}  # type: ignore[union-attr]
        memory = status.get("memory") or {}  # type: ignore[union-attr]
        queue_state = status.get("event_queue") or {}  # type: ignore[union-attr]
        inference = status.get("last_inference_seconds")  # type: ignore[union-attr]
        latency = status.get("event_latency") or {}  # type: ignore[union-attr]
        report_delay = latency.get("event_report_delay_seconds") or {}
        frame_id = latest.get("frame_id", "-")
        width = latest.get("width", "-")
        height = latest.get("height", "-")

        healthy = fps > 0 and qwen and hermes and bool(status)
        if healthy:
            overall_text = "系统正常，可演示"
        elif fps <= 0 or not latest:
            overall_text = "等待 FPGA 视频输入（检查板卡与光链路）"
        else:
            overall_text = "部分服务未就绪"
        self.overall.set(overall_text)
        color = "#2ecc71" if healthy else "#f0a33a"
        self.overall_dot.itemconfigure(self.overall_dot_id, fill=color)
        self.overall_label.configure(fg="#58d6a8" if healthy else "#f0a33a")
        if latest:
            mode = int(latest.get("fpga_algorithm", 0) or 0)
            metadata_valid = bool(latest.get("fpga_metadata_valid"))
            for algorithm_id, button in self.algorithm_buttons.items():
                button.configure(
                    relief="sunken" if metadata_valid and mode == algorithm_id else "flat",
                    bg="#246b4b" if metadata_valid and mode == algorithm_id else "#27313b",
                )
            if not self.algorithm_command_busy:
                self.algorithm_status.set(
                    f"已回读：{MODE_NAMES.get(mode, '未知')}"
                    if metadata_valid
                    else "等待新固件回读"
                )
        semantic_frequency = str(status.get("semantic_update_frequency", "-"))
        semantic_frequency = semantic_frequency.replace("scene refresh every ", "每 ").replace("s; motion candidates use an independent priority queue", " 秒刷新；动作优先")
        self.performance_text.set(
            f"视频采集    {fps:>6.2f} FPS   {width}×{height}   frame {frame_id}\n"
            f"语义更新    {semantic_frequency}\n"
            f"模型推理    {inference if inference is not None else '-'} 秒\n"
            f"事件延迟    平均 {report_delay.get('mean', '-')} 秒   P95 {report_delay.get('p95', '-')} 秒\n"
            f"事件队列    {queue_state.get('pending', 0)}/{queue_state.get('capacity', 0)}\n"
            f"场景记忆    确认 {memory.get('confirmed_event_count', 0)}   待确认 {memory.get('pending_event_count', 0)}\n"
            f"视频/图像模式 {latest.get('fpga_algorithm_name', '-')}｜命令接收 {latest.get('fpga_command_accepted_count', 0)}/拒收 {latest.get('fpga_command_rejected_count', 0)}\n"
            f"GPU         {data.get('gpu', '-')}\n"
            f"后台服务    Qwen {'正常' if qwen else '未就绪'} · 感知 {'正常' if status else '未就绪'} · Hermes {'正常' if hermes else '未就绪'}"
        )

        scene = data.get("scene") if isinstance(data.get("scene"), dict) else {}
        current = scene.get("scene") or {}
        summary = current.get("summary") or "尚无可靠场景描述"
        scene_type = str(current.get("scene_type") or "").strip()
        scene_lines = [
            f"场景类型：{scene_type}" if scene_type else "场景类型：等待静态场景分析",
            f"场景概况：{summary}",
        ]
        environment = str(current.get("environment") or "").strip()
        current_state = str(current.get("current_state") or "").strip()
        if environment:
            scene_lines.append(f"环境：{environment}")
        if current_state:
            scene_lines.append(f"当前状态：{current_state}")
        observations = current.get("observations") or []
        object_states = []
        for item in observations[:4]:
            if not isinstance(item, dict):
                continue
            name = str(item.get("name") or "物体")
            position = str(item.get("position") or "位置不确定")
            state_text = str(item.get("state") or "")
            object_states.append(
                f"{name}：{position}" + (f"，{state_text}" if state_text else "")
            )
        if object_states:
            scene_lines.append("画面中的物体：" + "；".join(object_states))
        else:
            scene_lines.append("画面中的物体：等待模型识别")
        scene_lines.append(
            f"视频输入：{latest.get('fpga_algorithm_name', '-')}｜"
            f"队列：{queue_state.get('pending', 0)}/{queue_state.get('capacity', 0)}｜"
            f"确认 {memory.get('confirmed_event_count', 0)} / 待确认 {memory.get('pending_event_count', 0)}"
        )
        self.scene_text.set("\n".join(scene_lines))
        events_payload = data.get("events") if isinstance(data.get("events"), dict) else {}
        items = events_payload.get("events") or []
        lines = []
        for item in items[-8:]:
            flag = "确认" if item.get("status") == "confirmed" else "待确认"
            when = _beijing_event_time(item)
            description = item.get("description") or item.get("object") or "-"
            before_state = str(item.get("before_state") or "").strip()
            after_state = str(item.get("after_state") or "").strip()
            state_line = (
                f"\n  状态变化：{before_state or '未记录'} → {after_state or '未记录'}"
            )
            lines.append(
                f"[{flag}] {when}  {item.get('type', '-')}\n  {description}{state_line}"
            )
        rendered = "\n\n".join(lines) if lines else "本会话尚无事件。"
        signature = rendered
        if signature != self.last_event_signature:
            self.events.configure(state="normal")
            self.events.delete("1.0", "end")
            self.events.insert("1.0", rendered)
            self.events.see("end")
            self.events.configure(state="disabled")
            self.last_event_signature = signature

    def _append_chat(self, speaker: str, text: str) -> None:
        self.chat_history.configure(state="normal")
        self.chat_history.insert("end", f"{speaker}：{text.strip()}\n\n")
        self.chat_history.see("end")
        self.chat_history.configure(state="disabled")

    def send_chat(self) -> None:
        question = self.chat_entry.get().strip()
        if not question or self.chat_busy:
            return
        self.chat_entry.delete(0, "end")
        self._append_chat("你", question)
        self.chat_busy = True
        self.chat_button.configure(text="思考中…", state="disabled")
        threading.Thread(target=self._chat_worker, args=(question,), daemon=True).start()

    def _chat_worker(self, question: str) -> None:
        history_query = bool(
            re.search(r"刚才|刚刚|之前|历史|拿起|拿了|拿过|拿什么|拿了什么|放下|移动|出现过|消失|去哪|做了什么", question)
        )
        algorithm_need = bool(
            re.search(r"识别|看清|增强|处理|算法|灰度|黑白|负片|反色|轮廓|边缘|低照度|暗|对比度|切换", question)
        )
        if history_query:
            try:
                result = vision.search_memory(question, seconds=3600, limit=10)
                confirmed = result.get("events") or []
                pending = result.get("pending_events") or []
                if confirmed:
                    rows = []
                    for item in confirmed[-3:]:
                        row = (
                            f"已确认：{item.get('description') or item.get('object') or item.get('type', '事件')}"
                            + (f"（{item.get('occurred_at')}）" if item.get("occurred_at") else "")
                        )
                        before_state = str(item.get("before_state") or "").strip()
                        after_state = str(item.get("after_state") or "").strip()
                        if before_state or after_state:
                            row += f"；状态变化：{before_state or '未记录'} → {after_state or '未记录'}"
                        rows.append(row)
                    if pending:
                        rows.append("另有待确认线索：" + "；".join(
                            str(item.get("description") or item.get("object") or item.get("type", "事件"))
                            for item in pending[-2:]
                        ))
                    answer = "根据已保存的场景记忆：" + "\n".join(rows)
                elif pending:
                    rows = [
                        str(item.get("description") or item.get("object") or item.get("type", "事件"))
                        for item in pending[-3:]
                    ]
                    answer = "记忆中有相关线索，但模型尚未确认，不能当作事实：" + "；".join(rows)
                else:
                    answer = "场景记忆中没有找到这类已保存事件；我没有读取新画面来推测过去。"
                self.messages.put(("chat_result", answer))
            except Exception as error:
                self.messages.put(("chat_result", f"读取场景记忆失败：{error}"))
            return

        if re.search(
            r"现在|此刻|当前.*(看到|画面)|看到了什么|场景|环境|画面里有什么|画面中有什么|有什么物体|有什么东西|有哪些物体|有哪些东西",
            question,
        ):
            try:
                result = vision.scene()
                scene = result.get("scene") or {}
                summary = scene.get("summary") or "当前还没有可靠场景描述。"
                details = []
                if scene.get("scene_type"):
                    details.append(f"场景类型：{scene['scene_type']}")
                if scene.get("environment"):
                    details.append(f"环境：{scene['environment']}")
                if scene.get("current_state"):
                    details.append(f"当前状态：{scene['current_state']}")
                observations = scene.get("observations") or []
                for item in observations[:4]:
                    if isinstance(item, dict):
                        state_text = str(item.get("state") or "").strip()
                        position = str(item.get("position") or "位置不确定")
                        details.append(
                            f"{item.get('name') or '物体'}：{position}"
                            + (f"，{state_text}" if state_text else "")
                        )
                age = result.get("scene_age_seconds")
                suffix = f"（场景结果约 {float(age):.1f} 秒前更新）" if age is not None else ""
                detail_text = "\n".join(details)
                answer = str(summary) + ("\n" + detail_text if detail_text else "") + suffix
                self.messages.put(("chat_result", answer))
            except Exception as error:
                self.messages.put(("chat_result", f"读取当前场景失败：{error}"))
            return
        rule = (
            "这是历史问题。只能调用 cam1-vision 的 get_recent_scene_events 或 search_scene_memory，"
            "禁止获取新图像来猜测历史。必须检查工具返回的 events 与 pending_events："
            "已确认事件可直接回答；若只有待确认线索，说明线索内容并明确标注‘尚未确认’，"
            "不能说成完全没有记录，也不能把待确认线索说成事实。"
            if history_query
            else "这是当前场景问题。优先调用 cam1-vision 的 get_current_scene；只有确需像素时才获取当前帧。"
        )
        algorithm_rule = (
            "用户提出了视觉处理或识别目标。必须先调用 list_vision_algorithms 读取 OV5640 当前图像模式，"
            "再结合目标选择：color=彩色，gray=灰度，binary=OV5640黑白效果，invert=负片效果；"
            "只有确有收益且用户任务需要时才调用 select_fpga_algorithm，完成后检查其硬件_verified/回读结果，"
            "确认后再继续取图或回答。FPGA 将命令经 SCCB 写入 OV5640 并在帧边界应用；"
            "后续 JPEG 视频帧元数据会回报当前模式和命令序号。"
            if algorithm_need
            else "不要为普通场景问答切换 OV5640 图像模式；保持当前硬件模式。"
        )
        prompt = (
            "你是 CAM1 FPGA 视觉 Agent，具有 cam1-vision MCP 工具。" + rule + algorithm_rule
            + "只能依据工具返回的可靠证据，用简洁中文回答；没有记录就明确说没有可靠记录，绝不编造。\n用户问题："
            + question
        )
        if not HERMES.exists():
            self.messages.put(("chat_result", "Hermes 未安装或路径未配置。请重新运行一键安装。"))
            return
        try:
            result = subprocess.run(
                [str(HERMES), "--in", str(PROJECT_ROOT), "-z", prompt],
                cwd=str(PROJECT_ROOT), capture_output=True, text=True,
                encoding="utf-8", errors="replace", timeout=150,
                creationflags=CREATE_NO_WINDOW, env=os.environ.copy(),
            )
            answer = result.stdout.strip()
            if not answer:
                answer = "Hermes 本次没有返回有效答案。" + (f"（{result.stderr.strip()[-160:]}）" if result.stderr.strip() else "")
        except subprocess.TimeoutExpired:
            answer = "Hermes 回答超时，但持续感知仍在后台运行。"
        except Exception as error:
            answer = f"Hermes 调用失败：{error}"
        self.messages.put(("chat_result", answer))

    def _finish_chat(self, answer: str) -> None:
        self._append_chat("Hermes", answer)
        self.chat_busy = False
        self.chat_button.configure(text="发送", state="normal")
        self.chat_entry.focus_set()

    def select_fpga_algorithm(self, mode: str) -> None:
        if self.algorithm_command_busy:
            return
        self.algorithm_command_busy = True
        self.algorithm_status.set("发送硬件命令…")
        for button in self.algorithm_buttons.values():
            button.configure(state="disabled")
        threading.Thread(
            target=self._select_fpga_algorithm_worker,
            args=(mode,),
            daemon=True,
        ).start()

    def _select_fpga_algorithm_worker(self, mode: str) -> None:
        result: dict[str, object]
        try:
            before = vision.status()
            latest = before.get("latest_frame") or {}
            if not latest:
                raise RuntimeError("当前没有 FPGA 视频帧；先恢复视频输入再切换算法。")
            controller = FpgaAlgorithmController(
                os.environ.get("CAM1_PCAP_INTERFACE") or None
            )
            controller.synchronize_sequence(int(latest.get("fpga_sequence", 0) or 0))
            request = controller.select(mode)
            deadline = time.monotonic() + 3.0
            observed: dict[str, object] = {}
            while time.monotonic() < deadline:
                observed = vision.status().get("latest_frame") or {}
                if (
                    observed.get("fpga_sequence") == request.sequence
                    and observed.get("fpga_algorithm") == request.mode
                ):
                    result = {
                        "ok": True,
                        "mode": request.mode,
                        "name": MODE_NAMES[request.mode],
                    }
                    break
                time.sleep(0.05)
            else:
                raise TimeoutError("命令已发送，但未从后续 FPGA 视频帧读回确认。")
        except Exception as error:
            result = {"ok": False, "error": str(error)}
        self.messages.put(("algorithm_result", result))

    def _apply_algorithm_result(self, result: dict[str, object]) -> None:
        self.algorithm_command_busy = False
        for button in self.algorithm_buttons.values():
            button.configure(state="normal")
        if result.get("ok"):
            name = str(result.get("name", "OV5640图像模式"))
            self.algorithm_status.set(f"已回读：{name}")
            self._log(f"OV5640 图像模式已由后续视频帧回读确认：{name}。", "ok")
        else:
            error = str(result.get("error", "硬件切换失败"))
            self.algorithm_status.set("切换未确认")
            self._log(f"图像算法切换未确认：{error}", "warn")

    def start_services(self) -> None:
        threading.Thread(target=self._start_services_worker, daemon=True).start()

    def _start_services_worker(self) -> None:
        started: list[str] = []
        if not _http_ok(MODEL_HEALTH_URL):
            if MODEL_MODE == "local":
                server = Path(os.environ.get("LLAMA_SERVER", ""))
                model = Path(os.environ.get("QWEN3VL_MODEL", ""))
                mmproj = Path(os.environ.get("QWEN3VL_MMPROJ", ""))
                if server.exists() and model.exists() and mmproj.exists():
                    command = [
                        str(server), "--model", str(model), "--mmproj", str(mmproj),
                        "--alias", os.environ.get("MODEL_NAME", "qwen3-vl-8b-instruct-q4_k_m"),
                        "--host", "127.0.0.1", "--port", str(MODEL_SERVER_PORT),
                        "--ctx-size", "16384", "--batch-size", "1024", "--ubatch-size", "256",
                        "--gpu-layers", "all", "--flash-attn", "on", "--parallel", "1",
                        "--image-min-tokens", "144", "--image-max-tokens", "384", "--no-webui",
                    ]
                    _hidden_popen(command, cwd=str(server.parent), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    started.append("本地 Qwen3-VL")
                else:
                    self.messages.put(("log", ("本地模型配置不完整，请重新运行安装程序。", "error")))
            else:
                self.messages.put(("log", (f"等待已有模型服务：{MODEL_SERVER_URL}", "warn")))
        if vision.is_running():
            # Restart an older daemon so the live-preview and structured-scene
            # response changes take effect. Persistent memory stays on disk.
            try:
                current_status = vision.status()
                config_path = str(current_status.get("config_path") or "")
                foreign_service = not config_path or not Path(config_path).resolve().is_relative_to(ROOT.resolve())
                if foreign_service or int(current_status.get("service_behavior_version", 0) or 0) < 12:
                    old_pid = int(current_status.get("process_id", 0) or 0)
                    if old_pid:
                        subprocess.run(
                            ["taskkill", "/PID", str(old_pid), "/T", "/F"],
                            creationflags=CREATE_NO_WINDOW,
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                        )
                    deadline = time.monotonic() + 5
                    while vision.is_running() and time.monotonic() < deadline:
                        time.sleep(0.2)
                    started.append("已更新持续感知服务")
            except Exception as error:
                self.messages.put(("log", (f"无法检查持续感知服务版本：{error}", "warn")))
        if not vision.is_running():
            env = os.environ.copy()
            config = _active_config()
            if config:
                env["CAM1_PERCEPTION_CONFIG"] = config
            _hidden_popen([str(PYTHON), str(ROOT / "continuous_perception.py")], cwd=str(ROOT), env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            started.append("持续感知")
        if not _hermes_running() and HERMES.exists():
            _hidden_popen([str(HERMES), "gateway", "run"], cwd=str(HERMES.parent), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            started.append("Hermes")
        self.messages.put(("log", (("已在后台启动：" + "、".join(started)) if started else "所有后台服务已在运行。", "ok")))

    def new_demo_session(self) -> None:
        threading.Thread(target=self._new_demo_session_worker, daemon=True).start()

    def _new_demo_session_worker(self) -> None:
        try:
            runtime = ROOT / "runtime"
            stamp = time.strftime("%Y%m%d_%H%M%S")
            session_root = runtime / "demo_sessions" / stamp
            backup_root = runtime / "memory_backups"
            session_root.mkdir(parents=True, exist_ok=False)
            backup_root.mkdir(parents=True, exist_ok=True)

            old_memory: Path | None = None
            process_id = 0
            try:
                status = vision.status()
                process_id = int(status.get("process_id", 0) or 0)
                memory_path = (status.get("memory") or {}).get("path")
                if memory_path:
                    old_memory = Path(str(memory_path))
            except Exception:
                pass
            backup_path = None
            if old_memory and old_memory.exists():
                backup_path = backup_root / f"continuous_scene_memory_pre_demo_{stamp}.json"
                shutil.copy2(old_memory, backup_path)

            base_config = json.loads((ROOT / "continuous_perception_config.json").read_text(encoding="utf-8-sig"))
            relative = f"runtime/demo_sessions/{stamp}"
            base_config["memory"]["state_file"] = f"{relative}/continuous_scene_memory.json"
            base_config["events"]["audit_file"] = f"{relative}/event_pipeline.jsonl"
            base_config["events"]["evidence_directory"] = f"{relative}/event_evidence"
            config_path = session_root / "competition_session_config.json"
            config_path.write_text(json.dumps(base_config, ensure_ascii=False, indent=2), encoding="utf-8")
            manifest = {
                "session_id": stamp,
                "created_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                "config_path": str(config_path),
                "memory_path": str(session_root / "continuous_scene_memory.json"),
                "previous_memory_backup": str(backup_path) if backup_path else None,
                "purpose": "CAM1 FPGA continuous vision isolated live session",
            }
            (session_root / "session_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
            ACTIVE_CONFIG.write_text(str(config_path), encoding="utf-8")

            if process_id and _pid_running(process_id):
                subprocess.run(["taskkill", "/PID", str(process_id), "/T", "/F"], creationflags=CREATE_NO_WINDOW, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            deadline = time.monotonic() + 5
            while vision.is_running() and time.monotonic() < deadline:
                time.sleep(0.2)
            env = os.environ.copy()
            env["CAM1_PERCEPTION_CONFIG"] = str(config_path)
            _hidden_popen([str(PYTHON), str(ROOT / "continuous_perception.py")], cwd=str(ROOT), env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            deadline = time.monotonic() + 15
            while not vision.is_running() and time.monotonic() < deadline:
                time.sleep(0.25)
            if not vision.is_running():
                raise RuntimeError("新持续感知服务未在15秒内启动")
            self.messages.put(("log", (f"已新建空白演示会话 {stamp}；旧记忆已备份。", "ok")))
        except Exception as error:
            self.messages.put(("log", (f"新建演示会话失败：{error}", "error")))

    def run(self) -> None:
        self.root.protocol("WM_DELETE_WINDOW", self.root.destroy)
        self.root.mainloop()


if __name__ == "__main__":
    if not ensure_single_instance():
        raise SystemExit(0)
    ControlCenter().run()

