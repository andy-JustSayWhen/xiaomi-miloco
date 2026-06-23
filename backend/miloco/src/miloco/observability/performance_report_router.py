"""HTTP API for per-run performance report files."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, HTTPException

from miloco.config import get_settings
from miloco.middleware import verify_token

router = APIRouter(dependencies=[Depends(verify_token)])

_REPORT_NAME_RE = re.compile(r"^miloco-perf-\d{8}-\d{6}-[0-9a-f]{8}\.md$")
_RUN_LINE_RE = re.compile(r"^- ([a-z_]+): (.*)$")


@router.get("/api/performance-reports")
def list_performance_reports() -> dict[str, Any]:
    root = _report_root()
    reports = []
    if root.exists():
        for path in sorted(root.glob("miloco-perf-*.md"), key=_mtime, reverse=True):
            if path.is_file() and _REPORT_NAME_RE.match(path.name):
                reports.append(_read_report_meta(path))
    return {"reports": reports}


@router.get("/api/performance-reports/{filename}")
def get_performance_report(filename: str) -> dict[str, Any]:
    if not _REPORT_NAME_RE.match(filename):
        raise HTTPException(status_code=404, detail="report not found")

    root = _report_root().resolve()
    path = (root / filename).resolve()
    try:
        path.relative_to(root)
    except ValueError:
        raise HTTPException(status_code=404, detail="report not found") from None
    if not path.is_file():
        raise HTTPException(status_code=404, detail="report not found")

    meta = _read_report_meta(path)
    return {**meta, "content": path.read_text(encoding="utf-8")}


def _report_root() -> Path:
    return get_settings().directories.performance_report_dir


def _mtime(path: Path) -> float:
    try:
        return path.stat().st_mtime
    except OSError:
        return 0.0


def _read_report_meta(path: Path) -> dict[str, Any]:
    try:
        stat = path.stat()
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        stat = None
        text = ""
    run = _parse_run_block(text)
    return {
        "id": path.name,
        "filename": path.name,
        "size_bytes": stat.st_size if stat else 0,
        "mtime": int((stat.st_mtime if stat else 0) * 1000),
        "run_id": run.get("run_id"),
        "status": run.get("status"),
        "app_version": run.get("version"),
        "started_at": run.get("started_at"),
        "ended_at": run.get("ended_at"),
        "duration": run.get("duration"),
        "perf_enabled": run.get("perf_enabled"),
    }


def _parse_run_block(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    in_run = False
    for line in text.splitlines():
        if line == "## Run":
            in_run = True
            continue
        if in_run and line.startswith("## "):
            break
        if not in_run:
            continue
        match = _RUN_LINE_RE.match(line.strip())
        if match:
            key, value = match.groups()
            values[key] = value.strip().strip("`")
    return values
