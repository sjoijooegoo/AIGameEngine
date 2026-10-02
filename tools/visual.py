"""Image regression is a change detector, never an aesthetic quality score."""
from __future__ import annotations
import argparse
import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageStat

ROOT = Path(__file__).resolve().parents[1]
BASELINES = ROOT / "tests/baselines"


def compare(current: Path, baseline: Path, diff_path: Path, policy: dict, name: str):
    if not baseline.exists():
        return {"status": "needs_review", "reason": "No approved baseline"}
    with Image.open(current) as im:
        actual = im.convert("RGB")
    with Image.open(baseline) as im:
        expected = im.convert("RGB")
    if actual.size != expected.size:
        return {"status": "fail", "reason": "Image dimensions changed"}
    for x, y, width, height in policy.get("masks", {}).get(name, []):
        for image in (actual, expected):
            ImageDraw.Draw(image).rectangle((x, y, x + width - 1, y + height - 1), fill=0)
    diff = ImageChops.difference(actual, expected)
    mae = sum(ImageStat.Stat(diff).mean) / 3
    r, g, b = diff.split()
    mask = ImageChops.lighter(ImageChops.lighter(r, g), b).point(lambda v: 255 if v > policy["pixel_threshold"] else 0)
    ratio = mask.histogram()[255] / (actual.width * actual.height)
    diff_path.parent.mkdir(parents=True, exist_ok=True)
    overlay = actual.copy()
    overlay.paste(Image.new("RGB", actual.size, "#ff3867"), mask=mask)
    overlay.save(diff_path)
    passed = ratio <= policy["max_changed_ratio"] and mae <= policy["max_mean_absolute_error"]
    return {"status": "pass" if passed else "fail", "changed_ratio": ratio, "mae": mae, "diff": str(diff_path)}


def fingerprint(ready):
    return {k: ready[k] for k in ("godot", "renderer", "gpu")}


def check_image(path: Path):
    with Image.open(path) as image:
        stats = ImageStat.Stat(image.convert("RGB"))
        return {"size": list(image.size), "mean": stats.mean, "stddev": stats.stddev, "nonblank": max(stats.stddev) > 3, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def approve(report_path: Path, reviewer: str, reason="", names=None, accept_visual_changes=False, baseline_dir=None):
    import re
    from datetime import datetime, timezone
    from lab import atomic_json
    destination = Path(baseline_dir) if baseline_dir else BASELINES
    report_path = report_path.resolve()
    report = json.loads(report_path.read_text(encoding="utf-8"))
    # Separate executable failures from expected image changes. No bypass for broken logic/capture.
    if any(c["status"] == "fail" for c in report["checks"]):
        raise ValueError("Cannot approve a report with failed executable checks")
    if not reviewer.strip():
        raise ValueError("Reviewer is required")
    visuals = {entry["name"]: entry for entry in report["visuals"]}
    selected = set(names) if names else set(visuals)
    if not selected or not selected <= visuals.keys():
        raise ValueError("Select existing visual captures")
    old_path = destination / "manifest.json"
    old = json.loads(old_path.read_text(encoding="utf-8")) if old_path.exists() else {}
    new_fingerprint = fingerprint(report["engine"])
    if old and old["fingerprint"] != new_fingerprint and not old["images"].keys() <= selected:
        raise ValueError("Changing renderer fingerprint requires reviewing every existing baseline")
    checked = {}
    for name in selected:
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", name):
            raise ValueError("Invalid baseline name")
        entry = visuals[name]
        image = check_image(Path(entry["path"]))
        if not image["nonblank"]:
            raise ValueError(f"Blank capture: {name}")
        if image["sha256"] != entry["image"]["sha256"]:
            raise ValueError(f"Capture modified since report was generated: {name}")
        if entry["comparison"]["status"] == "fail" and not (accept_visual_changes and reason.strip()):
            raise ValueError("Visual changes require --accept-visual-changes and --reason after review")
        checked[name] = image["sha256"]
    destination.mkdir(parents=True, exist_ok=True)
    for name in selected:
        temp = destination / (name + ".png.tmp")
        shutil.copyfile(visuals[name]["path"], temp)
        temp.replace(destination / (name + ".png"))
    images = dict(old.get("images", {}))
    images.update(checked)
    review = {"reviewer": reviewer, "reason": reason, "source_report": str(report_path), "images": sorted(selected), "time": datetime.now(timezone.utc).isoformat()}
    history = old.get("reviews", []) + [review]
    atomic_json(old_path, {"fingerprint": new_fingerprint, "reviewer": reviewer, "source_report": str(report_path), "images": images, "reviews": history})


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Promote explicitly reviewed captures; executable failures remain blocking")
    parser.add_argument("report", type=Path)
    parser.add_argument("--reviewer", required=True)
    parser.add_argument("--reason", default="")
    parser.add_argument("--names", nargs="+")
    parser.add_argument("--accept-visual-changes", action="store_true")
    args = parser.parse_args()
    approve(args.report, args.reviewer, args.reason, args.names, args.accept_visual_changes)
    print(BASELINES)
