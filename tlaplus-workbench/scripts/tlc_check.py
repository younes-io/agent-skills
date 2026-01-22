#!/usr/bin/env python3
"""
Deterministically run TLC on a spec+cfg and emit machine-readable results.

Why this exists:
- Running TLC is easy; keeping runs reproducible and parsing counterexamples
  reliably in an agent loop is where things go wrong.
- This script captures logs, dumps counterexamples in JSON (when produced),
  and writes a summary.json that other tools/agents can consume.

Dependencies: python3 stdlib, java, and a tla2tools.jar (set TLA2TOOLS_JAR or pass --jar).
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
import shlex
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, Optional

sys.dont_write_bytecode = True


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _find_tla2tools_jar(spec_dir: Path, explicit: Optional[str]) -> Optional[Path]:
    if explicit:
        p = Path(explicit).expanduser()
        return p if p.is_file() else None

    env = os.environ.get("TLA2TOOLS_JAR", "").strip()
    if env:
        p = Path(env).expanduser()
        if p.is_file():
            return p

    # Convenience guesses (non-authoritative).
    guesses = [
        spec_dir / "tla2tools.jar",
        spec_dir / "dist" / "tla2tools.jar",
        Path.cwd() / "tla2tools.jar",
    ]

    # If we're somewhere inside the tlaplus/tlaplus repo, this is the usual build output.
    for parent in [spec_dir] + list(spec_dir.parents):
        guesses.append(parent / "tlatools" / "org.lamport.tlatools" / "dist" / "tla2tools.jar")

    for g in guesses:
        if g.is_file():
            return g
    return None


def _mk_run_id(spec_path: Path, cfg_path: Path) -> str:
    ts = _dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    try:
        spec_h = _sha256_file(spec_path)[:8]
        cfg_h = _sha256_file(cfg_path)[:8]
        return f"{ts}-{spec_h}-{cfg_h}"
    except Exception:
        return ts


def _pick_metadir(meta_root: Path) -> Optional[Path]:
    if not meta_root.exists():
        return None
    subdirs = [p for p in meta_root.iterdir() if p.is_dir()]
    if not subdirs:
        return None
    # TLC creates a single timestamped metadir; pick newest if multiple exist.
    subdirs.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return subdirs[0]


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _summarize_trace(trace_path: Path, *, max_steps: int = 50) -> Optional[Dict[str, Any]]:
    try:
        script_dir = Path(__file__).resolve().parent
        sys.path.insert(0, str(script_dir))
        from tlc_trace_summary import summarize_counterexample_json  # type: ignore

        doc = _load_json(trace_path)
        return summarize_counterexample_json(doc, max_steps=max_steps)
    except Exception:
        return None


def _cmd() -> int:
    ap = argparse.ArgumentParser(description="Run TLC and emit a run summary JSON.")
    ap.add_argument("--spec", required=True, help="Path to root .tla module (e.g. Foo.tla)")
    ap.add_argument("--cfg", help="Path to .cfg file (default: <spec>.cfg)")
    ap.add_argument("--jar", help="Path to tla2tools.jar (default: $TLA2TOOLS_JAR)")
    ap.add_argument("--java", default="java", help="Java executable (default: java)")
    ap.add_argument("--workers", type=int, default=1, help="TLC workers (default: 1 for determinism)")
    ap.add_argument("--timeout-secs", type=int, default=0, help="Kill TLC after N seconds (0 = no timeout)")
    ap.add_argument("--out-root", help="Run artifacts root dir (default: <spec-dir>/.tlaplus-workbench/runs)")
    ap.add_argument("--trace-max-steps", type=int, default=50, help="Max steps to summarize from JSON trace")
    args = ap.parse_args()

    spec_path = Path(args.spec).expanduser().resolve()
    if not spec_path.is_file():
        sys.stderr.write(f"spec not found: {spec_path}\n")
        return 2

    cfg_path = Path(args.cfg).expanduser().resolve() if args.cfg else spec_path.with_suffix(".cfg")
    if not cfg_path.is_file():
        sys.stderr.write(f"cfg not found: {cfg_path}\n")
        return 2

    spec_dir = spec_path.parent
    module = spec_path.stem

    jar_path = _find_tla2tools_jar(spec_dir, args.jar)
    if jar_path is None:
        sys.stderr.write(
            "tla2tools.jar not found. Set $TLA2TOOLS_JAR or pass --jar.\n"
            "If you're in the tlaplus/tlaplus repo, build it with:\n"
            "  ant -f tlatools/org.lamport.tlatools/customBuild.xml default-maven\n"
            "and then use:\n"
            "  tlatools/org.lamport.tlatools/dist/tla2tools.jar\n"
        )
        return 2

    out_root = Path(args.out_root).expanduser().resolve() if args.out_root else (spec_dir / ".tlaplus-workbench" / "runs")
    run_id = _mk_run_id(spec_path, cfg_path)
    run_dir = out_root / run_id
    run_dir.mkdir(parents=True, exist_ok=False)

    stdout_path = run_dir / "tlc.stdout"
    stderr_path = run_dir / "tlc.stderr"
    summary_path = run_dir / "summary.json"
    trace_path = run_dir / "counterexample.json"

    meta_root = run_dir / "metadir"
    meta_root.mkdir(parents=True, exist_ok=True)

    # TLC resolves -config relative to the spec directory; pass a relative name when possible.
    cfg_arg = cfg_path.name if cfg_path.parent == spec_dir else str(cfg_path)

    cmd = [
        args.java,
        "-cp",
        str(jar_path),
        "tlc2.TLC",
        "-workers",
        str(args.workers),
        "-metadir",
        str(meta_root),
        "-dumpTrace",
        "json",
        str(trace_path),
        "-config",
        cfg_arg,
        module,
    ]

    started = time.time()
    started_iso = _dt.datetime.now(_dt.timezone.utc).isoformat()
    exit_code: int
    timed_out = False
    with stdout_path.open("w", encoding="utf-8") as out, stderr_path.open("w", encoding="utf-8") as err:
        try:
            p = subprocess.run(
                cmd,
                cwd=str(spec_dir),
                stdout=out,
                stderr=err,
                text=True,
                timeout=args.timeout_secs if args.timeout_secs and args.timeout_secs > 0 else None,
            )
            exit_code = p.returncode
        except subprocess.TimeoutExpired:
            timed_out = True
            exit_code = 124

    finished = time.time()
    finished_iso = _dt.datetime.now(_dt.timezone.utc).isoformat()

    metadir_used = _pick_metadir(meta_root)
    trace_exists = trace_path.is_file()

    # TLC can exit non-zero for errors that aren't property violations. Use the
    # presence of the dumped counterexample JSON as the most reliable signal.
    if trace_exists:
        status = "fail"
    elif timed_out:
        status = "timeout"
    elif exit_code == 0:
        status = "pass"
    else:
        status = "error"

    summary: Dict[str, Any] = {
        "status": status,
        "exit_code": exit_code,
        "timed_out": timed_out,
        "started_at_utc": started_iso,
        "finished_at_utc": finished_iso,
        "duration_ms": int((finished - started) * 1000),
        "spec_path": str(spec_path),
        "cfg_path": str(cfg_path),
        "module": module,
        "spec_dir": str(spec_dir),
        "jar_path": str(jar_path),
        "inputs": {
            "spec_sha256": _sha256_file(spec_path),
            "cfg_sha256": _sha256_file(cfg_path),
        },
        "command": cmd,
        "command_str": " ".join(shlex.quote(c) for c in cmd),
        "run_dir": str(run_dir),
        "meta_root": str(meta_root),
        "metadir": str(metadir_used) if metadir_used else None,
        "stdout_path": str(stdout_path),
        "stderr_path": str(stderr_path),
        "counterexample_json_path": str(trace_path) if trace_exists else None,
    }

    if trace_exists:
        trace_summary = _summarize_trace(trace_path, max_steps=args.trace_max_steps)
        if trace_summary is not None:
            summary["counterexample_summary"] = trace_summary

    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    sys.stdout.write(json.dumps(summary, indent=2, ensure_ascii=True) + "\n")

    # Exit status communicates pass/fail to calling agents/CI without requiring JSON parsing.
    if status == "pass":
        return 0
    if status == "fail":
        return 10
    if status == "timeout":
        return 11
    return 12


if __name__ == "__main__":
    raise SystemExit(_cmd())
