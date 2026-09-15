"""
engine.py

The part of the Mac app that does the work. The app is the window you look
at; this is the program behind it that opens clips, hands back frames and
runs the tracker.

    python3 engine.py            # the app starts this for you

It reads one JSON command per line on stdin and writes one JSON reply per
line on stdout. Nothing else is ever written to stdout, because a single
stray print would break the app's parser. Anything worth logging goes to
stderr.

WHY A PIPE AND NOT A LOCAL WEB SERVER
webapp.py listens on a port, which is fine for a browser but means any
other program on this Mac could talk to it. A pipe belongs to the app that
started it and to nothing else, and when the app quits the pipe closes and
this program exits with it. No orphaned trackers left running.

WHY IT STILL SHELLS OUT TO main.py
Same reason webapp.py does. main.py is the tracker. If the app had its own
copy of the tracking loop, the app and the terminal could quietly disagree
about what happened in a bout, which is exactly how the browser version
went wrong. A result in the app is a result you can reproduce in Terminal.

WHY THE ENGINE HANDS THE APP ITS FRAMES
The app does not decode video itself. The frame you draw your boxes on
has to be the exact frame the tracker starts from, and on the fleche clip
a one-frame offset is enough to swap which fencer is which. I checked
this on all five benchmark clips, including starts at frames 210, 545 and
1950: the frame read_frame_at returns is byte-for-byte the frame main.py
begins tracking on. So the preview and the tracker share one decoder path.

COMMANDS
    hello                          engine and model status
    probe   path                   size and frame count from the file header
    measure path                   the true frame count, which is slow
    frame   path index             one frame, written as a JPEG
    run     path box_a box_b ...   start tracking, streams progress events
    cancel  run                    stop a run
"""

import datetime
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import threading
import time

# When the app is packaged, this file and main.py live inside one frozen
# executable, so "python main.py" is not available. The engine re-launches
# itself with --run-main instead, which runs main.py in its own process
# exactly as Terminal would. Checked before anything heavy is imported.
if len(sys.argv) > 1 and sys.argv[1] == "--run-main":
    sys.argv = ["main.py"] + sys.argv[2:]
    import main as _tracker
    try:
        _tracker.main()
    except KeyboardInterrupt:
        print("\nInterrupted.")
        sys.exit(130)
    except Exception as exc:                            # noqa: BLE001
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)
    sys.exit(0)

import cv2

HERE = os.path.dirname(os.path.abspath(__file__))
FROZEN = bool(getattr(sys, "frozen", False))
ENGINE_VERSION = 1
FRAME_CACHE = os.path.join(tempfile.gettempdir(), "riposte-frames")

_out_lock = threading.Lock()
_runs = {}
_runs_lock = threading.Lock()


def emit(payload):
    """The only way anything reaches stdout."""
    line = json.dumps(payload, separators=(",", ":"))
    with _out_lock:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()


def log(message):
    print(f"[engine] {message}", file=sys.stderr, flush=True)


def tracker_command(args):
    """How to launch main.py, packaged or not."""
    if FROZEN:
        return [sys.executable, "--run-main"] + args
    return [sys.executable, os.path.join(HERE, "main.py")] + args


# ----------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------

def cmd_hello(_msg):
    from runtrace import model_hashes
    return {
        "engine": "python",
        "engine_version": ENGINE_VERSION,
        "opencv": cv2.__version__,
        "frozen": FROZEN,
        "models": model_hashes(),
    }


def _clean_path(raw):
    # People paste paths with quotes round them, because Terminal needs
    # them. Strip rather than fail, as webapp.py does.
    raw = (raw or "").strip().strip('"').strip("'")
    return os.path.abspath(os.path.expanduser(raw))


def _video_size(path):
    cap = cv2.VideoCapture(path)
    size = (int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)),
            int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)))
    cap.release()
    return size


