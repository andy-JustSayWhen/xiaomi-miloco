from __future__ import annotations

import time

from miloco.observability.metrics_db import connect, init_schema
from miloco.observability.performance_report import (
    report_path,
    write_performance_report,
)


def test_report_path_uses_logs_performance_dir(tmp_path):
    p = report_path(tmp_path / "logs" / "performance", 1_700_000_000_000, "abc12345")
    assert p.parent == tmp_path / "logs" / "performance"
    assert p.name == "miloco-perf-20231114-221320-abc12345.md"


def test_write_performance_report_renders_metrics(tmp_path):
    db = tmp_path / "observability.db"
    conn = connect(db)
    init_schema(conn)
    now_ms = int(time.time() * 1000)
    started = now_ms - 60_000
    conn.execute(
        "INSERT INTO traces (trace_id, timestamp, skipped, decode_ms, collect_ms, "
        "convert_ms, gate_ms, identity_ms, omni_ms, log_ms, cycle_total_ms, "
        "pipeline_total_ms, window_duration_ms, in_delay_ms, stream_lag_ms, "
        "gate_video_pass, gate_audio_pass, omni_call_count, omni_error_count, "
        "dropped_windows_total, overflow_count_total) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        (
            "trace-1",
            now_ms - 1000,
            0,
            10.0,
            5.0,
            3.0,
            2.0,
            20.0,
            800.0,
            1.0,
            1000.0,
            900.0,
            3000.0,
            50.0,
            20.0,
            1,
            0,
            1,
            0,
            2,
            1,
        ),
    )
    conn.execute(
        "INSERT INTO agent_runs (run_id, trace_id, timestamp, source, "
        "duration_ms, webhook_rtt_ms, tool_call_count, tool_max_ms, "
        "slowest_tool_name, success) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (
            "agent-1",
            "trace-1",
            now_ms - 500,
            "interaction",
            500.0,
            30.0,
            1,
            120.0,
            "miot_call",
            1,
        ),
    )
    conn.close()

    out = tmp_path / "logs" / "performance" / "report.md"
    write_performance_report(
        path=out,
        db_path=db,
        run_id="abc12345",
        started_at_ms=started,
        ended_at_ms=now_ms,
        status="stopped",
        app_version="1.2.3",
        perf_enabled=True,
    )

    text = out.read_text(encoding="utf-8")
    assert "# Miloco Performance Report" in text
    assert "- run_id: `abc12345`" in text
    assert "- cycles: 1" in text
    assert "- agent_calls: 1" in text
    assert "| omni | 1 | 800.0 |" in text
    assert "| miot_call | 1 | 120.0 | 120.0 |" in text


def test_write_performance_report_when_perf_disabled(tmp_path):
    out = tmp_path / "logs" / "performance" / "report.md"
    write_performance_report(
        path=out,
        db_path=tmp_path / "missing.db",
        run_id="abc12345",
        started_at_ms=1,
        ended_at_ms=2,
        status="running",
        app_version="1.2.3",
        perf_enabled=False,
    )

    text = out.read_text(encoding="utf-8")
    assert "`perf.enabled=false`" in text
    assert "- status: `running`" in text
