#!/usr/bin/env python3
"""Run one bounded Codex worker at a time against the improvement backlog.

Requires Python 3.10+ and an authenticated `codex` on PATH. No model override.
Dry run is read-only. Actual runs write checkpoints beside this script.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import fcntl
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time


REVIEW_PATH = Path("docs/review-2026-09-07")
VALID_STATUSES = {"todo", "in_progress", "blocked", "done"}
NO_PROGRESS_LIMIT = 2


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def read_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def atomic_json(path: Path, value: dict) -> None:
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)  # Only the temporary file created by this call.


def load_backlog(path: Path) -> dict:
    backlog = read_json(path)
    if not isinstance(backlog, dict) or "version" not in backlog:
        raise ValueError("Backlog must be an object with version and tasks.")
    tasks = backlog.get("tasks")
    if not isinstance(tasks, list):
        raise ValueError("Backlog tasks must be an array.")
    ids = set()
    for task in tasks:
        if not isinstance(task, dict):
            raise ValueError("Every backlog task must be an object.")
        task_id = task.get("id", "")
        if not isinstance(task_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", task_id):
            raise ValueError("Task IDs must contain only letters, digits, hyphens, underscores.")
        if task_id in ids:
            raise ValueError(f"Duplicate task ID: {task_id}")
        ids.add(task_id)
        if task.get("status") not in VALID_STATUSES:
            raise ValueError(f"Invalid task status: {task_id}")
        if type(task.get("priority")) is not int or not 0 <= task["priority"] <= 3:
            raise ValueError(f"Task priority must be an integer from 0 to 3: {task_id}")
        criteria = task.get("acceptance_criteria")
        if (not isinstance(criteria, list) or not criteria
                or any(not isinstance(c, str) or not c.strip() for c in criteria)
                or len(criteria) != len(set(criteria))):
            raise ValueError(f"Task needs unique, nonempty acceptance_criteria strings: {task_id}")
        if not isinstance(task.get("depends_on"), list):
            raise ValueError(f"Task depends_on must be an array: {task_id}")
        if not isinstance(task.get("loop", {}), dict):
            raise ValueError(f"Task loop metadata must be an object: {task_id}")
    for task in tasks:
        if any(not isinstance(dep, str) or dep not in ids or dep == task["id"]
               for dep in task["depends_on"]):
            raise ValueError(f"Unknown or self-referencing dependency: {task['id']}")
    pending = {task["id"]: set(task["depends_on"]) for task in tasks}
    resolved = set()
    while pending:
        ready = {task_id for task_id, dependencies in pending.items() if dependencies <= resolved}
        if not ready:
            raise ValueError("Backlog contains a dependency cycle.")
        resolved.update(ready)
        pending = {task_id: dependencies for task_id, dependencies in pending.items() if task_id not in ready}
    return backlog


def select_task(backlog: dict) -> dict | None:
    done = {task["id"] for task in backlog["tasks"] if task["status"] == "done"}
    ready = [task for task in backlog["tasks"]
             if task["status"] in {"todo", "in_progress"}
             and all(dep in done for dep in task["depends_on"])]
    return min(ready, key=lambda task: task["priority"]) if ready else None


def update_task(path: Path, task_id: str, **fields) -> dict:
    # Reload to preserve unrelated edits made since the preceding checkpoint.
    backlog = load_backlog(path)
    task = next(task for task in backlog["tasks"] if task["id"] == task_id)
    task.update(fields)
    atomic_json(path, backlog)
    return task


def append_event(path: Path, **event) -> None:
    # Metadata only. Raw CLI output is deliberately never captured.
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"at": now(), **event}) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def validate_result(result: dict, task: dict) -> dict:
    if not isinstance(result, dict):
        raise ValueError("Worker result is not an object.")
    required = {"status", "task_id", "summary", "evidence", "acceptance_checks", "next_action"}
    if set(result) != required or result["task_id"] != task["id"]:
        raise ValueError("Worker result fields or task_id do not match.")
    if result["status"] not in {"completed", "blocked", "continue"}:
        raise ValueError("Worker result has an invalid status.")
    if not isinstance(result["summary"], str) or not result["summary"].strip():
        raise ValueError("Worker result is missing a summary.")
    if not isinstance(result["next_action"], str):
        raise ValueError("Worker next_action must be a string.")
    evidence = result["evidence"]
    if not isinstance(evidence, list) or any(not isinstance(e, str) or not e.strip() for e in evidence):
        raise ValueError("Worker evidence must be an array of nonempty strings.")
    checks = result["acceptance_checks"]
    if not isinstance(checks, list):
        raise ValueError("Worker acceptance_checks must be an array.")
    seen = set()
    for check in checks:
        if (not isinstance(check, dict) or set(check) != {"criterion", "verified", "evidence"}
                or not isinstance(check["criterion"], str)
                or check["criterion"] not in task["acceptance_criteria"]
                or check["criterion"] in seen
                or type(check["verified"]) is not bool
                or not isinstance(check["evidence"], str)
                or (check["verified"] and not check["evidence"].strip())):
            raise ValueError("Worker acceptance check is invalid or unsupported.")
        seen.add(check["criterion"])
    if result["status"] == "completed" and (
        not evidence or seen != set(task["acceptance_criteria"])
        or not all(check["verified"] for check in checks)
    ):
        raise ValueError("Completion requires evidence and verified checks for every criterion.")
    return result


def stop_worker(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=5)
    except ProcessLookupError:
        return
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=5)


def run_worker(command: list[str], prompt: str, timeout: float) -> tuple[int | None, str | None]:
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, text=True, start_new_session=True)
    try:
        process.communicate(input=prompt, timeout=timeout)
        return process.returncode, None
    except subprocess.TimeoutExpired:
        stop_worker(process)
        return None, "iteration_timeout"
    except BaseException:
        stop_worker(process)
        raise


def run(args: argparse.Namespace) -> int:
    project = args.project.expanduser().resolve()
    review = project / REVIEW_PATH
    backlog_path = review / "backlog.json"
    plan_path = review / "IMPLEMENTATION_PLAN.md"
    prompt_path = review / "LOOP_PROMPT.md"
    schema_path = review / "result-schema.json"
    for path in (backlog_path, plan_path, prompt_path, schema_path):
        if not path.is_file():
            raise ValueError(f"Required workflow file is missing: {path}")
    backlog = load_backlog(backlog_path)
    read_json(schema_path)
    task = select_task(backlog)
    if args.dry_run:
        print(json.dumps({"dry_run": True, "project": str(project),
                          "next_task": task["id"] if task else None,
                          "max_iterations": args.max_iterations, "max_hours": args.max_hours,
                          "iteration_timeout": args.iteration_timeout,
                          "max_attempts_per_task": args.max_attempts,
                          "command": ["codex", "-a", "never", "exec", "-s", "workspace-write",
                                      "--cd", str(project), "--output-schema", str(schema_path),
                                      "-o", "<private result file>", "-"]}, indent=2))
        return 0
    executable = shutil.which("codex")
    if not executable:
        raise ValueError("codex is not on PATH; install/authenticate it before starting the loop.")

    lock_fd = os.open(review / ".loop.lock", os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(lock_fd, "r+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError("Another loop holds this project's lock.") from None
        state = review / "loop-state"
        state.mkdir(mode=0o700, exist_ok=True)
        event_path = state / "events.jsonl"
        deadline = time.monotonic() + args.max_hours * 3600
        completed = 0
        iterations = 0
        while iterations < args.max_iterations and time.monotonic() < deadline:
            backlog = load_backlog(backlog_path)
            task = select_task(backlog)
            if task is None:
                break  # Blocked dependencies never make downstream tasks eligible.
            task_id = task["id"]
            metadata = dict(task.get("loop", {}))
            attempts = int(metadata.get("attempts", 0))
            if attempts >= args.max_attempts:
                update_task(backlog_path, task_id, status="blocked", last_result={
                    "status": "blocked", "task_id": task_id,
                    "summary": "Per-task attempt limit reached; review checkpoints before retrying.",
                    "evidence": [], "acceptance_checks": [],
                    "next_action": "Resolve the issue, then reset status to todo and remove loop metadata."})
                append_event(event_path, event="attempt_limit", task_id=task_id)
                continue

            iterations += 1
            attempts += 1
            metadata.update(attempts=attempts, last_started_at=now())
            task = update_task(backlog_path, task_id, status="in_progress", loop=metadata)
            append_event(event_path, event="started", task_id=task_id, attempt=attempts)
            print(f"Starting {task_id}, attempt {attempts}/{args.max_attempts}", flush=True)
            prompt = (prompt_path.read_text(encoding="utf-8")
                      + "\n\n--- IMPLEMENTATION PLAN ---\n" + plan_path.read_text(encoding="utf-8")
                      + "\n\n--- SELECTED TASK ---\n" + json.dumps(task, indent=2)
                      + "\n\n--- DEPENDENCY STATUS ---\n"
                      + json.dumps([{ "id": item["id"], "status": item["status"] }
                                    for item in backlog["tasks"]], indent=2))
            fd, temporary = tempfile.mkstemp(prefix=f".{task_id}-", suffix=".json", dir=state)
            os.close(fd)
            output_path = Path(temporary)
            command = [executable, "-a", "never", "exec", "-s", "workspace-write", "--cd",
                       str(project), "--output-schema", str(schema_path), "-o", str(output_path), "-"]
            failure = None
            exit_code = None
            try:
                try:
                    exit_code, failure = run_worker(command, prompt,
                                                   min(args.iteration_timeout, max(0.01, deadline - time.monotonic())))
                except OSError:
                    failure = "worker_launch_error"
                except KeyboardInterrupt:
                    append_event(event_path, event="interrupted", task_id=task_id, attempt=attempts)
                    raise
                if failure is None and exit_code != 0:
                    failure = "codex_nonzero_exit"
                if failure is None:
                    try:
                        result = validate_result(read_json(output_path), task)
                    except (ValueError, TypeError, KeyError, OSError):
                        failure = "invalid_worker_result"
            finally:
                output_path.unlink(missing_ok=True)  # Only this iteration's private scratch result.
            if failure:
                result = {"status": "continue", "task_id": task_id,
                          "summary": f"Worker did not produce a verified result ({failure}).",
                          "evidence": [], "acceptance_checks": [],
                          "next_action": "Inspect the workspace and retry within the attempt limit."}

            previous_evidence = set(metadata.get("evidence_seen", []))
            new_evidence = set(result["evidence"]) - previous_evidence
            metadata["evidence_seen"] = sorted(previous_evidence | set(result["evidence"]))
            metadata["no_progress_count"] = (0 if new_evidence else int(metadata.get("no_progress_count", 0)) + 1)
            metadata["last_finished_at"] = now()
            status = {"completed": "done", "blocked": "blocked", "continue": "in_progress"}[result["status"]]
            if status == "in_progress" and (attempts >= args.max_attempts
                                             or metadata["no_progress_count"] >= NO_PROGRESS_LIMIT):
                status = "blocked"
                result["next_action"] = ("Runner stopped retries after the attempt/no-progress limit. "
                                         + result["next_action"])
            checkpoint = state / f"{task_id}-attempt-{attempts}-{time.time_ns()}.json"
            atomic_json(checkpoint, {"at": now(), "task_id": task_id, "attempt": attempts,
                                     "status": status, "worker_exit_code": exit_code,
                                     "failure": failure, "result": result})
            metadata["last_checkpoint"] = str(checkpoint.relative_to(project))
            update_task(backlog_path, task_id, status=status, last_result=result, loop=metadata)
            append_event(event_path, event="finished", task_id=task_id, attempt=attempts,
                         status=status, failure=failure, checkpoint=metadata["last_checkpoint"])
            completed += int(status == "done")
            print(f"Finished {task_id}: {status}", flush=True)

        final_backlog = load_backlog(backlog_path)
        counts = {status: sum(task["status"] == status for task in final_backlog["tasks"])
                  for status in sorted(VALID_STATUSES)}
        append_event(event_path, event="stopped", iterations=iterations, completed=completed, counts=counts)
        print(json.dumps({"iterations": iterations, "completed_this_run": completed, "counts": counts,
                          "all_done": counts["done"] == len(final_backlog["tasks"])}))
        return 0 if counts["done"] == len(final_backlog["tasks"]) else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--max-iterations", type=int, default=20)
    parser.add_argument("--max-hours", type=float, default=8)
    parser.add_argument("--iteration-timeout", type=int, default=3600, help="Maximum seconds per worker.")
    parser.add_argument("--max-attempts", type=int, default=3, help="Persistent attempt limit per task.")
    parser.add_argument("--dry-run", action="store_true", help="Print next task and command without writing or running Codex.")
    args = parser.parse_args()
    if (args.max_iterations < 1 or args.iteration_timeout < 1 or args.max_attempts < 1
            or not math.isfinite(args.max_hours) or args.max_hours <= 0):
        parser.error("All limits must be positive finite values.")
    os.umask(0o077)
    def interrupted(_signal, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    try:
        return run(args)
    except KeyboardInterrupt:
        print("Interrupted. In-progress task and attempt count are checkpointed for resume.", file=sys.stderr)
        return 130
    except (OSError, ValueError, KeyError, StopIteration) as error:
        print(f"Loop stopped: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
