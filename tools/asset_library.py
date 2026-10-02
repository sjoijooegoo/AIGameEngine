"""Content-addressed asset ingestion and Godot-backed preparation; JSON is the source of truth."""
from __future__ import annotations
import base64
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import sqlite3
import struct
import threading
from urllib.parse import unquote

from PIL import Image, ImageDraw

from lab import ROOT, atomic_json, godot_path, read_json_retry
from asset_jobs import Job

CATALOG = ROOT / "asset_catalog"
SOURCES = ROOT / "asset_sources"
LIBRARY = ROOT / "game/assets/library"
PIPELINE_VERSION = 1
MUTATION_LOCK = threading.RLock()
MODEL_SUFFIXES = {".glb", ".gltf", ".fbx"}
TEXTURE_SUFFIXES = {".png", ".jpg", ".jpeg", ".tga", ".webp"}


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r"[a-z][a-z0-9_.-]{0,63}", value) or ".." in value:
        raise ValueError("ID must use lowercase letters, digits, dots, dashes or underscores (no ..)")
    return value


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def res_path(path):
    return "res://" + Path(path).resolve().relative_to(ROOT / "game").as_posix()


def fs_path(resource):
    if not resource.startswith("res://"):
        raise ValueError("Expected project resource path")
    path = (ROOT / "game" / resource[6:]).resolve()
    if not path.is_relative_to((ROOT / "game").resolve()):
        raise ValueError("Resource escapes project")
    return path


def gltf_document(path):
    if path.suffix.lower() == ".gltf":
        return json.loads(path.read_text(encoding="utf-8"))
    data = path.read_bytes()
    if len(data) < 20:
        raise ValueError("Truncated GLB")
    magic, version, length = struct.unpack_from("<III", data)
    if magic != 0x46546C67 or version != 2 or length != len(data):
        raise ValueError("Invalid GLB 2.0 header")
    chunk_length, chunk_type = struct.unpack_from("<II", data, 12)
    if chunk_type != 0x4E4F534A or 20 + chunk_length > len(data):
        raise ValueError("Invalid GLB JSON chunk")
    return json.loads(data[20:20 + chunk_length].decode("utf-8"))


def dependencies(path):
    found, missing = [], []
    warnings = []
    if path.suffix.lower() in (".gltf", ".glb"):
        doc = gltf_document(path)
        uris = [x["uri"] for key in ("images", "buffers") for x in doc.get(key, []) if "uri" in x]
    elif path.suffix.lower() == ".fbx":
        # FBX exporter-relative paths are preflight hints, not material-role guesses.
        data = path.read_bytes()
        uris = [v.decode("utf-8", errors="replace") for v in re.findall(rb'RelativeFilename:\s*"([^"\r\n]+)"', data)]
        if not uris:
            warnings.append("FBX external dependency discovery is importer-dependent; inspect imported materials and supply explicit texture roles where needed")
    else:
        uris = []
    for uri in uris:
        if uri.startswith("data:"):
            continue
        uri = unquote(uri.replace("\\", "/"))
        if ":" in uri or uri.startswith("/"):
            raise ValueError("Asset references an absolute or remote dependency: " + uri)
        target = (path.parent / uri).resolve()
        if not target.is_relative_to(path.parent.resolve()):
            raise ValueError("Dependency escapes the asset package: " + uri)
        if not target.is_file():
            missing.append(uri)
        else:
            found.append((uri, target))
    return found, sorted(set(missing)), warnings


def inspect_asset(asset_id):
    path = CATALOG / (identifier(asset_id) + ".json")
    if not path.exists():
        raise ValueError("Unknown asset: " + asset_id)
    return read_json_retry(path)


