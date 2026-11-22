"""Create an offline synthetic example, not content taken from the game."""

from __future__ import annotations

import json
from pathlib import Path
import struct
import zlib


def make_demo(destination: Path) -> Path:
    destination.mkdir(parents=True, exist_ok=True)
    width, height = 1280, 720
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend((int(20 + x * .12), int(48 + y * .14), int(85 + (width - x) * .05)))

    def chunk(name: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data) & 0xffffffff)

    frame = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
             + chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b""))
    (destination / "demo_frame.png").write_bytes(frame)
    metadata = {
        "schema": "goag.thumbnail.capture.v1", "capture_file": "demo_frame.png",
        "width": width, "height": height, "heroine_stature_m": 1.680,
        "camera_focal_mm": 35.0, "universe_skin": "neutral_day",
        "clean_frame": True, "debug_ui_hidden": True, "private_draft": True,
        "frame_source": "synthetic_example"
    }
    path = destination / "demo_frame.json"
    path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


if __name__ == "__main__":
    import sys
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("demo_output")
    print(make_demo(target))
