#!/usr/bin/env python3
"""One-window installer for the CAM1 FPGA + AI host application."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
AI_ROOT = ROOT / "host" / "ai_vision"
VENV = AI_ROOT / ".venv"
CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


class Installer:
    def __init__(self) -> None:
        self.root = tk.Tk()
        self.root.title("CAM1 FPGA + AI 一键安装")
        self.root.geometry("760x690")
        self.root.resizable(False, False)

        local_appdata = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
        self.mode = tk.StringVar(value="external")
        self.server_url = tk.StringVar(value="http://127.0.0.1:8081")
        self.model_port = tk.StringVar(value="8081")
        self.model_name = tk.StringVar(value="qwen3-vl-8b-instruct-q4_k_m")
        self.interface = tk.StringVar(value="")
        self.llama = tk.StringVar(value="")
        self.model = tk.StringVar(value="")
        self.mmproj = tk.StringVar(value="")
        self.hermes = tk.StringVar(value=str(local_appdata / "Hermes" / "bin" / "hermes.exe"))
        self.status = tk.StringVar(value="检查电脑环境；已安装的组件会直接复用。")
        self.had_installation = False
        self._load_saved_settings()
        self._build()

    def _load_saved_settings(self) -> None:
        try:
            settings = json.loads((ROOT / "installation.json").read_text(encoding="utf-8-sig"))
        except Exception:
            return
        self.had_installation = True
        self.mode.set(settings.get("MODEL_MODE", self.mode.get()))
        self.server_url.set(settings.get("MODEL_SERVER_URL", self.server_url.get()))
        # Older installations implicitly used 8080 and did not store a port.
        # Migrate those installations to the new explicit, editable default.
        self.model_port.set(str(settings.get("MODEL_SERVER_PORT", 8081)))
        self.model_name.set(settings.get("MODEL_NAME", self.model_name.get()))
        self.interface.set(settings.get("CAM1_PCAP_INTERFACE", self.interface.get()))
        self.hermes.set(settings.get("HERMES_EXE", self.hermes.get()))
        self.llama.set(settings.get("LLAMA_SERVER", ""))
        self.model.set(settings.get("QWEN3VL_MODEL", ""))
        self.mmproj.set(settings.get("QWEN3VL_MMPROJ", ""))

    def _build(self) -> None:
        frame = ttk.Frame(self.root, padding=22)
        frame.pack(fill="both", expand=True)
        ttk.Label(frame, text="CAM1 FPGA + AI 上位机安装", font=("Microsoft YaHei UI", 18, "bold")).pack(anchor="w")
        ttk.Label(frame, text="安装 Python 依赖并写入本机配置；不会自动下载任何大模型。", foreground="#555").pack(anchor="w", pady=(4, 18))

        model_box = ttk.LabelFrame(frame, text="视觉模型", padding=12)
        model_box.pack(fill="x")
        ttk.Radiobutton(model_box, text="连接已有本地模型服务", variable=self.mode, value="external", command=self._toggle).grid(row=0, column=0, columnspan=3, sticky="w")
        ttk.Label(model_box, text="已有服务地址").grid(row=1, column=0, sticky="w", pady=6)
        self.server_entry = ttk.Entry(model_box, textvariable=self.server_url, width=62)
        self.server_entry.grid(row=1, column=1, columnspan=2, sticky="ew", pady=6)
        ttk.Label(model_box, text="模型名称/alias").grid(row=2, column=0, sticky="w", pady=6)
        ttk.Entry(model_box, textvariable=self.model_name, width=62).grid(row=2, column=1, columnspan=2, sticky="ew", pady=6)

        ttk.Radiobutton(model_box, text="选择本机 llama.cpp 与 GGUF 模型，由连续视觉系统自动启动", variable=self.mode, value="local", command=self._toggle).grid(row=3, column=0, columnspan=3, sticky="w", pady=(10, 4))
        self.local_rows: list[tk.Widget] = []
        port_label = ttk.Label(model_box, text="本地模型监听端口")
        port_entry = ttk.Entry(model_box, textvariable=self.model_port, width=16)
        port_hint = ttk.Label(model_box, text="可在每次启动前修改，不固定占用 8080")
        port_label.grid(row=4, column=0, sticky="w", pady=4)
        port_entry.grid(row=4, column=1, sticky="w", pady=4)
        port_hint.grid(row=4, column=2, sticky="w", padx=(8, 0), pady=4)
        self.local_rows.extend((port_label, port_entry, port_hint))
        for row, (label, variable, pattern) in enumerate((
            ("llama-server.exe", self.llama, "*.exe"),
            ("Qwen3-VL GGUF", self.model, "*.gguf"),
            ("视觉 mmproj GGUF", self.mmproj, "*.gguf"),
        ), start=5):
            lbl = ttk.Label(model_box, text=label)
            ent = ttk.Entry(model_box, textvariable=variable, width=48)
            btn = ttk.Button(model_box, text="选择", command=lambda v=variable, p=pattern: self._pick(v, p))
            lbl.grid(row=row, column=0, sticky="w", pady=4)
            ent.grid(row=row, column=1, sticky="ew", pady=4)
            btn.grid(row=row, column=2, padx=(8, 0), pady=4)
            self.local_rows.extend((lbl, ent, btn))
        model_box.columnconfigure(1, weight=1)

        system_box = ttk.LabelFrame(frame, text="硬件与 Agent", padding=12)
        system_box.pack(fill="x", pady=14)
        ttk.Label(system_box, text="X520-2 / Npcap 接口标识").grid(row=0, column=0, sticky="w", pady=5)
        ttk.Entry(system_box, textvariable=self.interface, width=50).grid(row=0, column=1, sticky="ew", pady=5)
        ttk.Label(system_box, text="Hermes 可执行文件").grid(row=1, column=0, sticky="w", pady=5)
        ttk.Entry(system_box, textvariable=self.hermes, width=50).grid(row=1, column=1, sticky="ew", pady=5)
        ttk.Button(system_box, text="选择", command=lambda: self._pick(self.hermes, "*.exe")).grid(row=1, column=2, padx=(8, 0))
        system_box.columnconfigure(1, weight=1)

        self.progress = ttk.Progressbar(frame, mode="indeterminate")
        self.progress.pack(fill="x", pady=(4, 8))
        ttk.Label(frame, textvariable=self.status, wraplength=700).pack(anchor="w")
        self.install_button = ttk.Button(frame, text="检查并启动", command=self.install)
        self.install_button.pack(fill="x", pady=(14, 0), ipady=8)
        self._toggle()

    def _toggle(self) -> None:
        local_mode = self.mode.get() == "local"
        state = "normal" if local_mode else "disabled"
        for widget in self.local_rows:
            widget.configure(state=state)
        self.server_entry.configure(state="disabled" if local_mode else "normal")

    def _pick(self, variable: tk.StringVar, pattern: str) -> None:
        path = filedialog.askopenfilename(filetypes=[("文件", pattern), ("所有文件", "*.*")])
        if path:
            variable.set(path)

    def install(self) -> None:
        if self.mode.get() == "local":
            missing = [path for path in (self.llama.get(), self.model.get(), self.mmproj.get()) if not Path(path).is_file()]
            if missing:
                messagebox.showerror("配置不完整", "请选择有效的 llama-server、模型 GGUF 和 mmproj GGUF。")
                return
            try:
                port = int(self.model_port.get())
                if not 1 <= port <= 65535:
                    raise ValueError
            except ValueError:
                messagebox.showerror("端口错误", "本地模型监听端口必须是 1 到 65535 之间的整数。")
                return
        if not self.server_url.get().startswith(("http://", "https://")):
            messagebox.showerror("地址错误", "模型服务地址必须以 http:// 或 https:// 开头。")
            return
        self.install_button.configure(state="disabled")
        self.progress.start(10)
        threading.Thread(target=self._worker, daemon=True).start()

    def _worker(self) -> None:
        try:
            python = VENV / "Scripts" / "python.exe"
            pythonw = VENV / "Scripts" / "pythonw.exe"
            if not python.exists() or not pythonw.exists():
                self._set_status("电脑中还没有项目运行环境，正在首次创建…")
                subprocess.run([sys.executable, "-m", "venv", str(VENV)], check=True, creationflags=CREATE_NO_WINDOW)

            python = VENV / "Scripts" / "python.exe"
            pythonw = VENV / "Scripts" / "pythonw.exe"
            self._set_status("正在检查已安装的上位机组件…")
            check = subprocess.run(
                [str(python), "-c", "import numpy, PIL, psutil, mcp"],
                capture_output=True, text=True, creationflags=CREATE_NO_WINDOW,
            )
            if check.returncode != 0:
                self._set_status("发现缺少依赖，正在补装…")
                subprocess.run(
                    [str(python), "-m", "pip", "install", "-r", str(ROOT / "requirements.txt")],
                    check=True, creationflags=CREATE_NO_WINDOW,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
            else:
                self._set_status("运行环境已齐全，复用现有组件…")

            if self.mode.get() == "local":
                model_port = int(self.model_port.get())
                server = f"http://127.0.0.1:{model_port}"
            else:
                server = self.server_url.get().rstrip("/")
                try:
                    model_port = urlsplit(server).port or 80
                except ValueError:
                    model_port = 80
            settings = {
                "MODEL_MODE": self.mode.get(),
                "MODEL_SERVER_URL": server,
                "MODEL_SERVER_PORT": model_port,
                "QWEN3VL_API_BASE": server + "/v1",
                "MODEL_NAME": self.model_name.get().strip(),
                "CAM1_PCAP_INTERFACE": self.interface.get().strip(),
                "HERMES_EXE": self.hermes.get().strip(),
                "HERMES_STATE": str(Path(self.hermes.get()).parents[1] / "gateway_state.json") if self.hermes.get() else "",
                "LLAMA_SERVER": self.llama.get().strip(),
                "QWEN3VL_MODEL": self.model.get().strip(),
                "QWEN3VL_MMPROJ": self.mmproj.get().strip(),
            }
            (ROOT / "installation.json").write_text(json.dumps(settings, ensure_ascii=False, indent=2), encoding="utf-8")

            hermes = Path(self.hermes.get())
            if hermes.is_file() and not self.had_installation:
                subprocess.run([str(hermes), "mcp", "remove", "cam1-vision"], capture_output=True, creationflags=CREATE_NO_WINDOW)
                subprocess.run(
                    [str(hermes), "mcp", "add", "cam1-vision", "--command", str(python), "--args", str(AI_ROOT / "vision_mcp_server.py")],
                    cwd=str(AI_ROOT), capture_output=True, creationflags=CREATE_NO_WINDOW,
                )

            self.root.after(0, lambda: self._done(pythonw))
        except Exception as error:
            self.root.after(0, lambda: self._failed(str(error)))

    def _set_status(self, text: str) -> None:
        self.root.after(0, lambda: self.status.set(text))

    def _done(self, pythonw: Path) -> None:
        self.progress.stop()
        self.status.set("环境就绪，正在启动连续视觉总控…")
        try:
            subprocess.Popen(
                [str(pythonw), str(AI_ROOT / "competition_control_center.py")],
                cwd=str(AI_ROOT), stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                creationflags=CREATE_NO_WINDOW,
            )
            self.root.after(500, self.root.destroy)
        except Exception as error:
            self.install_button.configure(state="normal")
            self.status.set("启动失败：" + str(error))

    def _failed(self, error: str) -> None:
        self.progress.stop()
        self.install_button.configure(state="normal")
        self.status.set("安装失败：" + error)
        messagebox.showerror("安装失败", error)

    def run(self) -> None:
        self.root.mainloop()


if __name__ == "__main__":
    Installer().run()