def cmd_probe(msg):
    """
    Size and frame count from the file header, which is instant.

    The header count can be wrong. One clip claims 127 frames and really
    has 120. That is fine for sizing a scrubber, and `measure` gets the
    true number in the background without making you wait to open a clip.
    """
    path = _clean_path(msg.get("path"))
    if not os.path.isfile(path):
        raise ValueError(f"No file at {path}")
    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        raise ValueError("OpenCV could not open that video. If it is an iPhone "
                         "HEVC or Dolby Vision clip, re-export it as H.264 .mp4.")
    info = {
        "path": path,
        "name": os.path.basename(path),
        "width": int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)),
        "height": int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)),
        "frames": max(int(cap.get(cv2.CAP_PROP_FRAME_COUNT)), 1),
        "fps": round(cap.get(cv2.CAP_PROP_FPS) or 30.0, 3),
        "size_bytes": os.path.getsize(path),
    }
    cap.release()
    return info


def cmd_measure(msg):
    """The true frame count and fps. Up to about 6 seconds on a long bout."""
    from video_io import measure_timebase
    path = _clean_path(msg.get("path"))
    measured = measure_timebase(path)
    return {"path": path, "frames": measured["frame_count"],
            "fps": round(measured["measured_fps"], 3),
            "duration_sec": round(measured["duration_sec"], 3)}


def cmd_frame(msg):
    """
    One frame as a JPEG on disk, and the path to it.

    A file rather than bytes on the pipe, because a 1080p frame is a few
    hundred kilobytes and the app can load a file without either side
    encoding it into JSON. Cached by clip and index, so scrubbing back and
    forth over the same stretch does not decode it twice.
    """
    from video_io import read_frame_at
    path = _clean_path(msg.get("path"))
    index = max(int(msg.get("index", 0)), 0)
    stat = os.stat(path)
    key = hashlib.sha1(
        f"{path}|{stat.st_size}|{stat.st_mtime_ns}".encode()).hexdigest()[:16]
    os.makedirs(FRAME_CACHE, exist_ok=True)
    target = os.path.join(FRAME_CACHE, f"{key}-{index}.jpg")

    if os.path.exists(target):
        width, height = _video_size(path)
    else:
        frame = read_frame_at(path, index)
        if frame is None:
            raise ValueError(f"There is no frame {index} in this clip.")
        ok, buffer = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 90])
        if not ok:
            raise ValueError("Could not encode that frame.")
        # Write then rename, so the app never loads a half-written file.
        partial = target + ".part"
        with open(partial, "wb") as handle:
            handle.write(buffer.tobytes())
        os.replace(partial, target)
        height, width = frame.shape[:2]

    return {"index": index, "image": target, "width": width, "height": height}


def _box(values, label):
    try:
        box = [int(round(float(v))) for v in values]
    except (TypeError, ValueError):
        raise ValueError(f"{label} is not a box.")
    if len(box) != 4 or box[2] < 8 or box[3] < 8:
        raise ValueError(f"{label} is too small. Drag a box around the mask "
                         f"and torso.")
    return box


def _summarise(trace_path):
    """What the app shows after a run, read from the trace main.py wrote."""
    import runtrace
    trace = runtrace.load(trace_path)
    frames = trace["frames"]
    n = max(len(frames), 1)
    fencers = []
    for side in (0, 1):
        tracked = [f for f in frames if f["fencers"][side]["tracked"]]
        with_pose = [f for f in tracked if f["fencers"][side]["pose"]]
        fencers.append({
            "tracked_pct": round(100.0 * len(tracked) / n, 1),
            "pose_pct": round(100.0 * len(with_pose) / max(len(tracked), 1), 1),
        })
    events = [e for e in trace["events"] if e["kind"] != "SNAP"]
    return {"frames": len(frames), "fencers": fencers, "events": events,
            "tracker": trace["header"].get("tracker")}


