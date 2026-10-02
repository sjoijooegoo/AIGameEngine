"""Validate handoff tasks and evaluate explicit acceptance against a concrete test report."""
import argparse
import hashlib
import json
from pathlib import Path
from lab import ROOT, atomic_json


def validate(directory=None):
    directory = Path(directory) if directory else ROOT / "project"
    tasks = json.loads((directory / "tasks.json").read_text(encoding="utf-8"))
    acceptance = json.loads((directory / "acceptance.json").read_text(encoding="utf-8"))
    criteria = {c["id"]: c for c in acceptance["criteria"]}
    entries = {t["id"]: t for t in tasks["tasks"]}
    if len(criteria) != len(acceptance["criteria"]) or len(entries) != len(tasks["tasks"]):
        raise ValueError("Duplicate task or acceptance ID")
    if tasks["next_task"] not in entries:
        raise ValueError("Unknown next task")
    for criterion in criteria.values():
        if criterion["kind"] not in ("automated", "review") or not criterion["description"].strip():
            raise ValueError("Invalid acceptance criterion")
        if not criterion.get("checks" if criterion["kind"] == "automated" else "evidence"):
            raise ValueError("Acceptance requires checks or review evidence")
    for entry in entries.values():
        if entry["status"] not in ("planned", "in_progress", "done", "blocked"):
            raise ValueError("Invalid task status")
        if not entry["acceptance"] or not set(entry["acceptance"]) <= criteria.keys():
            raise ValueError("Task has missing acceptance criteria")
        if not set(entry["depends_on"]) <= entries.keys():
            raise ValueError("Task depends on unknown task")
        if entry["status"] == "done" and not entry.get("evidence"):
            raise ValueError("Completed task requires evidence references")
    def visit(key, stack):
        if key in stack:
            raise ValueError("Task dependency cycle")
        for dependency in entries[key]["depends_on"]:
            visit(dependency, stack | {key})
    for key in entries:
        visit(key, set())
    return tasks, acceptance


def evaluate(report_path, review_path=None):
    _, acceptance = validate()
    report_path = Path(report_path).resolve()
    report = json.loads(report_path.read_text(encoding="utf-8"))
    checks = {c["name"]: c for c in report["checks"]}
    review = json.loads(Path(review_path).read_text(encoding="utf-8")) if review_path else {}
    if review and Path(review.get("report", "")).resolve() != report_path:
        raise ValueError("Review belongs to a different report")
    if review and (not review.get("reviewer", "").strip() or not review.get("scope", "").strip()):
        raise ValueError("Review requires reviewer and scope")
    if review and review.get("report_sha256") != hashlib.sha256(report_path.read_bytes()).hexdigest():
        raise ValueError("Report changed since review")
    results = []
    for criterion in acceptance["criteria"]:
        if criterion["kind"] == "automated":
            states = [checks.get(name, {}).get("status", "not_run") for name in criterion["checks"]]
            status = "fail" if "fail" in states else "pass" if all(s == "pass" for s in states) else "not_run"
            detail = ", ".join(criterion["checks"])
        else:
            decision = review.get("decisions", {}).get(criterion["id"], {})
            missing = [f for f in criterion["evidence"] if not (report_path.parent / f).exists()]
            status = "not_run" if missing else "needs_review"
            if not missing and decision.get("status") in ("pass", "fail") and decision.get("notes", "").strip():
                for name in criterion["evidence"]:
                    if review.get("evidence_sha256", {}).get(name) != hashlib.sha256((report_path.parent / name).read_bytes()).hexdigest():
                        raise ValueError("Review evidence changed or lacks fingerprint: " + name)
                status = decision["status"]
            detail = decision.get("notes", "No explicit visual review") if not missing else "Missing evidence: " + ", ".join(missing)
        results.append({"id": criterion["id"], "status": status, "detail": detail})
    result = {"report": str(report_path), "reviewer": review.get("reviewer"), "scope": review.get("scope"), "criteria": results}
    atomic_json(report_path.parent / "acceptance.json", result)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--review", type=Path)
    args = parser.parse_args()
    if args.report:
        print(json.dumps(evaluate(args.report, args.review), ensure_ascii=False, indent=2))
    else:
        tasks, acceptance = validate()
        print(json.dumps({"milestone": tasks["current_milestone"], "next_task": tasks["next_task"], "tasks": tasks["tasks"], "criteria_count": len(acceptance["criteria"])}, ensure_ascii=False, indent=2))
