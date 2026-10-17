"""Exercise the isolated addon fixture through real bridge input and rendered evidence."""
import argparse
import json
import math
from pathlib import Path
import re
import time

from PIL import Image, ImageChops
from engine.core.io import atomic_json
from engine.core.paths import PROJECT_ID
from engine.tools.lab import Client
from engine.tools.sequence import build as sequence_viewer


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--headless", action="store_true")
    args = parser.parse_args()
    if PROJECT_ID != "addon_probe":
        raise ValueError("Select --project addon_probe")
    client = Client.launch(rendered=not args.headless)
    report = {"session": str(client.session), "headless": args.headless, "checks": [],
              "limitations": ["No plugin checkpoint serialization; not a bank gameplay or art acceptance", "Ramp elevation and wall camera fixture, not bank staircase locomotion coverage"]}

    def check(name, condition, detail=None):
        report["checks"].append({"name": name, "passed": bool(condition), "detail": detail})
        atomic_json(client.session / "addon-report.json", report)

    def freeze(name):
        before = client.call("state")
        if not args.headless:
            client.call("capture", name=name + "_before")
        time.sleep(0.8)
        after = client.call("state")
        check(name + "_state_frozen", before == after, {"before": before, "after": after})
        if not args.headless:
            client.call("capture", name=name + "_after")
            a = Image.open(client.session / (name + "_before.png")).convert("RGB")
            b = Image.open(client.session / (name + "_after.png")).convert("RGB")
            check(name + "_pixels_frozen", ImageChops.difference(a, b).getbbox() is None)

    try:
        initial = client.call("step", frames=45)
        check("manual_host", initial["manual_mode"] == 3)
        check("headless_disables_debug_draw" if args.headless else "rendered_debug_draw_enabled",
              initial["debug_enabled"] == (not args.headless))
        freeze("idle")
        wall = client.call("act", keys=["S"], frames=55)
        wall = client.call("step", frames=45)
        check("rear_wall_camera_collision", wall["position"][2] > 1 and wall["camera"][2] < 3.4, wall)
        if not args.headless:
            client.call("capture", name="rear_wall")
        # Move using normal W input, then capture bounded moving frames.
        client.call("act", keys=["W"], frames=85)
        if args.headless:
            moving = client.call("act", keys=["W"], frames=140)
        else:
            client.call("sequence", name="ramp_follow", count=15, interval=10, keys=["W"])
            moving = client.call("state")
            report["sequence"] = sequence_viewer(client.session / "ramp_follow.sequence.json", speed=0.25)
        check("input_moves_up_ramp", moving["position"][2] < -7 and moving["position"][1] > 1.1, moving)
        check("camera_tracks_elevation", moving["camera"][1] > initial["camera"][1] + 0.8)
        freeze("moving_damping")
        transition = client.call("act", keys=["F"], frames=1)
        check("aim_input_received", transition["aiming"])
        freeze("mid_tween")
        if not args.headless:
            client.call("sequence", name="aim_transition", count=13, interval=2)
            report["aim_sequence"] = sequence_viewer(client.session / "aim_transition.sequence.json", speed=0.25)
        else:
            client.call("step", frames=24)
        aimed = client.call("state")
        check("aim_tween_completed", math.dist(aimed["camera"], aimed["aim"]) < 0.02, aimed)
        orbited = client.call("act", mouse=[170, -35], frames=20)
        check("mouse_orbit", abs(orbited["camera_rotation"][1] - aimed["camera_rotation"][1]) > 0.1)
        if not args.headless:
            client.call("capture", name="overlay_on")
            toggled = client.call("act", keys=["G"], frames=1)
            client.call("capture", name="overlay_off")
            check("overlay_toggle", not toggled["debug_enabled"])
        try:
            client.call("checkpoint", name="unsupported")
            check("unsupported_checkpoint_rejected", False)
        except RuntimeError as error:
            check("unsupported_checkpoint_rejected", "unsupported adapter" in str(error), str(error))
    except Exception as error:
        check("harness_exception", False, repr(error))
    finally:
        client.close()
        text = (client.session / "engine.log").read_text(encoding="utf-8", errors="replace")
        check("engine_log_clean", not re.search(r"SCRIPT ERROR|^ERROR:|Parse Error", text, re.M))
        report["passed"] = all(c["passed"] for c in report["checks"])
        atomic_json(client.session / "addon-report.json", report)
        print(json.dumps({"report": str(client.session / "addon-report.json"), "passed": report["passed"], "checks": [{"name": c["name"], "passed": c["passed"]} for c in report["checks"]]}, indent=2))
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
