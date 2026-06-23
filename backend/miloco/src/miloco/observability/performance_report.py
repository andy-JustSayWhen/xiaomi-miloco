"""Write one human-readable performance report for each backend run."""

from __future__ import annotations

import logging
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from miloco.observability.metrics_db import connect, init_schema
from miloco.observability.stats import (
    agent_webhook_health,
    error_top_n,
    gate_pass_rate,
    gate_score_percentiles,
    slowest_tool_top_n,
    stage_percentiles,
    summary,
)

logger = logging.getLogger(__name__)

_STAGE_LABELS = {
    "decode_ms": "decode",
    "collect_ms": "collect",
    "convert_ms": "convert",
    "gate_ms": "gate",
    "identity_ms": "identity",
    "omni_ms": "omni",
    "log_ms": "log",
}


def new_run_id() -> str:
    return uuid.uuid4().hex[:8]


def report_path(report_dir: Path, started_at_ms: int, run_id: str) -> Path:
    stamp = _format_path_stamp(started_at_ms)
    return report_dir / f"miloco-perf-{stamp}-{run_id}.md"


def write_performance_report(
    *,
    path: Path,
    db_path: Path,
    run_id: str,
    started_at_ms: int,
    ended_at_ms: int,
    status: str,
    app_version: str,
    perf_enabled: bool,
) -> Path:
    """Render a Markdown performance report for one process run.

    The function is intentionally best-effort: report generation must never keep
    the backend from starting or shutting down.
    """
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        body = _render_report(
            db_path=db_path,
            run_id=run_id,
            started_at_ms=started_at_ms,
            ended_at_ms=ended_at_ms,
            status=status,
            app_version=app_version,
            perf_enabled=perf_enabled,
        )
        path.write_text(body, encoding="utf-8")
    except Exception:
        logger.exception("failed to write performance report: %s", path)
    return path


def _render_report(
    *,
    db_path: Path,
    run_id: str,
    started_at_ms: int,
    ended_at_ms: int,
    status: str,
    app_version: str,
    perf_enabled: bool,
) -> str:
    started = _format_ts(started_at_ms)
    ended = _format_ts(ended_at_ms)
    duration = _format_duration(max(0, ended_at_ms - started_at_ms))

    lines = [
        "# Miloco Performance Report",
        "",
        "## Run",
        "",
        f"- run_id: `{run_id}`",
        f"- status: `{status}`",
        f"- version: `{app_version}`",
        f"- started_at: {started}",
        f"- ended_at: {ended}",
        f"- duration: {duration}",
        f"- perf_enabled: `{str(perf_enabled).lower()}`",
        f"- observability_db: `{db_path}`",
        "",
    ]

    if not perf_enabled:
        lines.extend(
            [
                "## Summary",
                "",
                "`perf.enabled=false`; this run did not collect observability metrics.",
                "",
            ]
        )
        return "\n".join(lines)

    if not db_path.exists():
        lines.extend(
            [
                "## Summary",
                "",
                "No observability database was found for this run.",
                "",
            ]
        )
        return "\n".join(lines)

    try:
        conn = connect(db_path)
        try:
            init_schema(conn)
            lines.extend(_render_metric_sections(conn, started_at_ms, ended_at_ms))
        finally:
            conn.close()
    except sqlite3.Error as exc:
        lines.extend(
            [
                "## Summary",
                "",
                f"Failed to read observability database: `{exc}`",
                "",
            ]
        )
    except RuntimeError as exc:
        lines.extend(
            [
                "## Summary",
                "",
                f"Observability database schema is not readable by this version: `{exc}`",
                "",
            ]
        )
    return "\n".join(lines)


