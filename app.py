#!/usr/bin/env python3
"""PiSpider Hybrid Core — SoloHost dashboard (replaces Windows WinForms)."""
from __future__ import annotations

import json
import os
import time
from datetime import datetime, timezone, timedelta
from pathlib import Path

from flask import Flask, jsonify, render_template, request, redirect, send_file

TZ = timezone(timedelta(hours=7))
app = Flask(__name__)

def cfg_path() -> Path:
    candidates = [
        Path(os.environ.get("PISPIDER_CONFIG") or "/data/pispider-config.json"),
        Path("/data/pispider-config.json"),
        Path("/app/config.json"),
    ]
    for p in candidates:
        if p.is_file():
            return p
        # SoloHost sometimes creates a DIRECTORY named config.json — never use it.
        if p.exists() and p.is_dir():
            bak = p.with_name(p.name + ".was-dir")
            try:
                if not bak.exists():
                    p.rename(bak)
            except Exception:
                pass
    return Path("/data/pispider-config.json")


def load_cfg() -> dict:
    p = cfg_path()
    if p.is_file():
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {
        "Port": 18770,
        "BusDir": "/data/live",
        "PacksDir": "/data/packs",
        "GitHub": {},
        "WindowsUi": os.environ.get("WINDOWS_UI") or "http://127.0.0.1:18771",
    }


def data_root() -> Path:
    return Path(os.environ.get("PISPIDER_DATA", "/data"))


def bus_dirs() -> list:
    out = []
    for d in (
        worker_dir() / "Data" / "live",
        data_root() / "live",
        app_root() / "data" / "live",
        app_root() / "Data" / "live",
    ):
        try:
            d.mkdir(parents=True, exist_ok=True)
            if d not in out:
                out.append(d)
        except Exception:
            pass
    return out or [data_root() / "live"]


def bus_dir() -> Path:
    return bus_dirs()[0]


def packs_dir() -> Path:
    cfg = load_cfg()
    d = Path(cfg.get("PacksDir") or str(data_root() / "packs"))
    d.mkdir(parents=True, exist_ok=True)
    return d


def app_root() -> Path:
    """SoloHost app folder (compose volume ./:/solohost-config)."""
    p = Path(os.environ.get("SOLOHOST_CONFIG") or "/solohost-config")
    try:
        p.mkdir(parents=True, exist_ok=True)
        return p
    except Exception:
        return data_root()


def worker_dir() -> Path:
    """Only one copy: SoloHost app root /WindowsWorker."""
    d = app_root() / "WindowsWorker"
    try:
        d.mkdir(parents=True, exist_ok=True)
        return d
    except Exception:
        d = data_root() / "WindowsWorker"
        d.mkdir(parents=True, exist_ok=True)
        return d


def bundled_zip() -> Path | None:
    for p in (
        Path("/app/packs/windows-worker.zip"),
        Path(__file__).resolve().parent / "packs" / "windows-worker.zip",
        Path(__file__).resolve().parent / "windows-worker.zip",
    ):
        if p.is_file():
            return p
    return None


