from __future__ import annotations

from fastapi import FastAPI
from fastapi.testclient import TestClient
from miloco.config import reset_settings
from miloco.observability.performance_report_router import router


def _app(tmp_path, monkeypatch) -> TestClient:
    monkeypatch.setenv("MILOCO_HOME", str(tmp_path))
    reset_settings()
    app = FastAPI()
    app.include_router(router)
    return TestClient(app)


def _write_report(root, name: str, status: str = "stopped") -> None:
    root.mkdir(parents=True, exist_ok=True)
    (root / name).write_text(
        "\n".join(
            [
                "# Miloco Performance Report",
                "",
                "## Run",
                "",
                "- run_id: `abc12345`",
                f"- status: `{status}`",
                "- version: `1.2.3`",
                "- started_at: 2026-06-23T10:00:00+00:00",
                "- ended_at: 2026-06-23T10:10:00+00:00",
                "- duration: 10m 0.0s",
                "- perf_enabled: `true`",
                "",
                "## Summary",
                "",
                "- cycles: 3",
            ]
        ),
        encoding="utf-8",
    )


def test_list_performance_reports(tmp_path, monkeypatch):
    with _app(tmp_path, monkeypatch) as client:
        root = tmp_path / "logs" / "performance"
        _write_report(root, "miloco-perf-20260623-100000-abc12345.md")
        # 不匹配命名规则的文件不暴露。
        (root / "notes.md").write_text("ignore", encoding="utf-8")

        resp = client.get("/api/performance-reports")

    assert resp.status_code == 200
    reports = resp.json()["reports"]
    assert len(reports) == 1
    assert reports[0]["filename"] == "miloco-perf-20260623-100000-abc12345.md"
    assert reports[0]["run_id"] == "abc12345"
    assert reports[0]["status"] == "stopped"
    assert reports[0]["duration"] == "10m 0.0s"


def test_get_performance_report_content(tmp_path, monkeypatch):
    with _app(tmp_path, monkeypatch) as client:
        root = tmp_path / "logs" / "performance"
        _write_report(root, "miloco-perf-20260623-100000-abc12345.md")

        resp = client.get(
            "/api/performance-reports/miloco-perf-20260623-100000-abc12345.md"
        )

    assert resp.status_code == 200
    data = resp.json()
    assert data["filename"] == "miloco-perf-20260623-100000-abc12345.md"
    assert "## Summary" in data["content"]


def test_get_performance_report_rejects_bad_name(tmp_path, monkeypatch):
    with _app(tmp_path, monkeypatch) as client:
        resp = client.get("/api/performance-reports/..%2Fconfig.json")

    assert resp.status_code == 404