def _render_metric_sections(
    conn: sqlite3.Connection, since: int, until: int
) -> list[str]:
    s = summary(conn, "1h", since, until)
    stages = stage_percentiles(conn, "1h", since, until)
    slow_tools = slowest_tool_top_n(conn, "1h", since, until)
    errors = error_top_n(conn, "1h", since, until)
    gate = gate_pass_rate(conn, "1h", since, until)
    agent_health = agent_webhook_health(conn, "1h", since, until)
    gate_scores = gate_score_percentiles(conn, "1h", since, until)
    agent_sources = _agent_sources(conn, since, until)

    lines = [
        "## Summary",
        "",
        f"- cycles: {_int(s['cycle_count'])}",
        f"- skipped: {_pct(s['skip_rate'])}",
        f"- dropped_windows: {_int(s['dropped_count'])} ({_pct(s['drop_rate'])})",
        f"- omni_error_rate: {_pct(s['omni_error_rate'])}",
        f"- p95_rtf_e2e: {_num(s['p95_rtf_e2e'], digits=3)}",
        f"- p95_rtf_omni: {_num(s['p95_rtf_omni'], digits=3)}",
        f"- agent_calls: {_int(s['agent_call_count'])}",
        "",
    ]

    if s["cycle_count"] == 0 and s["agent_call_count"] == 0:
        lines.extend(
            [
                "No trace or agent-run rows were collected inside this process window.",
                "",
            ]
        )

    lines.extend(
        [
            "## Stage Latency",
            "",
            "| stage | sample | avg_ms | p50_ms | p75_ms | p95_ms | p99_ms |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
    )
    for key, label in _STAGE_LABELS.items():
        row = stages.get(key, {})
        lines.append(
            "| "
            f"{label} | {_int(row.get('sample_size'))} | {_num(row.get('avg'))} | "
            f"{_num(row.get('p50'))} | {_num(row.get('p75'))} | "
            f"{_num(row.get('p95'))} | {_num(row.get('p99'))} |"
        )
    lines.append("")

    lines.extend(
        [
            "## Agent",
            "",
            "| source | count | success_rate | avg_duration_ms | p95_webhook_rtt_ms |",
            "| --- | ---: | ---: | ---: | ---: |",
        ]
    )
    if agent_sources:
        p95_rtt = _max_nonzero([row.get("p95_rtt") for row in agent_health])
        for row in agent_sources:
            lines.append(
                "| "
                f"{row['source']} | {_int(row['count'])} | {_pct(row['success_rate'])} | "
                f"{_num(row['avg_duration_ms'])} | {_num(p95_rtt)} |"
            )
    else:
        lines.append("| n/a | 0 | 0.0% | 0 | 0 |")
    lines.append("")

    lines.extend(
        [
            "## Slow Tools",
            "",
            "| tool | count | avg_max_ms | peak_ms |",
            "| --- | ---: | ---: | ---: |",
        ]
    )
    if slow_tools:
        for row in slow_tools:
            lines.append(
                "| "
                f"{row['tool_name']} | {_int(row['count'])} | "
                f"{_num(row['avg_max_ms'])} | {_num(row['peak_ms'])} |"
            )
    else:
        lines.append("| n/a | 0 | 0 | 0 |")
    lines.append("")

    lines.extend(
        [
            "## Gate",
            "",
            "| bucket_count | avg_overall_pass | avg_video_pass | avg_audio_pass |",
            "| ---: | ---: | ---: | ---: |",
        ]
    )
    lines.append(
        "| "
        f"{len(gate)} | {_pct(_avg([g.get('overall') for g in gate]))} | "
        f"{_pct(_avg([g.get('video') for g in gate]))} | "
        f"{_pct(_avg([g.get('audio') for g in gate]))} |"
    )
    lines.append("")

    lines.extend(
        [
            "## Gate Scores By Device",
            "",
            "| device | room | video_count | video_p90 | audio_count | audio_p90 |",
            "| --- | --- | ---: | ---: | ---: | ---: |",
        ]
    )
    if gate_scores:
        for row in gate_scores[:10]:
            video = row.get("video", {})
            audio = row.get("audio", {})
            lines.append(
                "| "
                f"{row.get('device_id')} | {row.get('room_name') or ''} | "
                f"{_int(video.get('count'))} | {_num(video.get('p90'), digits=4)} | "
                f"{_int(audio.get('count'))} | {_num(audio.get('p90'), digits=4)} |"
            )
    else:
        lines.append("| n/a |  | 0 | 0 | 0 | 0 |")
    lines.append("")

    lines.extend(
        [
            "## Errors",
            "",
            "| error_prefix | count |",
            "| --- | ---: |",
        ]
    )
    if errors:
        for row in errors:
            lines.append(f"| {row['error_prefix']} | {_int(row['count'])} |")
    else:
        lines.append("| n/a | 0 |")
    lines.append("")

    return lines


def _agent_sources(
    conn: sqlite3.Connection, since: int, until: int
) -> list[dict[str, Any]]:
    rows = conn.execute(
        "SELECT source, COUNT(*), AVG(success), AVG(duration_ms) "
        "FROM agent_runs WHERE timestamp BETWEEN ? AND ? "
        "GROUP BY source ORDER BY COUNT(*) DESC",
        (since, until),
    ).fetchall()
    return [
        {
            "source": r[0],
            "count": r[1],
            "success_rate": r[2] or 0.0,
            "avg_duration_ms": r[3] or 0.0,
        }
        for r in rows
    ]


def _avg(values: list[Any]) -> float:
    nums = [float(v) for v in values if v is not None]
    return sum(nums) / len(nums) if nums else 0.0


def _max_nonzero(values: list[Any]) -> float:
    nums = [float(v) for v in values if v is not None]
    return max(nums) if nums else 0.0


def _format_path_stamp(ms: int) -> str:
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).strftime("%Y%m%d-%H%M%S")


def _format_ts(ms: int) -> str:
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).isoformat()


def _format_duration(ms: int) -> str:
    seconds = ms / 1000
    if seconds < 60:
        return f"{seconds:.1f}s"
    minutes, rem = divmod(seconds, 60)
    if minutes < 60:
        return f"{int(minutes)}m {rem:.1f}s"
    hours, minutes = divmod(minutes, 60)
    return f"{int(hours)}h {int(minutes)}m {rem:.1f}s"


def _num(value: Any, *, digits: int = 1) -> str:
    if value is None:
        return "0"
    try:
        return f"{float(value):.{digits}f}"
    except (TypeError, ValueError):
        return "0"


def _int(value: Any) -> str:
    if value is None:
        return "0"
    try:
        return str(int(value))
    except (TypeError, ValueError):
        return "0"


def _pct(value: Any) -> str:
    if value is None:
        return "0.0%"
    try:
        return f"{float(value) * 100:.1f}%"
    except (TypeError, ValueError):
        return "0.0%"