def ensure_windows_worker(force_download: bool = False) -> dict:
    """Place WindowsWorker in SoloHost app root. Do not activate."""
    import shutil
    import zipfile

    dest_dir = worker_dir()
    dest_zip = packs_dir() / "windows-worker.zip"
    marker = dest_dir / "Activate_Worker.bat"
    cfg = load_cfg()
    url = (cfg.get("GitHub") or {}).get("WorkerPackUrl") or ""

    if marker.is_file() and not force_download:
        state = {
            "Ready": True,
            "Activated": False,
            "Path": str(dest_dir),
            "Zip": str(dest_zip) if dest_zip.is_file() else None,
            "Source": "existing",
            "UpdatedAt": now_iso(),
        }
        write_json(data_root() / "install_state.json", {"WorkerPack": state})
        return state

    err = None
    source = "bundled"
    try:
        src = bundled_zip()
        if force_download and url and "YOUR_ORG" not in url:
            import requests

            r = requests.get(url, timeout=90)
            r.raise_for_status()
            dest_zip.write_bytes(r.content)
            src = dest_zip
            source = "github"
        elif src:
            if src.resolve() != dest_zip.resolve():
                shutil.copy2(src, dest_zip)
        elif url and "YOUR_ORG" not in url:
            import requests

            r = requests.get(url, timeout=90)
            r.raise_for_status()
            dest_zip.write_bytes(r.content)
            src = dest_zip
            source = "github"
        elif dest_zip.is_file():
            src = dest_zip
            source = "cached-zip"
        else:
            src = None

        bundled_dir = Path("/app/WindowsWorker")
        if not bundled_dir.is_dir():
            bundled_dir = Path(__file__).resolve().parent / "WindowsWorker"

        if src and src.is_file():
            with zipfile.ZipFile(src) as zf:
                zf.extractall(dest_dir)
        elif bundled_dir.is_dir() and (bundled_dir / "Activate_Worker.bat").is_file():
            if dest_dir.resolve() != bundled_dir.resolve():
                if dest_dir.exists():
                    shutil.rmtree(dest_dir)
                shutil.copytree(bundled_dir, dest_dir)
            source = "image-folder"
        else:
            raise RuntimeError("No bundled pack and GitHub URL not set (YOUR_ORG)")

        act = dest_dir / "ACTIVATE.txt"
        act.write_text(
            "WindowsWorker is ready on SoloHost app root.\n"
            "Copy this folder to the Windows Node PC.\n"
            "Then run Activate_Worker.bat — Core will not start it for you.\n",
            encoding="utf-8",
        )
        state = {
            "Ready": True,
            "Activated": False,
            "Path": str(dest_dir),
            "Zip": str(dest_zip),
            "Bytes": dest_zip.stat().st_size if dest_zip.is_file() else 0,
            "Source": source,
            "UpdatedAt": now_iso(),
        }
    except Exception as e:
        err = str(e)
        state = {
            "Ready": False,
            "Activated": False,
            "Reason": err,
            "UpdatedAt": now_iso(),
        }
    write_json(data_root() / "install_state.json", {"WorkerPack": state})
    return state


def read_json(path: Path) -> dict | None:
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def write_json(path: Path, obj: dict) -> None:
    text = json.dumps(obj, indent=2, ensure_ascii=False)
    targets = [path]
    name = path.name
    if name in {"command.json", "heartbeat.json", "result.json", "pending_approval.json", "ACTIVATE_NOW.json"}:
        for d in bus_dirs():
            targets.append(d / name)
    seen = set()
    for t in targets:
        key = str(t)
        if key in seen:
            continue
        seen.add(key)
        try:
            t.parent.mkdir(parents=True, exist_ok=True)
            tmp = t.with_suffix(".tmp")
            tmp.write_text(text, encoding="utf-8")
            tmp.replace(t)
        except Exception:
            pass


def now_iso() -> str:
    return datetime.now(TZ).isoformat()


def worker_alive(hb: dict | None) -> bool:
    if not hb:
        return False
    ts = hb.get("At") or hb.get("UpdatedAt")
    if not ts:
        return bool(hb.get("Alive"))
    try:
        t = datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
        if t.tzinfo is None:
            t = t.replace(tzinfo=TZ)
        return (datetime.now(TZ) - t.astimezone(TZ)).total_seconds() < 90
    except Exception:
        return bool(hb.get("Alive"))

def all_bus_dirs() -> list[Path]:
    """Return every mounted LiveBus location, including the SoloHost app mount."""
    dirs = []
    candidates = [
        worker_dir() / "Data" / "live",
        data_root() / "live",
        app_root() / "data" / "live",
        app_root() / "Data" / "live",
    ]
    # Also discover a Worker placed one level below the mounted app root.
    try:
        root = app_root()
        for w in root.glob("*/WindowsWorker/Data/live"):
            candidates.append(w)
        candidates.append(root / "WindowsWorker" / "Data" / "live")
    except Exception:
        pass
    for d in candidates:
        try:
            d.mkdir(parents=True, exist_ok=True)
            if d not in dirs:
                dirs.append(d)
        except Exception:
            continue
    return dirs or [data_root() / "live"]


@app.get("/")
def home():
    return render_template("index.html")


@app.get("/api/status")
def api_status():
    hb = result = cmd = pending = {}
    def newest_json(name):
        best = {}
        best_ts = ""
        for d in all_bus_dirs():
            item = read_json(d / name) or {}
            ts = str(item.get("At") or item.get("RequestedAt") or item.get("UpdatedAt") or "")
            if item and (not best or ts > best_ts):
                best, best_ts = item, ts
        return best
    hb = newest_json("heartbeat.json")
    result = newest_json("result.json")
    cmd = newest_json("command.json")
    pending = newest_json("pending_approval.json")
    inst = read_json(data_root() / "install_state.json") or {}
    alive = worker_alive(hb)
    pack = inst.get("WorkerPack") or {}
    return jsonify(
        {
            "ok": True,
            "core": "PiSpider Hybrid Core",
            "time": now_iso(),
            "workerAlive": alive,
            "workerBusy": bool(hb.get("Busy")),
            "heartbeat": hb,
            "lastResult": result,
            "lastCommand": cmd,
            "pending": pending,
            "packInstalled": bool(pack.get("Ready")),
            "packActivated": bool(pack.get("Activated")),
            "pack": pack,
            "workerPath": str(worker_dir()),
            "busPath": str(bus_dir()),
            "termsAccepted": bool((read_json(data_root() / "terms_accepted.json") or {}).get("Accepted")),
            "activateHint": load_cfg().get("WindowsActivateHint"),
        }
    )


