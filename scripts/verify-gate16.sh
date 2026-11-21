#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

plutil -lint \
  ThumbnailMaker/PrivacyInfo.xcprivacy \
  ThumbnailMaker/ThumbnailMaker.entitlements \
  ThumbnailMaker/Info.plist \
  ThumbnailMaker.xcodeproj/project.pbxproj

python3 - <<'PY'
from __future__ import annotations

import json
import plistlib
import re
import struct
import sys
from decimal import Decimal
from pathlib import Path

root = Path.cwd()
failures: list[str] = []
warnings: list[str] = []
strict_fonts = bool(int(__import__("os").environ.get("VERIFY_GATE16_STRICT_FONTS", "0")))


def check(condition: bool, message: str) -> None:
    if condition:
        print(f"PASS: {message}")
    else:
        print(f"FAIL: {message}")
        failures.append(message)


def warn(message: str) -> None:
    print(f"EXTERNAL: {message}")
    warnings.append(message)


def load_plist(relative_path: str):
    with (root / relative_path).open("rb") as handle:
        return plistlib.load(handle)


def png_metadata(path: Path) -> tuple[int, int, int, bool]:
    with path.open("rb") as handle:
        signature = handle.read(8)
        if signature != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"{path} is not a PNG")

        width = height = color_type = None
        has_trns = False

        while True:
            length_bytes = handle.read(4)
            if not length_bytes:
                break
            length = struct.unpack(">I", length_bytes)[0]
            chunk_type = handle.read(4)
            data = handle.read(length)
            handle.read(4)

            if chunk_type == b"IHDR":
                width, height, _bit_depth, color_type, _compression, _filter, _interlace = struct.unpack(
                    ">IIBBBBB",
                    data,
                )
            elif chunk_type == b"tRNS":
                has_trns = True
            elif chunk_type == b"IEND":
                break

        if width is None or height is None or color_type is None:
            raise ValueError(f"{path} is missing PNG IHDR metadata")

        return width, height, color_type, has_trns


info = load_plist("ThumbnailMaker/Info.plist")
privacy = load_plist("ThumbnailMaker/PrivacyInfo.xcprivacy")
entitlements = load_plist("ThumbnailMaker/ThumbnailMaker.entitlements")
project_text = (root / "ThumbnailMaker.xcodeproj/project.pbxproj").read_text()

check(info.get("ITSAppUsesNonExemptEncryption") is False, "Info.plist declares non-exempt encryption is not used")
check(bool(info.get("NSPhotoLibraryUsageDescription")), "Info.plist has photo-library read usage text")
check(bool(info.get("NSPhotoLibraryAddUsageDescription")), "Info.plist has photo-library add usage text")
check(isinstance(info.get("UIAppFonts"), list) and len(info["UIAppFonts"]) >= 1, "Info.plist declares bundled fonts")

for font_name in info.get("UIAppFonts", []):
    font_path = root / "ThumbnailMaker/Fonts" / font_name
    if strict_fonts:
        check(font_path.is_file(), f"bundled font exists: {font_name}")
    elif font_path.is_file():
        print(f"PASS: bundled font exists: {font_name}")
    else:
        print(f"REPO-WARN: bundled font not present in this compact workspace: {font_name}")
        warnings.append(f"bundled font not present in compact workspace: {font_name}")

check(privacy.get("NSPrivacyTracking") is False, "Privacy manifest disables tracking")
check(privacy.get("NSPrivacyTrackingDomains") == [], "Privacy manifest has no tracking domains")
check(privacy.get("NSPrivacyCollectedDataTypes") == [], "Privacy manifest declares no collected data")

accessed_reasons = {
    item.get("NSPrivacyAccessedAPIType"): set(item.get("NSPrivacyAccessedAPITypeReasons", []))
    for item in privacy.get("NSPrivacyAccessedAPITypes", [])
}
check(
    "CA92.1" in accessed_reasons.get("NSPrivacyAccessedAPICategoryUserDefaults", set()),
    "Privacy manifest declares UserDefaults reason CA92.1",
)
check(
    "C617.1" in accessed_reasons.get("NSPrivacyAccessedAPICategoryFileTimestamp", set()),
    "Privacy manifest declares File Timestamp reason C617.1",
)

for key in [
    "com.apple.security.app-sandbox",
    "com.apple.security.network.client",
    "com.apple.security.personal-information.photos-library",
    "com.apple.security.files.user-selected.read-write",
]:
    check(entitlements.get(key) is True, f"Catalyst entitlement enabled: {key}")
check("get-task-allow" not in entitlements, "Release entitlements do not include get-task-allow")

check('INFOPLIST_KEY_CFBundleDisplayName = "Thumbnail Maker";' in project_text, "Project sets display name to Thumbnail Maker")
check("PRODUCT_BUNDLE_IDENTIFIER = com.williamjiamin.ThumbnailMaker;" in project_text, "Project sets production bundle identifier")
check("MARKETING_VERSION = 1.3.0;" in project_text, "Project has non-placeholder marketing version 1.3.0")
check("CURRENT_PROJECT_VERSION = 15;" in project_text, "Project has non-placeholder build number 15")
check("SUPPORTS_MACCATALYST = YES;" in project_text, "Project supports Mac Catalyst")
check(
    '"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]" = ThumbnailMaker/ThumbnailMaker.entitlements;' in project_text,
    "Project attaches Catalyst entitlements",
)
check("get-task-allow" not in project_text, "Project does not hard-code get-task-allow")

