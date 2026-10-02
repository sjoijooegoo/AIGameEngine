"""Run real Godot input scenarios, rendered captures, asset audits and visual regressions."""
from __future__ import annotations

import argparse
import html
import json
from pathlib import Path
import re
import sys
import time
import traceback

from lab import Client, ROOT, atomic_json
from visual import BASELINES, check_image, compare, fingerprint


def lookup(data, path):
    for key in path.split("."):
        data = data[int(key)] if isinstance(data, list) else data[key]
    return data


def assert_state(data, assertion):
    actual = lookup(data, assertion["path"])
    expected = assertion["value"]
    operation = assertion.get("op", "eq")
    if operation == "eq":
        ok = actual == expected
    elif operation == "near":
        ok = abs(actual - expected) <= assertion.get("tolerance", 0.01)
    elif operation == "gte":
        ok = actual >= expected
    elif operation == "lt":
        ok = actual < expected
    elif operation == "contains":
        ok = expected in actual
    elif operation == "length":
        ok = len(actual) == expected
    else:
        raise ValueError(f"Unknown assertion operation {operation}")
    if not ok:
        raise AssertionError(f"{assertion['path']}: expected {operation} {expected!r}; actual {actual!r}")


def check_ui(data):
    errors = []
    for name, control in data["controls"].items():
        if not control["visible"]:
            continue
        if not control["inside_viewport"]:
            errors.append(name + " extends outside viewport")
        minimum = control.get("minimum_size", [0, 0])
        rect = control["rect"]
        if minimum[0] > rect[2] + 1 or minimum[1] > rect[3] + 1:
            errors.append(name + " is smaller than its text minimum")
    if errors:
        raise AssertionError("; ".join(errors))


def check_assets(audit):
    assert audit["mesh_count"] >= 20, "Scene appears incomplete"
    imported = [m for m in audit["meshes"] if "ImportedCrate" in m["path"]]
    assert imported, "Imported GLB is missing"
    textured = []
    for mesh in audit["meshes"]:
        assert max(mesh["aabb_size"]) > 0, f"Empty mesh: {mesh['path']}"
        for surface in mesh["surfaces"]:
            assert surface["material"] != "MISSING", f"Missing material: {mesh['path']}"
            assert surface["vertices"] > 0, f"No vertices: {mesh['path']}"
            if "albedo_texture" in surface:
                textured.append(surface)
                assert surface["uv_count"] == surface["vertices"], f"UV channel missing: {mesh['path']}"
                assert surface["albedo_texture"]["width"] >= 64, f"Unexpected tiny texture: {mesh['path']}"
    assert len(textured) >= 2, "Expected floor and GLB albedo textures"
    return {"meshes": audit["mesh_count"], "textured_surfaces": len(textured)}


def write_report(report, directory):
    report["summary"] = {
        "passed": sum(c["status"] == "pass" for c in report["checks"]),
        "failed": sum(c["status"] == "fail" for c in report["checks"]) + sum(v["comparison"]["status"] == "fail" for v in report["visuals"]),
        "visual_passed": sum(v["comparison"]["status"] == "pass" for v in report["visuals"]),
        "visual_needs_review": sum(v["comparison"]["status"] == "needs_review" for v in report["visuals"]),
    }
    atomic_json(directory / "report.json", report)
    esc = html.escape
    checks = "".join(f'<tr><td class="{c["status"]}">{c["status"]}</td><td>{esc(c["name"])}</td><td>{esc(c.get("detail", ""))}</td></tr>' for c in report["checks"])
    figures = []
    for visual in report["visuals"]:
        status = visual["comparison"]["status"]
        image_name = Path(visual["path"]).name
        baseline = visual.get("baseline")
        diff = visual["comparison"].get("diff")
        links = f'<a href="{esc(image_name)}">原图</a> · <a href="{esc(image_name.replace(".png", ".state.json"))}">场景状态</a>'
        if diff:
            links += f' · <a href="{esc(Path(diff).name)}">差异标记</a>'
        if baseline:
            links += f' · <a href="{esc(Path(baseline).name)}">基准图</a>'
        figures.append(f'<figure><a href="{esc(image_name)}"><img loading="lazy" src="{esc(image_name)}" alt="{esc(visual["name"])}"></a><figcaption><strong>{esc(visual["name"])}</strong><span class="{status}">{status}</span><p>{links}</p><small>{esc(json.dumps(visual["comparison"], ensure_ascii=False))}</small></figcaption></figure>')
    summary = report["summary"]
    page = f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>银行危机 · 开发测试报告</title>
