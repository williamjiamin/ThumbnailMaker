#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

python3 - <<'PY'
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

root = Path.cwd()
packet_path = Path(os.environ.get("GATE16_EVIDENCE_PACKET", "docs/GATE16_EVIDENCE_PACKET.md"))
if not packet_path.is_absolute():
    packet_path = root / packet_path

failures: list[str] = []
warnings: list[str] = []


def check(condition: bool, message: str) -> None:
    if condition:
        print(f"PASS: {message}")
    else:
        print(f"FAIL: {message}")
        failures.append(message)


def warn(message: str) -> None:
    print(f"WARN: {message}")
    warnings.append(message)


def clean(value: str) -> str:
    value = value.strip()
    if value.startswith("`") and value.endswith("`") and len(value) >= 2:
        value = value[1:-1]
    return re.sub(r"\s+", " ", value).strip()


def is_pending(value: str) -> bool:
    return clean(value).upper().startswith("PENDING")


def is_na(value: str) -> bool:
    return clean(value).upper() in {"N/A", "NA", "NOT APPLICABLE"}


def is_filled(value: str) -> bool:
    return bool(clean(value)) and not is_pending(value)


def is_http_url(value: str) -> bool:
    return bool(re.fullmatch(r"https?://\S+", clean(value)))


def evidence_path_exists(value: str) -> bool:
    normalized = clean(value)
    if not normalized:
        return False

    path = Path(os.path.expanduser(normalized))
    if path.is_absolute():
        return path.exists()
    return (root / path).exists()


