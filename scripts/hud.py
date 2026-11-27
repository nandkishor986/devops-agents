#!/usr/bin/env python3
"""InfraCortex HUD for macOS/Linux (tkinter). Windows uses hud.ps1. Same state.json contract.

Usage: hud.py <state_dir>   — started automatically by agent_events.py; exits after 90 s idle.
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

try:
    import tkinter as tk
except ImportError:  # no Tk on this Python: silently skip the HUD
    sys.exit(0)

STATE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / ".infracortex" / "hud"
COLORS = {"terraform-engineer": "#8B5CF6", "k8s-troubleshooter": "#3B82F6",
          "docker-engineer": "#06B6D4", "finops-analyst": "#22C55E",
          "cortex": "#F97316", "overseer": "#14B8A6"}
GLYPH = {"PASS": "✅", "DONE": "✅", "WARN": "⚠️", "FAIL": "❌", "BLOCKED": "⛔"}
W, CARD = 340, 70


def elapsed(s: float) -> str:
    return f"{s:.0f}s" if s < 60 else f"{int(s // 60)}m{int(s % 60):02d}s"


class Hud:
    def __init__(self) -> None:
        self.root = tk.Tk()
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.configure(bg="#1e1e2e")
        self.tick, self.idle, self.moved = 0, time.time(), False
        bar = tk.Frame(self.root, bg="#1e1e2e")
        bar.pack(fill="x")
        tk.Label(bar, text="  🤖  InfraCortex", fg="#cdd6f4", bg="#1e1e2e", font=("Helvetica", 10, "bold")).pack(side="left")
        tk.Button(bar, text="×", command=self.root.destroy, bd=0, fg="#a6adc8", bg="#1e1e2e").pack(side="right")
        bar.bind("<B1-Motion>", self.drag)
        self.body = tk.Frame(self.root, bg="#1e1e2e")
        self.body.pack(fill="both", expand=True)
        self.root.after(100, self.refresh)

    def drag(self, e) -> None:
        self.moved = True
        self.root.geometry(f"+{e.x_root - 60}+{e.y_root - 10}")

    def refresh(self) -> None:
        self.tick += 1
        (STATE / "heartbeat").write_text(str(time.time()))
        try:
            agents = json.loads((STATE / "state.json").read_text()).get("agents", {})
        except (OSError, ValueError):
            agents = {}
        now = time.time()
        live = sorted(((k, a) for k, a in agents.items() if not a.get("ended") or now - a["ended"] < 12),
                      key=lambda kv: kv[1].get("started", 0))
        for w in self.body.winfo_children():
            w.destroy()
        for _, a in live:
            col = COLORS.get(a.get("type"), "#F59E0B")
            card = tk.Frame(self.body, bg="#313244", highlightthickness=0)
            card.pack(fill="x", padx=6, pady=3)
            tk.Frame(card, bg=col, width=5).pack(side="left", fill="y")
            done = a.get("status") == "done"
            icon = GLYPH.get(a.get("result", ""), "✅") if done else ("🤖" if self.tick % 2 else "🦾")
            tk.Label(card, text=icon, font=("Helvetica", 22), fg=col, bg="#313244", width=2).pack(side="left", padx=4)
            txt = tk.Frame(card, bg="#313244")
            txt.pack(side="left", fill="x", expand=True)
            head = f"{a.get('type')}  -  {a.get('result')}" if done else f"{a.get('type')}  working{'.' * (1 + self.tick % 3)}"
            tk.Label(txt, text=head, fg="white", bg="#313244", font=("Helvetica", 10, "bold"), anchor="w").pack(fill="x")
            tk.Label(txt, text=str(a.get("action", ""))[:48], fg="#bac2de", bg="#313244", font=("Courier", 9), anchor="w").pack(fill="x")
            t = (a.get("ended", now) if done else now) - a.get("started", now)
            tk.Label(txt, text=f"{elapsed(t)} | {a.get('steps', 0)} steps | {a.get('errors', 0)} errors", fg="#9399b2",
                     bg="#313244", font=("Helvetica", 8), anchor="w").pack(fill="x")
        h = 26 + max(1, len(live)) * CARD
        if not self.moved:
            self.root.geometry(f"{W}x{h}+{self.root.winfo_screenwidth() - W - 16}+{self.root.winfo_screenheight() - h - 60}")
        else:
            self.root.geometry(f"{W}x{h}")
        if live:
            self.idle = now
            self.root.deiconify()
        else:
            self.root.withdraw()
            if now - self.idle > 90:
                self.root.destroy()
                return
        self.root.after(450, self.refresh)


if __name__ == "__main__":
    STATE.mkdir(parents=True, exist_ok=True)
    Hud().root.mainloop()