def ingest(path, asset_id, title="", tags=None, source_note="", usage="unspecified", job=None):
    job = job or Job("asset_ingest")
    with MUTATION_LOCK:
        asset_id = identifier(asset_id)
        path = Path(path).resolve()
        if not path.is_file() or path.suffix.lower() not in MODEL_SUFFIXES | TEXTURE_SUFFIXES:
            raise ValueError("Expected GLB/glTF/FBX or PNG/JPEG/TGA/WebP")
        if path.stat().st_size > 512 * 1024 * 1024:
            raise ValueError("Single input exceeds 512 MiB budget")
        deps, missing, warnings = dependencies(path)
        files = [(path.name, path)] + deps
        if sum(file.stat().st_size for _, file in files) > 512 * 1024 * 1024:
            raise ValueError("Asset package exceeds 512 MiB budget")
        hashes = {name: digest(file) for name, file in files}
        revision = canonical({"files": hashes, "missing": missing})[:16]
        target = SOURCES / asset_id / revision
        target.mkdir(parents=True, exist_ok=True)
        for name, file in files:
            job.check()
            output = target / name
            output.parent.mkdir(parents=True, exist_ok=True)
            if not output.exists():
                shutil.copyfile(file, output)
            elif digest(output) != hashes[name]:
                raise ValueError("Immutable source snapshot was modified: " + str(output))
        kind = "model" if path.suffix.lower() in MODEL_SUFFIXES else "texture"
        metadata = {"version": 1, "id": asset_id, "title": title or path.stem, "tags": sorted(set(tags or [])), "kind": kind, "revision": revision, "source": (target / path.name).relative_to(ROOT).as_posix(), "source_note": source_note, "usage": usage, "files": hashes, "missing_dependencies": missing, "warnings": warnings, "status": "blocked" if missing else "registered", "inferred": {}, "declared": {}, "preparations": {}}
        if kind == "texture":
            with Image.open(path) as image:
                if image.width*image.height > 64*1024*1024:
                    raise ValueError("Texture exceeds 64 megapixel budget")
                metadata["measured"] = {"size_px": list(image.size), "mode": image.mode, "has_alpha": "A" in image.getbands()}
        previous = CATALOG / (asset_id + ".json")
        if previous.exists():
            old = read_json_retry(previous)
            metadata["preparations"] = old.get("preparations", {})
            if old["revision"] == revision:
                for key in ("prepared", "declared", "measured", "status"):
                    if key in old:
                        metadata[key] = old[key]
        CATALOG.mkdir(exist_ok=True)
        atomic_json(previous, metadata)
        reindex()
        return metadata


def reindex():
    CATALOG.mkdir(exist_ok=True)
    with sqlite3.connect(CATALOG / "index.sqlite") as db:
        db.execute("CREATE TABLE IF NOT EXISTS assets (id TEXT PRIMARY KEY,title TEXT,tags TEXT,kind TEXT,status TEXT,revision TEXT)")
        db.execute("DELETE FROM assets")
        for path in sorted(CATALOG.glob("*.json")):
            data = read_json_retry(path)
            db.execute("INSERT INTO assets VALUES (?,?,?,?,?,?)", (data["id"], data["title"], " ".join(data["tags"]), data["kind"], data["status"], data["revision"]))


def search(query="", kind=None, status=None, limit=20):
    limit = max(1, min(int(limit), 100))
    with MUTATION_LOCK:
        reindex()
        sql = "SELECT id,title,tags,kind,status,revision FROM assets WHERE (id LIKE ? OR title LIKE ? OR tags LIKE ?)"
        pattern = "%" + query.replace("%", "") + "%"
        args = [pattern] * 3
        for name, value in (("kind", kind), ("status", status)):
            if value:
                sql += f" AND {name}=?"
                args.append(value)
        sql += " ORDER BY id LIMIT ?"
        args.append(limit)
        with sqlite3.connect(CATALOG / "index.sqlite") as db:
            db.row_factory = sqlite3.Row
            return {"assets": [dict(row) for row in db.execute(sql, args)]}


def engine(job, operation, rendered=False, **arguments):
    request = job.directory / (operation + ".request.json")
    result = job.directory / (operation + ".result.json")
    atomic_json(request, {"operation": operation, "result": str(result), **arguments})
    command = [str(godot_path()), "--path", str(ROOT / "game")]
    if not rendered:
        command.append("--headless")
    else:
        command += ["--resolution", "1280x720", "--position", "40,40"]
    command += ["--script", "res://asset_pipeline/worker.gd", "--", "--request=" + str(request)]
    job.run(command, operation)
    if not result.exists():
        raise RuntimeError("Engine did not produce a result")
    data = read_json_retry(result)
    if "error" in data:
        raise RuntimeError(data["error"])
    return data