@app.post("/api/command")
def api_command():
    body = request.get_json(silent=True) or {}
    action = str(body.get("action") or "SCAN").upper()
    allowed = {"RUN", "SCAN", "PATROL", "STATUS", "REPAIR", "DIGEST", "APPROVE", "DENY", "ACTIVATE"}
    if action not in allowed:
        return jsonify({"ok": False, "error": "unknown action"}), 400
    cmd = {
        "Id": "cmd-" + datetime.now(TZ).strftime("%Y%m%d-%H%M%S"),
        "Action": action,
        "RequestedAt": now_iso(),
        "TimeoutSec": 180,
        "Source": "solohost-core",
    }
    write_json(bus_dir() / "command.json", cmd)
    return jsonify({"ok": True, "command": cmd})


@app.post("/api/run")
def api_run():
    """Whitelist only: scan|repair|status|patrol|digest|worker."""
    body = request.get_json(silent=True) or {}
    script = str(body.get("script") or body.get("action") or "scan").strip().lower()
    allowed = {"run", "scan", "repair", "status", "patrol", "digest", "worker"}
    if script not in allowed:
        return jsonify({"ok": False, "error": "script not allowed"}), 400
    cmd = {
        "Id": "cmd-" + datetime.now(TZ).strftime("%Y%m%d-%H%M%S"),
        "Action": script.upper(),
        "Script": script,
        "RequestedAt": now_iso(),
        "TimeoutSec": 180,
        "Source": "solohost-run",
    }
    write_json(bus_dir() / "command.json", cmd)
    return jsonify({"ok": True, "command": cmd})


@app.post("/api/run-form")
def api_run_form():
    script = str(request.form.get("script") or "scan").strip().lower()
    allowed = {"run", "scan", "repair", "status", "patrol", "digest", "worker"}
    if script not in allowed:
        script = "scan"
    write_json(
        bus_dir() / "command.json",
        {
            "Id": "cmd-" + datetime.now(TZ).strftime("%Y%m%d-%H%M%S"),
            "Action": script.upper(),
            "Script": script,
            "RequestedAt": now_iso(),
            "TimeoutSec": 180,
            "Source": "solohost-form",
        },
    )
    return redirect("/")


@app.post("/api/accept-form")
def api_accept_form():
    """Accept terms only. Never try to start a Windows process from SoloHost."""
    write_json(
        data_root() / "terms_accepted.json",
        {"Accepted": True, "At": now_iso(), "Version": "2.0"},
    )
    try:
        ensure_windows_worker()
    except Exception:
        pass
    return redirect("/")


@app.post("/api/prepare-pack")
def api_prepare_pack():
    """Refresh WindowsWorker into SoloHost app root. Does not activate."""
    body = request.get_json(silent=True) or {}
    state = ensure_windows_worker(force_download=bool(body.get("force")))
    return jsonify({"ok": bool(state.get("Ready")), "pack": state})


@app.post("/api/accept-terms")
def api_accept_terms():
    """Terms gate: prepare the worker package, then let the user start it on Windows."""
    body = request.get_json(silent=True) or {}
    if not body.get("accepted"):
        return jsonify({"ok": False, "error": "terms not accepted"}), 400

    write_json(
        data_root() / "terms_accepted.json",
        {"Accepted": True, "At": now_iso(), "Version": "2.0"},
    )
    pack = ensure_windows_worker()
    return jsonify(
        {
            "ok": True,
            "termsAccepted": True,
            "pack": pack,
            "next": "worker-setup",
            "message": "Terms accepted. Start the Windows Worker using one of the methods shown.",
        }
    )