def cmd_run(msg):
    path = _clean_path(msg.get("path"))
    if not os.path.isfile(path):
        raise ValueError(f"No file at {path}")
    box_a = _box(msg.get("box_a"), "Fencer A's box")
    box_b = _box(msg.get("box_b"), "Fencer B's box")
    start = max(int(msg.get("start", 0)), 0)
    frames = max(int(msg.get("frames", 0)), 0)
    tracker = msg.get("tracker", "vit")
    if tracker not in ("vit", "csrt"):
        raise ValueError("tracker must be vit or csrt")

    stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    base = os.path.splitext(os.path.basename(path))[0]
    out_root = msg.get("out_dir") or os.path.expanduser("~/Movies/Riposte")
    out_dir = os.path.join(os.path.expanduser(out_root), f"{base} {stamp}")
    os.makedirs(out_dir, exist_ok=True)
    trace_path = os.path.join(out_dir, "trace.json")

    args = [path,
            "--box-a", ",".join(map(str, box_a)),
            "--box-b", ",".join(map(str, box_b)),
            "--start-frame", str(start),
            "--out-dir", out_dir,
            "--trace", trace_path,
            "--tracker", tracker,
            "--no-display", "--progress"]
    if frames:
        args += ["--max-frames", str(frames)]
    if msg.get("detect", True):
        args.append("--detect")
    if msg.get("pose", True):
        args.append("--pose")

    run_id = f"r{int(time.time() * 1000) % 100000000}"
    env = dict(os.environ, PYTHONUNBUFFERED="1")
    process = subprocess.Popen(tracker_command(args), cwd=HERE, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, bufsize=1)
    with _runs_lock:
        _runs[run_id] = {"process": process, "cancelled": False}

    def follow():
        started = time.time()
        tail = []
        for line in process.stdout:
            line = line.rstrip()
            if line.startswith("PROGRESS "):
                try:
                    _, done, total = line.split()
                    emit({"event": "progress", "run": run_id,
                          "done": int(done), "total": int(frames or total)})
                except ValueError:
                    pass
                continue
            if not line.strip() or line.startswith("[ INFO") or \
                    line.startswith("[ WARN") or "x265" in line:
                continue
            tail = (tail + [line])[-12:]
            if "LOST" in line or "WARNING" in line or "re-attached" in line:
                emit({"event": "log", "run": run_id, "line": line})
        process.wait()

        with _runs_lock:
            cancelled = _runs.get(run_id, {}).get("cancelled")
            _runs.pop(run_id, None)
        if cancelled:
            emit({"event": "cancelled", "run": run_id})
            return

        video = os.path.join(out_dir, f"{base}_tracked.mp4")
        csv_path = os.path.join(out_dir, f"{base}_tracking.csv")
        if process.returncode != 0 or not os.path.exists(video):
            emit({"event": "error", "run": run_id,
                  "error": "\n".join(tail[-6:]) or
                  f"The tracker exited with code {process.returncode}."})
            return
        try:
            summary = _summarise(trace_path)
        except Exception as exc:                        # noqa: BLE001
            summary = {"error": f"Could not read the trace: {exc}"}
        emit({"event": "done", "run": run_id, "folder": out_dir,
              "video": video, "csv": csv_path, "trace": trace_path,
              "seconds": round(time.time() - started, 1), "summary": summary})

    threading.Thread(target=follow, daemon=True).start()
    return {"run": run_id, "folder": out_dir}


def cmd_cancel(msg):
    with _runs_lock:
        entry = _runs.get(msg.get("run"))
        if entry:
            entry["cancelled"] = True
            entry["process"].terminate()
    return {"cancelled": bool(entry)}


COMMANDS = {"hello": cmd_hello, "probe": cmd_probe, "measure": cmd_measure,
            "frame": cmd_frame, "run": cmd_run, "cancel": cmd_cancel}

# Commands slow enough that answering them on the reading thread would
# stall everything else, like scrubbing while a clip is being measured.
SLOW = {"measure", "frame"}


def handle(msg):
    request_id = msg.get("id")
    name = msg.get("cmd")
    try:
        if name not in COMMANDS:
            raise ValueError(f"Unknown command {name!r}")
        result = COMMANDS[name](msg)
        emit({"id": request_id, "ok": True, **result})
    except Exception as exc:                            # noqa: BLE001
        log(f"{name} failed: {type(exc).__name__}: {exc}")
        emit({"id": request_id, "ok": False, "error": str(exc)})


def shutdown():
    """The app has gone. Take every running tracker down with us."""
    with _runs_lock:
        for entry in _runs.values():
            entry["cancelled"] = True
            try:
                entry["process"].terminate()
            except OSError:
                pass


def serve():
    log(f"ready, opencv {cv2.__version__}, frozen={FROZEN}")
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            emit({"ok": False, "error": "That line was not JSON."})
            continue
        if msg.get("cmd") in SLOW:
            threading.Thread(target=handle, args=(msg,), daemon=True).start()
        else:
            handle(msg)
    shutdown()


if __name__ == "__main__":
    serve()
