"""Local-only template and browser renderer. No external requests or publishing."""

from __future__ import annotations

import argparse
import base64
from dataclasses import asdict, dataclass
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import struct
from typing import Any, Mapping

WIDTH = 1280
HEIGHT = 720
SCHEMA = "goag.thumbnail.capture.v1"
MAX_CAPTURE_BYTES = 30 * 1024 * 1024
MAX_TITLE_CHARS = 82
SAFE_EDGE = 64
PANEL_RGB = (10, 19, 33)
PANEL_ALPHA = 0.92


class CaptureError(ValueError):
    """Invalid capture content, metadata, or private file path."""


class LayoutError(ValueError):
    """Unsafe zone, text overlap, or inadequate contrast."""


@dataclass(frozen=True)
class TemplateSpec:
    name: str
    x: int
    y: int
    width: int
    height: int
    padding_x: int = 44
    padding_y: int = 27

    def validate(self) -> None:
        if not (SAFE_EDGE <= self.x and SAFE_EDGE <= self.y):
            raise LayoutError("Text zone begins outside safe area")
        if self.x + self.width > WIDTH - SAFE_EDGE:
            raise LayoutError("Text zone crosses right safe edge")
        if self.y + self.height > HEIGHT - SAFE_EDGE:
            raise LayoutError("Text zone crosses bottom safe edge")
        if self.width - 2 * self.padding_x < 200:
            raise LayoutError("Text zone has insufficient usable width")
        if self.height - 2 * self.padding_y < 130:
            raise LayoutError("Text zone has insufficient usable height")


TEMPLATES: dict[str, TemplateSpec] = {
    "cinematic-left": TemplateSpec("cinematic-left", 76, 120, 640, 476),
    "feature-right": TemplateSpec("feature-right", 648, 120, 564, 476, 40, 28),
    "editorial-bottom": TemplateSpec("editorial-bottom", 72, 377, 1136, 271, 46, 20),
}


@dataclass(frozen=True)
class Capture:
    path: Path
    media_type: str
    metadata: dict[str, Any]
    digest: str
    raw: bytes


def _rgb_channels(color: str) -> tuple[int, int, int]:
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
        raise LayoutError("Only six-digit hexadecimal colors are allowed")
    return tuple(int(color[i : i + 2], 16) for i in (1, 3, 5))  # type: ignore[return-value]


def _luminance(channels: tuple[int, int, int]) -> float:
    linear: list[float] = []
    for component in channels:
        value = component / 255.0
        linear.append(value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4)
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def _blend(capture_rgb: tuple[int, int, int]) -> tuple[int, int, int]:
    return tuple(round(PANEL_ALPHA * panel + (1.0 - PANEL_ALPHA) * capture)
                 for capture, panel in zip(capture_rgb, PANEL_RGB))  # type: ignore[return-value]


def contrast_ratio(foreground: tuple[int, int, int], background: tuple[int, int, int]) -> float:
    l1, l2 = sorted((_luminance(foreground), _luminance(background)), reverse=True)
    return (l1 + .05) / (l2 + .05)


def check_contrast(colors: Mapping[str, str] | None = None) -> dict[str, float]:
    """WCAG ratios against both extreme capture colors beneath the scrim."""
    colors = colors or {"title": "#ffffff", "eyebrow": "#fee0a4", "subtitle": "#e4f3f6"}
    ratios: dict[str, float] = {}
    for name, css_color in colors.items():
        fg = _rgb_channels(css_color)
        ratios[name] = round(min(contrast_ratio(fg, _blend((0, 0, 0))),
                                 contrast_ratio(fg, _blend((255, 255, 255)))), 3)
        if ratios[name] < 4.5:
            raise LayoutError(f"Unsafe {name} contrast: {ratios[name]:.3f} < 4.5")
    return ratios


def validate_title(title: str, subtitle: str, eyebrow: str) -> None:
    if not title or not title.strip():
        raise LayoutError("A nonblank title is required")
    for label, value, limit in (("title", title, MAX_TITLE_CHARS), ("subtitle", subtitle, 100),
                                ("eyebrow", eyebrow, 28)):
        if len(value) > limit:
            raise LayoutError(f"{label} exceeds {limit} characters")
        if any(ord(char) < 32 or ord(char) == 127 for char in value):
            raise LayoutError(f"{label} contains control characters")


