"""Record deterministic native replays, stop the complete recorder process group."""
from pathlib import Path
import json
import os
import signal
import subprocess
import sys
import time

results, udid, build_dir = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
bundle = "com.classroomboardgame.design.grasslightingreviewv2"
app = build_dir / "Build/Products/Debug-iphonesimulator/GrassLightingPrototype.app"
subprocess.run(["xcrun", "simctl", "install", udid, str(app)], check=True)
data = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", udid, bundle, "data"], text=True).strip())
trace = data / "Documents/review-replay.json"
(results / "screenshots").mkdir()
for ratio in ("16x9", "4x3"):
    # This file belongs solely to the transient, independently identified CI app.
    trace.unlink(missing_ok=True)
    video = results / f"replay-{ratio}.mp4"
    with (results / f"video-{ratio}.log").open("w") as log:
        recorder = subprocess.Popen(["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", str(video)],
                                    stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            env = dict(os.environ, SIMCTL_CHILD_PROTOTYPE_RATIO=ratio,
                       SIMCTL_CHILD_PROTOTYPE_SOURCE_COMMIT=os.environ.get("GITHUB_SHA", "local"))
            with (results / f"replay-launch-{ratio}.log").open("w") as launch_log:
                subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", udid, bundle, "--review-replay"],
                               env=env, stdout=launch_log, stderr=subprocess.STDOUT, check=True, timeout=30)
            deadline = time.monotonic() + 45
            events = []
            captured = set()
            capture_phases = {"original", "sunlight", "arrival", "local-light"}
            while time.monotonic() < deadline:
                if recorder.poll() is not None:
                    raise RuntimeError("Video recorder exited early; see video log")
                try:
                    events = json.loads(trace.read_text())
                    phase = events[-1]["phase"]
                    if phase in capture_phases and phase not in captured:
                        time.sleep(0.3)  # Allow several native draw frames after the state change.
                        subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", "--type=png",
                                        str(results / "screenshots" / f"{phase}-{ratio}.png")], check=True, timeout=15)
                        captured.add(phase)
                    if events[-1]["phase"] == "complete": break
                except (OSError, ValueError, IndexError): pass
                time.sleep(0.15)
            assert events and events[-1]["phase"] == "complete", "Native replay did not complete"
            assert captured == capture_phases, "Missing native simulator screenshot phase"
            expected_aspect = 16 / 9 if ratio == "16x9" else 4 / 3
            assert all(abs(e["viewWidth"] / e["viewHeight"] - expected_aspect) < 0.02 for e in events), "Native scene viewport aspect differs"
            middle = next(e for e in events if e["phase"] == "movement-middle")
            arrival = next(e for e in events if e["phase"] == "arrival")
            assert middle["moving"] and not arrival["moving"] and middle["heroX"] != arrival["heroX"]
            time.sleep(1)
            (results / f"replay-{ratio}.json").write_bytes(trace.read_bytes())
        finally:
            if recorder.poll() is None:
                os.killpg(recorder.pid, signal.SIGINT)
                try: recorder.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    os.killpg(recorder.pid, signal.SIGTERM)
                    recorder.wait(timeout=5)
        assert video.is_file() and video.stat().st_size > 0, "Missing native video"
        print("Native replay trace and video:", ratio, flush=True)
