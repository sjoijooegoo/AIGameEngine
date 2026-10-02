"""Rebuild the original, redistributable fixture assets. No external asset downloads."""
import io
import json
import struct
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "game/assets"


def main():
    ASSETS.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (256, 256), "#77949f")
    draw = ImageDraw.Draw(image)
    for y in range(0, 256, 32):
        for x in range(0, 256, 32):
            draw.rectangle((x, y, x + 31, y + 31), fill="#8da4aa" if (x + y) // 32 % 2 else "#627e8b")
    image.save(ASSETS / "checker.png")
    texture = Image.new("RGB", (256, 256), "#bf995d")
    d = ImageDraw.Draw(texture)
    for y in range(0, 256, 32):
        d.rectangle((0, y, 255, y + 2), fill="#513e2a")
        for x in range(8, 256, 16):
            d.line((x, y + 9, x + 8, y + 9), fill="#aa8148")
    d.rectangle((4, 4, 251, 251), outline="#29394a", width=16)
    d.rectangle((60, 88, 196, 168), fill="#e2dbc5")
    d.text((78, 107), "BANK / 001", fill="#263d50", font_size=18)
    d.text((82, 136), "UV CHECK", fill="#263d50", font_size=14)
    texture.save(ASSETS / "crate_albedo.png")
    png = io.BytesIO()
    texture.save(png, format="PNG")
    faces = [
        ((0, 0, 1), [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]),
        ((0, 0, -1), [(1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1)]),
        ((1, 0, 0), [(1, -1, 1), (1, -1, -1), (1, 1, -1), (1, 1, 1)]),
        ((-1, 0, 0), [(-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1)]),
        ((0, 1, 0), [(-1, 1, 1), (1, 1, 1), (1, 1, -1), (-1, 1, -1)]),
        ((0, -1, 0), [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)]),
    ]
    positions, normals, uvs, indices = [], [], [], []
    for i, (normal, corners) in enumerate(faces):
        for corner, uv in zip(corners, [(0, 1), (1, 1), (1, 0), (0, 0)]):
            positions.extend(v * 0.65 for v in corner)
            normals.extend(normal)
            uvs.extend(uv)
        indices.extend(i * 4 + n for n in [0, 1, 2, 0, 2, 3])
    binary, views = bytearray(), []

    def add(data, target=None):
        while len(binary) % 4:
            binary.append(0)
        view = {"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)}
        if target:
            view["target"] = target
        views.append(view)
        binary.extend(data)
        return len(views) - 1

    add(struct.pack(f"<{len(positions)}f", *positions), 34962)
    add(struct.pack(f"<{len(normals)}f", *normals), 34962)
    add(struct.pack(f"<{len(uvs)}f", *uvs), 34962)
    add(struct.pack(f"<{len(indices)}H", *indices), 34963)
    add(png.getvalue())
    gltf = {
        "asset": {"version": "2.0", "generator": "Bank Crisis Lab fixture generator"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": "InspectionCrate", "mesh": 0}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "material": 0}]}],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 24, "type": "VEC3", "min": [-0.65] * 3, "max": [0.65] * 3},
            {"bufferView": 1, "componentType": 5126, "count": 24, "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": 24, "type": "VEC2"},
            {"bufferView": 3, "componentType": 5123, "count": 36, "type": "SCALAR"},
        ],
        "materials": [{"name": "CrateWood", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "roughnessFactor": 0.85, "metallicFactor": 0}}],
        "textures": [{"source": 0}], "images": [{"bufferView": 4, "mimeType": "image/png"}],
        "bufferViews": views, "buffers": [{"byteLength": len(binary)}],
    }
    text = json.dumps(gltf, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    binary.extend(b"\0" * (-len(binary) % 4))
    payload = struct.pack("<II", len(text), 0x4E4F534A) + text + struct.pack("<II", len(binary), 0x004E4942) + binary
    (ASSETS / "inspection_crate.glb").write_bytes(struct.pack("<III", 0x46546C67, 2, 12 + len(payload)) + payload)
    print(f"Generated 3 sample assets in {ASSETS}")


if __name__ == "__main__":
    main()