@app.get("/api/worker-check")
def api_worker_check():
    """Read-only verification. Accept only a fresh heartbeat from the Windows Worker."""
    hb = result = {}
    heartbeat_source = None
    for d in all_bus_dirs():
        candidate = read_json(d / "heartbeat.json") or {}
        if candidate and not hb:
            hb = candidate
            heartbeat_source = str(d / "heartbeat.json")
        r = read_json(d / "result.json") or {}
        if r and not result:
            result = r
    alive = worker_alive(hb)
    return jsonify({
        "ok": True,
        "workerAlive": alive,
        "workerBusy": bool(hb.get("Busy")),
        "heartbeat": hb,
        "heartbeatSource": heartbeat_source,
        "lastResult": result,
        "verifiedAt": now_iso(),
        "verification": "PASS" if alive else "WAITING",
        "reason": ("Fresh heartbeat received from Windows Worker." if alive else
                   "No fresh heartbeat received. The Worker may be running in a different Pi Network app folder or SoloHost may not be mounting that folder."),
    })

@app.post("/api/worker-heartbeat")
def api_worker_heartbeat():
    """Receive a local Windows Worker heartbeat as a second, reliable transport path."""
    body = request.get_json(silent=True) or {}
    if not body.get("Alive") or body.get("Pack") != "windows-worker":
        return jsonify({"ok": False, "error": "invalid worker heartbeat"}), 400
    hb = {
        "Alive": True,
        "Busy": bool(body.get("Busy")),
        "At": body.get("At") or now_iso(),
        "Pack": "windows-worker",
        "Note": str(body.get("Note") or ""),
        "Pid": body.get("Pid"),
        "Root": str(body.get("Root") or ""),
        "Transport": "http-localhost",
    }
    write_json(data_root() / "live" / "heartbeat.json", hb)
    return jsonify({"ok": True, "workerAlive": True, "heartbeat": hb})


@app.post("/api/activate")
def api_activate():
    """User requested activation — write bus flag only. Worker must be started on Windows."""
    state = ensure_windows_worker()
    inst = read_json(data_root() / "install_state.json") or {}
    pack = inst.get("WorkerPack") or state
    pack["Activated"] = False
    pack["ActivationRequested"] = True
    pack["ActivationRequestedAt"] = now_iso()
    write_json(data_root() / "install_state.json", {"WorkerPack": pack})
    write_json(
        bus_dir() / "command.json",
        {
            "Id": "cmd-" + datetime.now(TZ).strftime("%Y%m%d-%H%M%S"),
            "Action": "SCAN",
            "RequestedAt": now_iso(),
            "TimeoutSec": 180,
            "Source": "solohost-activate",
        },
    )
    hint = (
        "Copy/run the Worker on the Windows Node PC, then wait for a fresh heartbeat. "
        "SoloHost does not start Windows processes from the container."
    )
    return jsonify({"ok": True, "pack": pack, "hint": hint})


@app.get("/windows-worker.zip")
def download_worker_zip():
    p = bundled_zip()
    if not p or not p.is_file():
        return jsonify({"ok": False, "error": "Windows Worker package not available"}), 404
    return send_file(p, as_attachment=True, download_name="windows-worker.zip")


@app.get("/health")
def health():
    return jsonify({"ok": True, "service": "pispider-core"})


@app.get("/Activate_Worker.bat")
def download_activate_bat():
    wd = worker_dir()
    p = wd / "Activate_Worker.bat"
    if not p.is_file():
        p.write_text(
            "@echo off\r\ncd /d \"%~dp0\"\r\npowershell -NoProfile -ExecutionPolicy Bypass -File \".\\LiveWorker.ps1\"\r\n",
            encoding="utf-8",
        )
    from flask import send_file
    return send_file(p, as_attachment=True, download_name="Activate_Worker.bat")


@app.route("/win-ui/", defaults={"sub": ""})
@app.route("/win-ui/<path:sub>")
def win_ui_proxy(sub):
    """Try to pull the Windows dashboard stream into SoloHost."""
    import urllib.request
    import urllib.error
    targets = [
        f"http://host.docker.internal:18771/{sub}",
        f"http://127.0.0.1:18771/{sub}",
    ]
    last = "Windows UI not reachable on port 18771"
    for url in targets:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "PiSpider-SoloHost"})
            with urllib.request.urlopen(req, timeout=2) as resp:
                data = resp.read()
                ctype = resp.headers.get("Content-Type") or "text/html; charset=utf-8"
                from flask import Response
                return Response(data, content_type=ctype)
        except Exception as e:
            last = str(e)
    return (
        "<p>Windows dashboard stream is off.</p>"
        "<p>On Windows run Start-Worker.cmd then refresh.</p>"
        f"<pre>{last}</pre>",
        503,
    )


if __name__ == "__main__":
    c = load_cfg()
    packs_dir()
    app.run(host=c.get("Listen") or "0.0.0.0", port=int(c.get("Port") or 18770), debug=False, threaded=True)