def _detect_media(raw: bytes, path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix == ".png" and raw.startswith(b"\x89PNG\r\n\x1a\n"):
        if len(raw) < 24:
            raise CaptureError("Truncated PNG")
        width, height = struct.unpack(">II", raw[16:24])
        if (width, height) != (WIDTH, HEIGHT):
            raise CaptureError("Capture PNG dimensions must be 1280x720")
        return "image/png"
    if suffix in (".jpeg", ".jpg") and raw[:3] == b"\xff\xd8\xff":
        return "image/jpeg"
    if suffix == ".webp" and raw[:4] == b"RIFF" and raw[8:12] == b"WEBP":
        return "image/webp"
    raise CaptureError("Capture must be a valid PNG, JPEG or WebP")


def _metadata_document(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_bytes()
        if len(raw) > 128 * 1024:
            raise CaptureError("Metadata exceeds size limit")
        parsed = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise CaptureError("Metadata is unreadable or invalid JSON") from exc
    if not isinstance(parsed, dict) or parsed.get("schema") != SCHEMA:
        raise CaptureError(f"Expected metadata schema {SCHEMA}")
    if parsed.get("width") != WIDTH or parsed.get("height") != HEIGHT:
        raise CaptureError("Capture metadata must declare 1280x720")
    stature = parsed.get("heroine_stature_m")
    if isinstance(stature, bool) or not isinstance(stature, (int, float)) or abs(stature - 1.680) > 0.0001:
        raise CaptureError("Expected heroine stature 1.680 m")
    focal = parsed.get("camera_focal_mm")
    if isinstance(focal, bool) or not isinstance(focal, (int, float)) or not (1.0 <= focal <= 500.0):
        raise CaptureError("Camera focal length must be between 1 and 500 mm")
    skin = parsed.get("universe_skin")
    if not isinstance(skin, str) or not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,47}", skin):
        raise CaptureError("Universe skin must be a short lowercase token")
    if parsed.get("clean_frame") is not True or parsed.get("debug_ui_hidden") is not True:
        raise CaptureError("Metadata must certify a clean frame with debug UI hidden")
    if parsed.get("frame_source") not in ("viewport", "injected_image", "synthetic_example"):
        raise CaptureError("Unknown capture source")
    if parsed.get("private_draft") is not True:
        raise CaptureError("Only private draft captures are accepted")
    return parsed


def load_capture(metadata_file: Path, capture_override: Path | None = None) -> Capture:
    metadata_file = metadata_file.resolve(strict=True)
    metadata = _metadata_document(metadata_file)
    capture_name = metadata.get("capture_file")
    if capture_override is not None:
        path = capture_override.resolve(strict=True)
    else:
        if not isinstance(capture_name, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}\.png", capture_name) or Path(capture_name).name != capture_name:
            raise CaptureError("Capture file must be a basename in metadata directory")
        path = (metadata_file.parent / capture_name).resolve(strict=True)
        if path.parent != metadata_file.parent:
            raise CaptureError("Capture file escapes metadata directory")
    try:
        if path.stat().st_size > MAX_CAPTURE_BYTES:
            raise CaptureError("Capture exceeds size limit")
        raw = path.read_bytes()
    except OSError as exc:
        raise CaptureError("Capture is unreadable") from exc
    if not raw:
        raise CaptureError("Capture is empty")
    return Capture(path=path, media_type=_detect_media(raw, path),
                   digest=hashlib.sha256(raw).hexdigest(), raw=raw, metadata=metadata)


def compose_html(capture: Capture, title: str, subtitle: str = "", eyebrow: str = "WORLD FRAME",
                 template: str = "cinematic-left") -> tuple[str, TemplateSpec, dict[str, float]]:
    validate_title(title, subtitle, eyebrow)
    if template not in TEMPLATES:
        raise LayoutError("Unknown local template")
    zone = TEMPLATES[template]
    zone.validate()
    ratios = check_contrast()
    html_source = (Path(__file__).resolve().parent / "templates" / "promo.html").read_text(encoding="utf-8")
    substitutions = {
        "__CAPTURE_DATA_URI__": "data:" + capture.media_type + ";base64," + base64.b64encode(capture.raw).decode("ascii"),
        "__ZONE_X__": str(zone.x), "__ZONE_Y__": str(zone.y),
        "__ZONE_W__": str(zone.width), "__ZONE_H__": str(zone.height),
        "__PAD_X__": str(zone.padding_x), "__PAD_Y__": str(zone.padding_y),
        "__ZONE_NAME__": html.escape(zone.name, quote=True),
        "__TITLE__": html.escape(title, quote=True),
        "__SUBTITLE__": html.escape(subtitle, quote=True),
        "__EYEBROW__": html.escape(eyebrow, quote=True),
        "__CORNER__": "PRIVATE • DRAFT", "__CAPTION__": "FRAME / 01",
        "__TITLE_SIZE__": "70" if template != "editorial-bottom" else "62",
    }
    for token, value in substitutions.items():
        html_source = html_source.replace(token, value)
    return html_source, zone, ratios


def _browser_executable(explicit: str | None) -> str | None:
    if explicit:
        path = Path(explicit).resolve()
        if not path.is_file():
            raise CaptureError("Browser executable does not exist")
        return str(path)
    # An optional local browser can be used if no managed browser has been installed.
    for name in ("chromium", "chromium-browser"):
        candidate = shutil.which(name)
        if candidate:
            return candidate
    return None


def _inspect_layout(page: Any, zone: TemplateSpec) -> dict[str, Any]:
    """Measure actual browser boxes, reducing title size until they safely fit."""
    result: dict[str, Any] = {}
    for title_size in range(70 if zone.name != "editorial-bottom" else 62, 29, -2):
        result = page.evaluate("""(size) => {
          const panel = document.querySelector('.panel');
          const title = document.querySelector('.title');
          const eyebrow = document.querySelector('.eyebrow');
          const subtitle = document.querySelector('.subtitle');
          title.style.fontSize = `${size}px`;
          const bounds = (node) => { const b = node.getBoundingClientRect();
            return {x:b.x,y:b.y,right:b.right,bottom:b.bottom,width:b.width,height:b.height}; };
          const p = bounds(panel), t = bounds(title), e = bounds(eyebrow), s = bounds(subtitle);
          return {font_size_px:size,panel:p,title:t,eyebrow:e,subtitle:s,
            fits: t.x >= p.x+25 && t.right <= p.right-24 &&
              t.y >= p.y+13 && t.bottom <= p.bottom-13 &&
              e.y >= p.y+13 && e.bottom <= t.y+1 &&
              s.y >= t.bottom-1 && s.bottom <= p.bottom-13 &&
              document.documentElement.scrollWidth === 1280 &&
              document.documentElement.scrollHeight === 720};
        }""", title_size)
        if result["fits"]:
            return result
    raise LayoutError("Text does not fit safe title zone at minimum font size")


def generate(metadata_file: Path, output_file: Path, *, title: str, subtitle: str = "",
             eyebrow: str = "WORLD FRAME", template: str = "cinematic-left",
             capture_override: Path | None = None, browser_executable: str | None = None) -> dict[str, Any]:
    """Render locally and leave the game/source files untouched."""
    if output_file.suffix.lower() != ".png":
        raise CaptureError("Output must be a .png file")
    capture = load_capture(metadata_file, capture_override)
    source, zone, ratios = compose_html(capture, title, subtitle, eyebrow, template)
    try:
        from playwright.sync_api import sync_playwright
    except ImportError as exc:
        raise CaptureError("Optional browser renderer missing; install local Playwright runtime") from exc
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as browser_driver:
        browser_args = {"headless": True}
        executable = _browser_executable(browser_executable)
        if executable is not None:
            browser_args["executable_path"] = executable
        browser = browser_driver.chromium.launch(**browser_args)
        try:
            context = browser.new_context(viewport={"width": WIDTH, "height": HEIGHT},
                                          device_scale_factor=1, reduced_motion="reduce")
            page = context.new_page()
            # The template embeds the entire capture, has no scripts or remote resources.
            page.set_content(source, wait_until="load")
            page.evaluate("document.fonts.ready")
            layout = _inspect_layout(page, zone)
            screenshot = page.locator(".canvas").screenshot(type="png", animations="disabled")
            if screenshot[16:24] != struct.pack(">II", WIDTH, HEIGHT):
                raise CaptureError("Renderer returned unexpected dimensions")
            output_file.write_bytes(screenshot)
            context.close()
        finally:
            browser.close()
    report = {
        "schema": "goag.thumbnail.render.v1", "private_draft": True,
        "output_file": output_file.name, "width": WIDTH, "height": HEIGHT,
        "template": template, "safe_title_zone": asdict(zone),
        "contrast_ratios_min_wcag": ratios, "contrast_pass": True,
        "layout_pass": True, "layout": layout, "source_capture_sha256": capture.digest,
        "source_metadata_sha256": hashlib.sha256(metadata_file.read_bytes()).hexdigest(),
        "output_sha256": hashlib.sha256(screenshot).hexdigest(),
        "capture": {key: capture.metadata[key] for key in
                    ("heroine_stature_m", "camera_focal_mm", "universe_skin", "clean_frame")},
    }
    report_file = output_file.with_suffix(".render.json")
    report_file.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Offline private thumbnail renderer")
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--subtitle", default="")
    parser.add_argument("--eyebrow", default="WORLD FRAME")
    parser.add_argument("--template", choices=sorted(TEMPLATES), default="cinematic-left")
    parser.add_argument("--capture", type=Path)
    parser.add_argument("--browser-executable")
    args = parser.parse_args(argv)
    try:
        result = generate(args.metadata, args.output, title=args.title, subtitle=args.subtitle,
                          eyebrow=args.eyebrow, template=args.template, capture_override=args.capture,
                          browser_executable=args.browser_executable)
    except (CaptureError, LayoutError, OSError) as exc:
        print(f"FAIL | thumbnail | {exc}")
        print("ALL=false")
        return 1
    print(f"PASS | 1280x720 | {args.output}")
    print(f"PASS | safe-zone | {result['template']}")
    print("PASS | contrast >=4.5 | all text")
    print("ALL=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
