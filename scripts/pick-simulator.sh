#!/usr/bin/env bash
set -euo pipefail

family="${1:-iphone}"
minimum_ios="${MIN_IOS_VERSION:-18.1}"

selection="$(python3 - "$family" "$minimum_ios" <<'PY'
import json
import re
import subprocess
import sys

family = sys.argv[1].lower()
minimum = tuple(int(part) for part in sys.argv[2].split("."))


def simctl_json(*args):
    output = subprocess.check_output(
        ["xcrun", "simctl", "list", *args, "--json"],
        text=True,
    )
    return json.loads(output)


def runtime_version_from_id(identifier):
    match = re.search(r"iOS-(\d+)(?:-(\d+))?", identifier)
    if not match:
        return None
    return (int(match.group(1)), int(match.group(2) or 0))


def version_tuple(text):
    parts = re.findall(r"\d+", text or "")
    if not parts:
        return None
    return tuple(int(part) for part in parts[:2])


def family_matches(name):
    lowered = name.lower()
    if family == "iphone-max":
        return "iphone" in lowered and (
            "pro max" in lowered or "plus" in lowered or "air" in lowered
        )
    if family == "ipad-13":
        return "ipad" in lowered and "13-inch" in lowered
    if family == "ipad":
        return "ipad" in lowered
    return "iphone" in lowered


def device_preference(name):
    lowered = name.lower()
    score = 0
    if family == "iphone-max":
        if "pro max" in lowered:
            score += 8
        if "plus" in lowered:
            score += 5
        if "air" in lowered:
            score += 4
    else:
        if "pro max" in lowered:
            score -= 2
        if "pro" in lowered:
            score -= 1
        if "plus" in lowered:
            score -= 1
    if family == "iphone" and re.search(r"iphone \d+$", lowered):
        score += 4
    if family in ("ipad", "ipad-13") and "13-inch" in lowered:
        score += 3
    if "m4" in lowered or "m5" in lowered:
        score += 2
    return score


devices = simctl_json("devices", "available")
explicit_udid = None
candidates = []

for runtime_id, available_devices in devices.get("devices", {}).items():
    version = runtime_version_from_id(runtime_id)
    for device in available_devices:
        if not device.get("isAvailable", False):
            continue

        udid = device.get("udid", "")
        name = device.get("name", "")
        if udid.upper() == family.upper():
            explicit_udid = udid

        if version is None or version < minimum:
            continue
        if not udid or not family_matches(name):
            continue
        candidates.append((version, device_preference(name), name, udid))

if explicit_udid:
    print(f"id={explicit_udid}")
    sys.exit(0)

if candidates:
    candidates.sort(key=lambda item: (item[0], item[1], item[2]), reverse=True)
    print(f"id={candidates[0][3]}")
    sys.exit(0)

runtimes = simctl_json("runtimes")
usable_runtimes = []
for runtime in runtimes.get("runtimes", []):
    if not runtime.get("isAvailable", False):
        continue

    identifier = runtime.get("identifier", "")
    platform = runtime.get("platform") or ("iOS" if "iOS" in identifier else "")
    if platform != "iOS":
        continue

    version = version_tuple(runtime.get("version")) or runtime_version_from_id(identifier)
    if version is None or version < minimum:
        continue
    usable_runtimes.append((version, runtime))

usable_runtimes.sort(key=lambda item: item[0], reverse=True)

device_type_fallback = None
for version, runtime in usable_runtimes:
    pool = [
        (device_type.get("name", ""), device_type.get("identifier", ""))
        for device_type in (runtime.get("supportedDeviceTypes") or [])
    ]
    if not pool:
        if device_type_fallback is None:
            device_types = simctl_json("devicetypes")
            device_type_fallback = [
                (device_type.get("name", ""), device_type.get("identifier", ""))
                for device_type in device_types.get("devicetypes", [])
            ]
        pool = device_type_fallback

    matches = [
        (device_preference(name), name, identifier)
        for name, identifier in pool
        if identifier and family_matches(name)
    ]
    if not matches:
        continue

    matches.sort(reverse=True)
    _, _, device_type_id = matches[0]
    new_name = f"ci-{family}-{version[0]}-{version[1]}"
    print(f"create\t{new_name}\t{device_type_id}\t{runtime.get('identifier')}")
    sys.exit(0)

print(
    f"No available {family} simulator and none could be created for iOS >= {sys.argv[2]}",
    file=sys.stderr,
)
sys.exit(1)
PY
)"

if [[ "$selection" == id=* ]]; then
  echo "platform=iOS Simulator,id=${selection#id=}"
elif [[ "$selection" == create$'\t'* ]]; then
  IFS=$'\t' read -r _ new_name device_type_id runtime_id <<< "$selection"
  echo "Creating simulator '$new_name' ($device_type_id, $runtime_id)" >&2
  udid="$(xcrun simctl create "$new_name" "$device_type_id" "$runtime_id")"
  echo "platform=iOS Simulator,id=$udid"
else
  echo "pick-simulator: unexpected selector output: $selection" >&2
  exit 1
fi
