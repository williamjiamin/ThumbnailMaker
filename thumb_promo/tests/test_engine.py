"""Standard-library/pytest tests; optional local browser integration."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import struct
import zlib

import pytest

from thumb_promo.engine import (
    CaptureError, LayoutError, TEMPLATES, HEIGHT, WIDTH, TemplateSpec,
    check_contrast, compose_html, generate, load_capture, validate_title,
)


def write_png(path: Path, width: int = WIDTH, height: int = HEIGHT) -> None:
    """Create a valid synthetic gradient capture without third-party assets."""
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)

    pixel_rows = bytearray()
    for y in range(height):
        pixel_rows.append(0)
        for x in range(width):
            pixel_rows.extend((int(40 + 150 * x / width), int(40 + 130 * y / height), int(80 + 90 * x / width)))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
                     chunk(b"IDAT", zlib.compress(bytes(pixel_rows), 6)) + chunk(b"IEND", b""))


@pytest.fixture()
def capture(tmp_path: Path) -> Path:
    png = tmp_path / "scene.png"
    write_png(png)
    metadata = {
        "schema": "goag.thumbnail.capture.v1", "capture_file": png.name,
        "width": WIDTH, "height": HEIGHT, "heroine_stature_m": 1.680,
        "camera_focal_mm": 50.0, "universe_skin": "neutral_day",
        "clean_frame": True, "private_draft": True,
        "frame_source": "injected_image", "debug_ui_hidden": True,
    }
    f = tmp_path / "scene.json"
    f.write_text(json.dumps(metadata), encoding="utf-8")
    return f


def test_three_safe_title_zones() -> None:
    assert set(TEMPLATES) == {"cinematic-left", "feature-right", "editorial-bottom"}
    for template in TEMPLATES.values():
        template.validate()
    with pytest.raises(LayoutError, match="safe"):
        TemplateSpec("invalid", 4, 120, 500, 400).validate()


def test_contrast_is_measured_in_both_capture_extremes() -> None:
    assert all(value >= 4.5 for value in check_contrast().values())
    with pytest.raises(LayoutError, match="Unsafe"):
        check_contrast({"title": "#323232"})


def test_load_capture_contract(capture: Path) -> None:
    parsed = load_capture(capture)
    assert parsed.path.name == "scene.png"
    assert parsed.media_type == "image/png"
    assert len(parsed.digest) == 64
    assert parsed.metadata["heroine_stature_m"] == 1.680


def test_html_escapes_user_text_and_embeds_capture(capture: Path) -> None:
    html, zone, ratios = compose_html(load_capture(capture), "<script>bad</script>",
                                     "Note & details", "LOCAL", "feature-right")
    assert "&lt;script&gt;bad&lt;/script&gt;" in html
    assert "<script>bad</script>" not in html
    assert "Note &amp; details" in html
    assert "data:image/png;base64," in html
    assert zone.name == "feature-right"
    assert ratios["title"] >= 4.5
    assert "https://" not in html and "http://" not in html


def test_rejects_metadata_traversal_and_untrusted_flag(capture: Path) -> None:
    metadata = json.loads(capture.read_text())
    metadata["capture_file"] = "../other.png"
    capture.write_text(json.dumps(metadata))
    with pytest.raises(CaptureError, match="basename"):
        load_capture(capture)
    metadata["capture_file"] = "scene.png"
    metadata["private_draft"] = False
    capture.write_text(json.dumps(metadata))
    with pytest.raises(CaptureError, match="private"):
        load_capture(capture)


def test_rejects_invalid_stature_focal_or_skin(capture: Path) -> None:
    valid = json.loads(capture.read_text())
    for key, invalid in (("heroine_stature_m", 1.607), ("camera_focal_mm", 0.0),
                         ("universe_skin", "../outside"), ("clean_frame", False), ("debug_ui_hidden", False)):
        metadata = dict(valid)
        metadata[key] = invalid
        capture.write_text(json.dumps(metadata))
        with pytest.raises(CaptureError):
            load_capture(capture)


def test_rejects_unbounded_title_and_controls() -> None:
    with pytest.raises(LayoutError):
        validate_title(" ", "", "LOCAL")
    with pytest.raises(LayoutError):
        validate_title("x" * 83, "", "LOCAL")
    with pytest.raises(LayoutError):
        validate_title("bad\nline", "", "LOCAL")


@pytest.mark.parametrize("template,title,subtitle", [
    ("cinematic-left", "EXPLORE THE UNKNOWN", "A new frame from the world"),
    ("feature-right", "LIGHT AND LAND", "Capture showcase"),
    ("editorial-bottom", "INTO THE CITY", "A clean promotional frame"),
])
def test_local_browser_render_png_with_safe_layout(
    capture: Path, tmp_path: Path, template: str, title: str, subtitle: str
) -> None:
    pytest.importorskip("playwright")
    if not (shutil.which("chromium") or shutil.which("chromium-browser")):
        pytest.skip("No local browser executable")
    out = tmp_path / (template + ".png")
    report = generate(capture, out, title=title, subtitle=subtitle, template=template)
    assert out.read_bytes()[:8] == b"\x89PNG\r\n\x1a\n"
    assert struct.unpack(">II", out.read_bytes()[16:24]) == (WIDTH, HEIGHT)
    assert report["layout_pass"] and report["contrast_pass"]
    assert report["layout"]["fits"]
    assert report["safe_title_zone"]["name"] == template
    assert json.loads(out.with_suffix(".render.json").read_text())["private_draft"] is True


def test_rejects_dimensions_mismatch_even_if_metadata_claims_1280(capture: Path) -> None:
    write_png(capture.parent / "scene.png", 640, 360)
    with pytest.raises(CaptureError, match="dimensions"):
        load_capture(capture)


def test_canonical_schema_contract() -> None:
    schema_path = Path(__file__).parents[1] / "schema" / "capture.v1.schema.json"
    schema = json.loads(schema_path.read_text())
    assert schema["$id"] == "goag.thumbnail.capture.v1"
    assert schema["properties"]["width"]["const"] == WIDTH
    assert schema["properties"]["height"]["const"] == HEIGHT
    assert schema["properties"]["heroine_stature_m"]["const"] == 1.68
    assert "debug_ui_hidden" in schema["required"]
    assert "private_draft" in schema["required"]


def test_long_title_adaptively_shrinks_to_zone(capture: Path, tmp_path: Path) -> None:
    pytest.importorskip("playwright")
    if not (shutil.which("chromium") or shutil.which("chromium-browser")):
        pytest.skip("No local browser executable")
    output_file = tmp_path / "overflow.png"
    report = generate(capture, output_file, title="W" * 82, subtitle="small subtitle",
                      template="feature-right")
    assert output_file.exists()
    assert report["layout"]["fits"]
    assert report["layout"]["font_size_px"] < 70