source_text = "\n".join(
    path.read_text(errors="ignore")
    for path in (root / "ThumbnailMaker").rglob("*.swift")
)
check("PhotosPicker" in source_text, "Photo read usage is exercised by PhotosPicker")
check("PHPhotoLibrary" in source_text, "Photo add usage is exercised by PHPhotoLibrary")

restricted_patterns = [
    "volumeAvailableCapacity",
    "systemUptime",
    "mach_absolute_time",
    "activeInputModes",
]
for pattern in restricted_patterns:
    check(pattern not in source_text, f"No undeclared required-reason API usage: {pattern}")

check(not (root / "ThumbnailMaker/Config/Secrets.plist").exists(), "Release tree does not contain Secrets.plist")
check((root / "ThumbnailMaker/Config/Secrets.example.plist").is_file(), "Secrets.example.plist exists for local setup")

secret_scanned_paths = [
    root / "ThumbnailMaker",
    root / ".github",
    root / "docs",
    root / "scripts",
    root / "CONFIGURATION.md",
]
krea_scanned_paths = [
    root / "ThumbnailMaker",
    root / ".github",
    root / "CONFIGURATION.md",
]
api_key_pattern = re.compile(rb"AIza[0-9A-Za-z_-]{20,}")
krea_pattern = re.compile(rb"krea", re.IGNORECASE)
secret_hits: list[str] = []
krea_hits: list[str] = []


def iter_scannable_files(scan_root: Path):
    paths = [scan_root] if scan_root.is_file() else scan_root.rglob("*")
    for path in paths:
        if not path.is_file():
            continue
        if path.suffix.lower() in {".png", ".ttf", ".tgz", ".xcresult"}:
            continue
        yield path


for scan_root in secret_scanned_paths:
    for path in iter_scannable_files(scan_root):
        data = path.read_bytes()
        relative = str(path.relative_to(root))
        if api_key_pattern.search(data):
            secret_hits.append(relative)

for scan_root in krea_scanned_paths:
    for path in iter_scannable_files(scan_root):
        data = path.read_bytes()
        relative = str(path.relative_to(root))
        if krea_pattern.search(data):
            krea_hits.append(relative)

check(not secret_hits, "No Google API key literals in app/config/workflow/docs/script sources")
if secret_hits:
    print("Google API key literal hits:", ", ".join(secret_hits))
check(not krea_hits, "No active Krea integration in app/config/workflow sources")
if krea_hits:
    print("Krea hits:", ", ".join(krea_hits))

appicon_dir = root / "ThumbnailMaker/Resources/Assets.xcassets/AppIcon.appiconset"
contents = json.loads((appicon_dir / "Contents.json").read_text())
image_entries = contents.get("images", [])
check(any(item.get("idiom") == "ios-marketing" and item.get("filename") == "1024.png" for item in image_entries), "App icon set includes 1024 marketing icon")

for item in image_entries:
    filename = item.get("filename")
    if not filename:
        continue
    size = item.get("size", "0x0")
    scale = item.get("scale", "1x").removesuffix("x")
    try:
        expected_width = int(Decimal(size.split("x")[0]) * Decimal(scale))
        expected_height = int(Decimal(size.split("x")[1]) * Decimal(scale))
    except Exception:
        failures.append(f"Could not parse app icon size entry: {item}")
        continue

    icon_path = appicon_dir / filename
    check(icon_path.is_file(), f"app icon file exists: {filename}")
    if icon_path.is_file():
        actual_width, actual_height, color_type, has_trns = png_metadata(icon_path)
        check(
            (actual_width, actual_height) == (expected_width, expected_height),
            f"{filename} dimensions are {expected_width}x{expected_height}",
        )
        if filename == "1024.png":
            has_alpha = color_type in {4, 6} or has_trns
            check(not has_alpha, "1024 marketing icon has no alpha channel or transparency chunk")

privacy_policy = (root / "ThumbnailMaker/Resources/privacy_policy.txt").read_text(errors="ignore")
terms = (root / "ThumbnailMaker/Resources/terms_of_service.txt").read_text(errors="ignore")
check("YouTube Data API" in privacy_policy, "Privacy policy discloses YouTube Data API usage")
check("do not upload or store your images" in privacy_policy, "Privacy policy says images are not uploaded or stored on app servers")
check("Privacy Policy" in terms, "Terms refer users to privacy policy")

warn("Rotate or revoke the previously exposed YouTube Data API key in Google Cloud Console")
warn("Create a fresh restricted release API key if YouTube import ships enabled")
warn("Verify App Store Connect App Privacy answers for YouTube, StoreKit, Photos, and local storage")
warn("Verify App Store Connect export compliance answer")
warn("Verify live support URL, age rating, final screenshot upload, archive validation, and TestFlight/App Store review metadata")

if failures:
    print(f"Gate 16 repo verifier failed with {len(failures)} issue(s).", file=sys.stderr)
    sys.exit(1)

print("Gate 16 repo verifier passed. External App Store Connect and Google Cloud tasks remain manual.")
PY