<style>
:root{{color-scheme:light}}*{{box-sizing:border-box}}body{{margin:0;background:#edf1f4;color:#183244;font:16px/1.6 "Microsoft YaHei",sans-serif}}header{{background:#183e54;color:#fff;padding:40px max(24px,calc((100vw - 1280px)/2))}}h1{{font-size:30px;font-weight:600;margin:0 0 12px}}header p{{max-width:72ch;margin:8px 0;color:#d0e1eb}}main{{max-width:1328px;margin:auto;padding:24px}}.summary{{display:flex;gap:24px;flex-wrap:wrap;background:#fff;padding:16px 24px;border-left:5px solid #286888}}.summary b{{font-size:26px;margin-right:6px}}h2{{font-size:22px;margin-top:32px}}table{{border-collapse:collapse;background:#fff;width:100%;font-size:14px}}td,th{{padding:12px;text-align:left;border-bottom:1px solid #d9e3ea;overflow-wrap:anywhere}}td:first-child{{width:90px}}.pass{{color:#206349}}.fail{{color:#aa273c}}.needs_review{{color:#916008}}.gallery{{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,480px),1fr));gap:24px}}figure{{margin:0;background:#fff}}img{{width:100%;display:block}}figcaption{{padding:16px}}figcaption>span{{float:right}}small{{display:block;overflow-wrap:anywhere;color:#526674}}a{{color:#17658b}}a:focus-visible{{outline:3px solid #b37320;outline-offset:3px}}pre{{white-space:pre-wrap;overflow-wrap:anywhere;font-size:13px}}footer{{margin:30px 0}}@media(max-width:700px){{header{{padding:24px}}main{{padding:16px}}td{{padding:8px}}h1{{font-size:25px}}}}
</style><header><h1>银行危机 · 开发测试报告</h1><p>输入回放、玩法断言与渲染证据。截图比较用于发现变化；美术质量、可读性和操作手感需要结合审阅判断。</p><p>{esc(report['engine'].get('godot','unknown'))} / {esc(report['engine'].get('gpu','unknown'))}</p></header><main>
<div class="summary"><span><b>{summary['passed']}</b>检查通过</span><span><b>{summary['failed']}</b>失败</span><span><b>{summary['visual_passed']}</b>视觉回归通过</span><span><b>{summary['visual_needs_review']}</b>画面待审阅</span></div>
<h2>操作与逻辑</h2><table><thead><tr><th>结果</th><th>检查项</th><th>证据 / 原因</th></tr></thead><tbody>{checks}</tbody></table>
<h2>视觉检查台</h2><div class="gallery">{''.join(figures)}</div>
<footer><a href="report.json">完整 JSON 报告</a> · <a href="trace.jsonl">输入回放</a> · <a href="engine.log">引擎日志</a><p>未验证范围：操作系统焦点与实体设备、主观美术评分、生产模型骨骼动画、完整原游戏流程、长期性能表现。</p></footer></main></html>'''
    (directory / "report.html").write_text(page, encoding="utf-8")


def run(headless=False, cases_path=None):
    client = Client.launch(rendered=not headless)
    report = {"engine": json.loads((client.session / "ready.json").read_text()), "session": str(client.session), "checks": [], "visuals": [], "source": {}}
    import hashlib
    for path in sorted((ROOT / "game").rglob("*")):
        if path.is_file() and ".godot" not in path.parts and path.suffix in (".gd", ".tscn", ".godot", ".glb", ".png"):
            report["source"][str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    policy = json.loads((ROOT / "tests/visual_policy.json").read_text())
    manifest_path = BASELINES / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}

    def check(name, fn):
        started = time.monotonic()
        try:
            detail = fn()
            report["checks"].append({"name": name, "status": "pass", "detail": str(detail or ""), "seconds": time.monotonic() - started})
            print("PASS", name, flush=True)
        except Exception as error:
            report["checks"].append({"name": name, "status": "fail", "detail": str(error), "traceback": traceback.format_exc()})
            print("FAIL", name, error, flush=True)
            if not headless:
                try:
                    client.call("capture", name="failure_" + name)
                except Exception:
                    pass
            if isinstance(error, TimeoutError):
                raise

    def capture(name):
        result = client.call("capture", name=name)
        path = Path(result["path"])
        image = check_image(path)
        assert image["nonblank"], f"Blank frame: {name}"
        baseline = BASELINES / (name + ".png")
        if manifest and manifest.get("fingerprint") != fingerprint(report["engine"]):
            comparison = {"status": "needs_review", "reason": "Engine/GPU/renderer differs from approved baseline"}
        else:
            comparison = compare(path, baseline, client.session / (name + "_diff.png"), policy, name)
        entry = {"name": name, "path": str(path), "image": image, "comparison": comparison}
        if baseline.exists():
            import shutil
            copied = client.session / (name + "_baseline.png")
            shutil.copyfile(baseline, copied)
            entry["baseline"] = str(copied)
        report["visuals"].append(entry)

    try:
        cases = json.loads((cases_path or ROOT / "tests/scenarios.json").read_text(encoding="utf-8"))
        for case in cases:
            def execute(case=case):
                for index, step in enumerate(case["steps"]):
                    state = client.call(step["command"], **step.get("args", {}))
                    for assertion in step.get("assert", []):
                        try:
                            assert_state(state, assertion)
                        except Exception as error:
                            atomic_json(client.session / (case["name"] + "_failure.json"), {"step": index, "state": state, "assertion": assertion})
                            raise AssertionError(f"step {index}: {error}") from error
                return case["description"]
            check(case["name"], execute)

        def deterministic():
            results = []
            for _ in range(2):
                client.call("reset", fixture="npc_chase")
                results.append(client.call("step", frames=120))
            for path in ("player.position.0", "player.position.2", "player.hp", "npc.position.0", "npc.position.2", "npc.attacks"):
                assert_state(results[1], {"path": path, "op": "near", "value": lookup(results[0], path), "tolerance": 0.0001})
        check("repeatability", deterministic)
        audit = client.call("audit")
        atomic_json(client.session / "asset-audit.json", audit)
        check("model_material_texture_audit", lambda: check_assets(audit))

        def invalid_input():
            for command, args in [("act", {"frames": 601}), ("reset", {"fixture": "unknown"}), ("click", {"control": "save"})]:
                try:
                    client.call(command, **args)
                except RuntimeError:
                    continue
                raise AssertionError(f"Invalid {command} was accepted")
        client.call("reset")
        check("bridge_validation", invalid_input)

        if not headless:
            client.call("reset", fixture="gallery")
            client.call("step", frames=2)
            for view in ("overview", "materials", "model", "npc"):
                client.call("view", name=view, hud=False)
                check("capture_" + view, lambda view=view: capture(view))
            for angle in (90, 180, 270):
                client.call("view", name="model", orbit_degrees=angle, hud=False)
                check(f"model_orbit_{angle}", lambda angle=angle: capture(f"model_{angle}"))
            client.call("view", name="player", hud=True)
            for width, height in ((1280, 720), (1024, 768), (1920, 1080), (800, 600)):
                client.call("resize", width=width, height=height)
                for screen in ("gameplay", "inventory", "pause"):
                    client.call("reset")
                    if screen != "gameplay":
                        client.call("act", keys=["TAB" if screen == "inventory" else "ESC"], frames=1)
                    name = f"ui_{screen}_{width}x{height}"
                    check(name + "_bounds", lambda: check_ui(client.call("ui")))
                    def sized_capture(name=name, width=width, height=height):
                        capture(name)
                        assert report["visuals"][-1]["image"]["size"] == [width, height], "Render size was clamped or changed"
                    check(name, sized_capture)
        else:
            report["visual_skipped"] = "Headless mode cannot validate rendered appearance"
    except Exception as error:
        report["checks"].append({"name": "runner", "status": "fail", "detail": str(error), "traceback": traceback.format_exc()})
    finally:
        try:
            client.close()
        except Exception as error:
            report["checks"].append({"name": "shutdown", "status": "fail", "detail": str(error)})
        log = (client.session / "engine.log").read_text(encoding="utf-8", errors="replace")
        errors = [line for line in log.splitlines() if re.search(r"SCRIPT ERROR|^ERROR:|Parse Error|Invalid call", line)]
        report["checks"].append({"name": "engine_errors", "status": "fail" if errors else "pass", "detail": "\n".join(errors)})
        write_report(report, client.session)
        atomic_json(ROOT / "artifacts/latest-report.json", {"report": str(client.session / "report.json"), "html": str(client.session / "report.html")})
        print(client.session / "report.html", flush=True)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--allow-unreviewed", action="store_true", help="Return 0 for missing visual baselines while keeping needs_review in report")
    parser.add_argument("--cases", type=Path)
    args = parser.parse_args()
    result = run(headless=args.headless, cases_path=args.cases)
    sys.exit(1 if result["summary"]["failed"] else 2 if result["summary"]["visual_needs_review"] and not args.allow_unreviewed else 0)
