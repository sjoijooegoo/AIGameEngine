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


def approve(report_path: Path, reviewer: str):
    report_path = report_path.resolve()
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if report["summary"]["failed"]:
        raise ValueError("Cannot approve a report with failed checks")
    if not report["visuals"]:
        raise ValueError("Report has no visual captures")
    BASELINES.mkdir(parents=True, exist_ok=True)
    for entry in report["visuals"]:
        source = Path(entry["path"])
        if not check_image(source)["nonblank"]:
            raise ValueError(f"Blank capture: {source}")
    for entry in report["visuals"]:
        shutil.copyfile(entry["path"], BASELINES / (entry["name"] + ".png"))
    (BASELINES / "manifest.json").write_text(json.dumps({"fingerprint": fingerprint(report["engine"]), "reviewer": reviewer, "source_report": str(report_path), "images": {v["name"]: v["image"]["sha256"] for v in report["visuals"]}}, indent=2), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Explicitly promote a visually reviewed run; never call to silence a regression")
    parser.add_argument("report", type=Path)
    parser.add_argument("--reviewer", required=True)
    args = parser.parse_args()
    approve(args.report, args.reviewer)
    print(BASELINES)