def split_row(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def is_separator_row(cells: list[str]) -> bool:
    return bool(cells) and all(re.fullmatch(r":?-{3,}:?", cell.strip()) for cell in cells)


def record_unfilled(section: str, label: str, value: str) -> None:
    if is_pending(value):
        check(False, f'Unfilled cell in {section} / "{label}": still PENDING - record real evidence or N/A.')
    elif not clean(value):
        check(False, f'Unfilled cell in {section} / "{label}": value is empty.')
    else:
        print(f'PASS: Filled cell in {section} / "{label}"')


def check_evidence_reference(section: str, label: str, value: str) -> None:
    if not is_filled(value) or is_na(value):
        return

    check(
        is_http_url(value) or evidence_path_exists(value),
        f'Evidence reference in {section} / "{label}" is an http(s) URL or an existing local path',
    )


if not packet_path.is_file():
    check(False, f"Evidence packet exists at {packet_path.relative_to(root)}")
    print(f"Evidence packet verifier failed with {len(failures)} issue(s).", file=sys.stderr)
    sys.exit(1)

text = packet_path.read_text()
lines = text.splitlines()

last_updated = next((line.removeprefix("Last updated:").strip() for line in lines if line.startswith("Last updated:")), "")
status_line = next((line.removeprefix("Status:").strip() for line in lines if line.startswith("Status:")), "")

check(bool(last_updated), "Evidence packet has Last updated line")
if last_updated:
    check(bool(re.fullmatch(r"\d{4}-\d{2}-\d{2}", last_updated)), "Last updated uses YYYY-MM-DD")
check(bool(status_line), "Evidence packet has Status line")
if status_line:
    record_unfilled("Status", "Status", status_line)

sections: dict[str, list[list[str]]] = {}
current_section = ""
for line in lines:
    if line.startswith("## "):
        current_section = line.removeprefix("## ").strip()
        sections.setdefault(current_section, [])
        continue
    if current_section and line.startswith("|"):
        cells = split_row(line)
        if not is_separator_row(cells):
            sections.setdefault(current_section, []).append(cells)


def table_rows(section: str) -> list[list[str]]:
    rows = sections.get(section, [])
    return rows[1:] if rows else []


def field_table(section: str) -> dict[str, str]:
    rows = table_rows(section)
    result: dict[str, str] = {}
    for row in rows:
        if len(row) >= 2:
            result[clean(row[0])] = row[1].strip()
    return result


ledger_rows = table_rows("Evidence Ledger")
check(len(ledger_rows) == 10, "Evidence ledger has 10 external-task rows")

ledger_by_task: dict[str, dict[str, str]] = {}
for row in ledger_rows:
    if len(row) != 8:
        check(False, f"Evidence Ledger row has {len(row)} columns instead of 8: {row[0] if row else '<empty>'}")
        continue

    task, owner, date_completed, evidence, decision, _criteria, verified_by, verdict = row
    task = clean(task)
    ledger_by_task[task] = {
        "owner": owner,
        "date_completed": date_completed,
        "evidence": evidence,
        "decision": decision,
        "verified_by": verified_by,
        "verdict": verdict,
    }

    for label, value in [
        ("Owner and account/system", owner),
        ("Date completed", date_completed),
        ("Evidence link or screenshot path", evidence),
        ("Decision/value recorded", decision),
        ("Verified by/date", verified_by),
        ("Verdict", verdict),
    ]:
        record_unfilled("Evidence Ledger", f"{task} / {label}", value)

    check_evidence_reference("Evidence Ledger", f"{task} / Evidence link or screenshot path", evidence)

    normalized_date = clean(date_completed)
    check(
        bool(re.fullmatch(r"\d{4}-\d{2}-\d{2}", normalized_date)) or is_na(normalized_date),
        f'Ledger row "{task}": Date completed "{normalized_date}" is YYYY-MM-DD or N/A',
    )
    normalized_verdict = clean(verdict)
    check(
        normalized_verdict in {"PASS", "N/A"},
        f'Ledger row "{task}": verdict is PASS or N/A',
    )

google = field_table("Google Cloud Credential Evidence")
export = field_table("Export Compliance Evidence")
metadata = field_table("Metadata Evidence")
build = field_table("Screenshot And Build Evidence")
signoff = field_table("Final Gate 16 Sign-Off")

for section_name, fields in [
    ("Google Cloud Credential Evidence", google),
    ("Export Compliance Evidence", export),
    ("Metadata Evidence", metadata),
    ("Screenshot And Build Evidence", build),
    ("Final Gate 16 Sign-Off", signoff),
]:
    check(bool(fields), f"{section_name} table exists")
    for field, value in fields.items():
        record_unfilled(section_name, field, value)
        if field in {
            "Evidence screenshot/path for old credential action",
            "Evidence screenshot/path",
            "Screenshot source directory or App Store Connect evidence",
        }:
            check_evidence_reference(section_name, field, value)

old_action = clean(google.get("Old credential action", "")).lower()
check(old_action in {"disabled", "deleted", "rotated"}, 'Google Cloud: "Old credential action" is disabled, deleted, or rotated')

old_action_date = clean(google.get("Old credential action timestamp", ""))
check(bool(re.fullmatch(r"\d{4}-\d{2}-\d{2}", old_action_date)), 'Google Cloud: "Old credential action timestamp" uses YYYY-MM-DD')

youtube_enabled = clean(google.get("YouTube import ships enabled in this release", "")).lower()
check(youtube_enabled in {"yes", "no"}, 'Google Cloud: "YouTube import ships enabled in this release" is yes or no')

new_credential_fields = [
    "New release credential identifier, last four, or fingerprint",
    "New credential API restriction",
    "New credential app/referrer/bundle restriction",
    "Runtime storage location for release value",
]
new_credential_task = "Create fresh restricted release YouTube credential if YouTube import ships enabled"
if youtube_enabled == "yes":
    for field in new_credential_fields:
        check(
            is_filled(google.get(field, "")) and not is_na(google.get(field, "")),
            f'Google Cloud: "{field}" is filled because YouTube import ships enabled',
        )
    if new_credential_task in ledger_by_task:
        for label, value in ledger_by_task[new_credential_task].items():
            check(
                not is_na(value),
                f'Evidence Ledger: fresh restricted release YouTube credential "{label}" is not N/A when YouTube import ships enabled',
            )
        check(
            not is_na(ledger_by_task[new_credential_task]["verdict"]),
            'Evidence Ledger: fresh restricted release YouTube credential row is not N/A when YouTube import ships enabled',
        )
elif youtube_enabled == "no":
    if new_credential_task in ledger_by_task:
        check(
            clean(ledger_by_task[new_credential_task]["verdict"]) in {"PASS", "N/A"},
            "Evidence Ledger: fresh restricted release YouTube credential row has a valid verdict when YouTube import is disabled",
        )

check(
    clean(export.get("Matching repo value", "")) == "ITSAppUsesNonExemptEncryption = false",
    "Export compliance anchor matches repo value ITSAppUsesNonExemptEncryption = false",
)
export_answer = clean(export.get("App Store Connect export compliance answer", "")).lower()
if is_filled(export_answer):
    if not ("no" in export_answer or "non-exempt" in export_answer or "exempt" in export_answer):
        warn('Export compliance answer does not mention "No", "exempt", or "non-exempt"; manually review wording.')

expected_metadata = {
    "Bundle identifier": "com.williamjiamin.ThumbnailMaker",
    "Display name": "Thumbnail Maker",
    "Marketing version/build": "1.0.8 / 9",
}
for field, expected in expected_metadata.items():
    actual = clean(metadata.get(field, "")).replace("`", "")
    actual = re.sub(r"\s+", " ", actual).strip()
    check(actual == expected, f'Metadata "{field}" matches repo value "{expected}"')

for field in ["Support URL", "Privacy policy URL"]:
    value = clean(metadata.get(field, ""))
    check(bool(re.fullmatch(r"https?://\S+", value)), f'Metadata "{field}" is an http(s) URL')

marketing_url = clean(metadata.get("Marketing URL", ""))
check(is_na(marketing_url) or bool(re.fullmatch(r"https?://\S+", marketing_url)), 'Metadata "Marketing URL" is N/A or an http(s) URL')

release_ref = clean(build.get("Release branch/commit used for archive", ""))
check(
    bool(re.search(r"[0-9a-f]{7,40}", release_ref, re.IGNORECASE)) or bool(re.fullmatch(r"[A-Za-z0-9._/-]+", release_ref)),
    'Screenshot/build "Release branch/commit used for archive" looks like a branch or commit',
)

final_date = clean(signoff.get("Final review date", ""))
check(bool(re.fullmatch(r"\d{4}-\d{2}-\d{2}", final_date)), "Final sign-off review date uses YYYY-MM-DD")

gate_verdict = clean(signoff.get("Gate 16 verdict", ""))
check(gate_verdict == "PASS", 'Final sign-off "Gate 16 verdict" is PASS')

for field in [
    "All evidence ledger rows are non-PENDING",
    "All evidence links/screenshots are reachable by reviewer",
    "Google Cloud credential rotation/restriction evidence complete",
    "App Store Connect privacy/metadata/export compliance evidence complete",
]:
    value = clean(signoff.get(field, "")).upper()
    check(value in {"YES", "PASS"}, f'Final sign-off "{field}" is YES or PASS')

final_release_ref = clean(signoff.get("Final release branch/commit", ""))
if is_filled(final_release_ref) and is_filled(release_ref):
    if final_release_ref != release_ref and final_release_ref not in release_ref and release_ref not in final_release_ref:
        warn("Final release branch/commit differs from archive release branch/commit; confirm both refer to the same release.")

if gate_verdict == "PASS":
    check(not is_pending(status_line), "Status line is not PENDING when Gate 16 verdict is PASS")

if failures:
    print(f"Evidence packet verifier failed with {len(failures)} issue(s).", file=sys.stderr)
    sys.exit(1)

print("Gate 16 external evidence packet verifier passed.")
PY