def prepare(asset_id, unit_scale=1.0, yaw_degrees=0.0, textures=None, job=None):
    job = job or Job("asset_prepare")
    if not math.isfinite(unit_scale) or not 0.0001 <= unit_scale <= 1000 or not math.isfinite(yaw_degrees):
        raise ValueError("Invalid explicit scale or rotation")
    unit_scale=float(unit_scale)
    yaw_degrees=float(yaw_degrees)%360
    with MUTATION_LOCK:
        asset = inspect_asset(asset_id)
        if asset["missing_dependencies"]:
            raise ValueError("Missing dependencies: " + ", ".join(asset["missing_dependencies"]))
        source = ROOT / asset["source"]
        for name, expected in asset["files"].items():
            if not (source.parent / name).exists() or digest(source.parent / name) != expected:
                raise ValueError("Source snapshot missing or modified; re-ingest original package")
        roles, texture_hashes = {}, {}
        for role, texture_id in (textures or {}).items():
            if role not in ("albedo", "normal", "roughness", "metallic", "ao", "emission"):
                raise ValueError("Unsupported explicit texture role")
            texture = inspect_asset(texture_id)
            if texture["kind"] != "texture":
                raise ValueError("Texture role must reference a texture asset")
            tex_source = ROOT / texture["source"]
            if digest(tex_source) != texture["files"][tex_source.name]:
                raise ValueError("Texture source snapshot modified; re-ingest original")
            texture_hashes[role] = digest(tex_source)
            roles[role] = tex_source
        engine_version = job.run([str(godot_path()), "--version"], "engine_version").strip()
        options = {"pipeline": PIPELINE_VERSION, "worker_sha256": digest(ROOT / "game/asset_pipeline/worker.gd"), "engine": engine_version, "revision": asset["revision"], "unit_scale": unit_scale, "yaw_degrees": yaw_degrees, "texture_hashes": texture_hashes}
        key = canonical(options)[:16]
        target = LIBRARY / asset_id / key
        output = target / ("prepared.tscn" if asset["kind"] == "model" else "texture.png")
        old = asset.get("preparations", {}).get(key)
        if old and output.exists() and digest(output) == old["output_sha256"] and all((target / name).is_file() and digest(target/name)==sha for name,sha in old.get("artifact_hashes", {}).items()):
            asset["prepared"] = old
            asset["declared"] = {"unit_scale": unit_scale, "yaw_degrees": yaw_degrees, "texture_roles": textures or {}}
            asset["status"] = "prepared"
            atomic_json(CATALOG / (asset_id + ".json"), asset)
            return {"asset": asset, "cache_hit": True}
        target.mkdir(parents=True, exist_ok=True)
        job.progress("Copying source snapshot")
        for name in asset["files"]:
            destination = target / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source.parent / name, destination)
        bound_roles = {}
        for role, texture_source in roles.items():
            destination = target / ("override_" + role + texture_source.suffix)
            shutil.copyfile(texture_source, destination)
            bound_roles[role] = res_path(destination)
        if asset["kind"] == "texture":
            with Image.open(source) as image:
                image.convert("RGBA").save(output)
            measured = {"size_px": asset["measured"]["size_px"]}
        else:
            job.run([str(godot_path()), "--headless", "--path", str(ROOT / "game"), "--editor", "--import"], "import")
            measured = engine(job, "prepare", source=res_path(target / source.name), output=res_path(output), unit_scale=unit_scale, yaw_degrees=yaw_degrees, textures=bound_roles)
        job.check()
        artifact_hashes={p.relative_to(target).as_posix():digest(p) for p in target.rglob('*') if p.is_file() and p.suffix not in ('.import','.uid')}
        preparation = {"key": key, "options": options, "resource": res_path(output), "output_sha256": digest(output), "artifact_hashes":artifact_hashes,"measured": measured}
        asset["preparations"][key] = preparation
        asset["prepared"] = preparation
        asset["declared"] = {"unit_scale": unit_scale, "yaw_degrees": yaw_degrees, "texture_roles": textures or {}}
        asset["status"] = "prepared"
        atomic_json(CATALOG / (asset_id + ".json"), asset)
        reindex()
        return {"asset": asset, "cache_hit": False}


def preview_asset(asset_id, lighting="neutral", job=None):
    from asset_report import preview_report
    job = job or Job("asset_preview")
    asset = inspect_asset(asset_id)
    if "prepared" not in asset:
        raise ValueError("Prepare the asset first")
    identity = {"asset_id": asset_id, "preparation_key": asset["prepared"]["key"], "source_revision": asset["prepared"]["options"]["revision"], "resource_sha256": asset["prepared"]["output_sha256"]}
    if lighting not in ("neutral","dark","raking"):
        raise ValueError("Lighting must be neutral, dark or raking")
    if asset["kind"] == "texture":
        with Image.open(fs_path(asset["prepared"]["resource"])) as image:
            image = image.convert("RGBA")
            image.thumbnail((512, 512))
            sheet = Image.new("RGB", (image.width * 3, image.height * 2 + 50), "#d3dce0")
            draw = ImageDraw.Draw(sheet)
            for i, channel in enumerate([image.convert("RGB"), *image.split()]):
                x, y = i % 3 * image.width, i // 3 * (image.height + 25)
                sheet.paste(channel, (x, y))
                draw.text((x+4, y+image.height+4), ["RGB", "R", "G", "B", "A"][i], fill="black")
            path = job.directory / "texture_channels.png"
            sheet.save(path)
        return preview_report({**identity, "captures": [{"view": "channels", "path": str(path)}], "semantic_role": "Not inferred from filename"},job.directory,asset['title'])
    return preview_report({**identity, "lighting":lighting, **engine(job, "preview", rendered=True, source=asset["prepared"]["resource"], kind="asset", lighting=lighting, directory=str(job.directory))},job.directory,asset['title'])
