"""Agent restore pack export tests."""

import json
import sqlite3
import zipfile
from io import BytesIO
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from miloco.admin.backup_export import (
    ASSET_HOME_PROFILE,
    ASSET_MEMBERS,
    ASSET_MODEL_CONFIG,
    ASSET_TASKS,
    DEFAULT_ASSETS,
    build_agent_restore_pack,
    normalize_assets,
)


@pytest.fixture(autouse=True)
def _isolate_miloco_home(tmp_path, monkeypatch):
    """每个测试隔离 MILOCO_HOME、settings cache 与 DB connector 单例。"""
    monkeypatch.setenv("MILOCO_HOME", str(tmp_path))
    monkeypatch.delenv("MILOCO_DATABASE__PATH", raising=False)

    import miloco.database.connector as connector_module
    from miloco.config.settings import reset_settings

    reset_settings()
    connector_module.db_connector = None
    connector_module.init_database()
    yield
    connector_module.db_connector = None
    reset_settings()


def _write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")


def _seed_config(home: Path) -> None:
    _write_json(
        home / "config.json",
        {
            "model": {
                "omni": {
                    "label": "mimo-prod",
                    "model": "xiaomi/mimo-v2.5",
                    "base_url": "https://api.example.test/v1",
                    "api_key": "sk-test-secret",
                },
                "omni_profiles": [
                    {
                        "label": "mimo-prod",
                        "model": "xiaomi/mimo-v2.5",
                        "base_url": "https://api.example.test/v1",
                        "api_key": "sk-test-secret",
                    }
                ],
            }
        },
    )


def _seed_home_profile(home: Path) -> None:
    profile_dir = home / "home-profile"
    _write_json(
        profile_dir / "profile.json",
        {
            "entries": [
                {
                    "id": "memory-1",
                    "type": "family",
                    "content": "晚饭后提醒 <person-a> 散步。",
                }
            ]
        },
    )
    _write_json(profile_dir / "candidates.json", {"by_date": {}})
    (profile_dir / "profile.md").write_text("# 家庭档案\n", encoding="utf-8")


def _seed_identity_lib(home: Path) -> None:
    sample = home / "data" / "identity_lib" / "persons" / "p1" / "tier_a"
    sample.mkdir(parents=True, exist_ok=True)
    (sample / "body_001.json").write_text('{"embedding":[0.1]}', encoding="utf-8")


def _seed_db(home: Path) -> None:
    conn = sqlite3.connect(home / "miloco.db")
    now = 1_780_000_000
    conn.execute(
        "INSERT INTO person (id, name, role, created_at, updated_at) "
        "VALUES (?, ?, ?, ?, ?)",
        ("p1", "<person-a>", "爸爸", now, now),
    )
    conn.execute(
        "INSERT INTO task (task_id, description, status, paused_at, created_at) "
        "VALUES (?, ?, ?, ?, ?)",
        ("desk_sit_30min", "久坐 30 分钟提醒", "active", None, now),
    )
    conn.execute(
        """
        INSERT INTO rule (
            id, name, task_id, mode, lifecycle, enabled, condition, actions,
            action_descriptions, on_enter_actions, on_enter_desc, on_exit_actions,
            on_exit_desc, on_target_desc, terminate_when, exit_debounce_seconds,
            duration_seconds, duration_ratio, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            "rule-1",
            "久坐提醒",
            "desk_sit_30min",
            "event",
            "permanent",
            1,
            '{"type":"state"}',
            "[]",
            '["通过飞书消息提醒 <person-a>"]',
            "[]",
            None,
            "[]",
            None,
            None,
            None,
            60,
            None,
            0.8,
            now,
            now,
        ),
    )
    conn.execute(
        "INSERT INTO task_link (task_id, link_kind, link_ref) VALUES (?, ?, ?)",
        ("desk_sit_30min", "rule", "rule-1"),
    )
    conn.commit()
    conn.close()


def test_build_agent_restore_pack_full(tmp_path):
    _seed_config(tmp_path)
    _seed_home_profile(tmp_path)
    _seed_identity_lib(tmp_path)
    _seed_db(tmp_path)

    result = build_agent_restore_pack(DEFAULT_ASSETS)

    assert result.path.exists()
    assert result.path.parent == tmp_path / "packs"
    assert result.filename.startswith("miloco-agent-restore-pack-")
    assert result.filename.endswith(".zip")
    assert result.assets == DEFAULT_ASSETS
    assert result.size_bytes > 0

    with zipfile.ZipFile(result.path) as zf:
        names = set(zf.namelist())
        manifest = json.loads(zf.read("manifest.json").decode("utf-8"))
        tasks_restore = json.loads(
            zf.read("tasks/tasks.restore.json").decode("utf-8")
        )
        active_model = json.loads(zf.read("model/active-model.json").decode("utf-8"))

    assert {
        "manifest.json",
        "AGENTS.md",
        "RESTORE.md",
        "home-profile/index.json",
        "home-profile/profile.json",
        "home-profile/profile.md",
        "home-profile/candidates.json",
        "members/index.json",
        "members/members.json",
        "members/identity-lib/persons/p1/tier_a/body_001.json",
        "tasks/tasks.restore.json",
        "tasks/task-table.json",
        "tasks/rule-table.json",
        "tasks/task-link-table.json",
        "model/active-model.json",
        "model/model-profiles.json",
    }.issubset(names)

    assert manifest["kind"] == "miloco-agent-restore-pack"
    assert manifest["schema_version"] == 1
    assert manifest["restore_contract"] == "agent_restore_v1"
    assert manifest["assets"] == DEFAULT_ASSETS

    restore_task = tasks_restore["tasks"][0]
    assert restore_task["task"]["task_id"] == "desk_sit_30min"
    assert restore_task["rules"][0]["action_descriptions"] == '["通过飞书消息提醒 <person-a>"]'
    assert restore_task["restore_policy"] == {
        "default_status": "disabled",
        "notification_actions_require_remap": True,
        "enable_after_user_confirmation": True,
    }

    assert active_model["model"]["api_key"] == "sk-test-secret"


def test_build_agent_restore_pack_selected_assets(tmp_path):
    _seed_config(tmp_path)

    result = build_agent_restore_pack([ASSET_MODEL_CONFIG])

    with zipfile.ZipFile(result.path) as zf:
        names = set(zf.namelist())
        manifest = json.loads(zf.read("manifest.json").decode("utf-8"))

    assert manifest["assets"] == [ASSET_MODEL_CONFIG]
    assert "model/active-model.json" in names
    assert "members/members.json" not in names
    assert "tasks/tasks.restore.json" not in names
    assert "home-profile/profile.json" not in names


def test_build_agent_restore_pack_uses_unique_filename(tmp_path):
    _seed_config(tmp_path)

    first = build_agent_restore_pack([ASSET_MODEL_CONFIG])
    second = build_agent_restore_pack([ASSET_MODEL_CONFIG])

    assert first.filename != second.filename
    assert first.path != second.path
    assert first.path.exists()
    assert second.path.exists()


def test_normalize_assets_rejects_empty_and_unknown():
    assert normalize_assets(None) == [
        ASSET_HOME_PROFILE,
        ASSET_MEMBERS,
        ASSET_TASKS,
        ASSET_MODEL_CONFIG,
    ]
    assert normalize_assets([ASSET_TASKS, ASSET_TASKS]) == [ASSET_TASKS]
    with pytest.raises(ValueError, match="未选择"):
        normalize_assets([])
    with pytest.raises(ValueError, match="不支持"):
        normalize_assets(["runtime_config"])


def test_backup_export_endpoint_downloads_zip(tmp_path):
    from miloco.admin.router import router

    _seed_config(tmp_path)
    app = FastAPI()
    app.include_router(router, prefix="/api")

    resp = TestClient(app).post(
        "/api/admin/backup/export",
        json={"assets": [ASSET_MODEL_CONFIG]},
    )

    assert resp.status_code == 200
    assert resp.headers["content-type"] == "application/zip"
    assert "miloco-agent-restore-pack-" in resp.headers["content-disposition"]
    with zipfile.ZipFile(BytesIO(resp.content)) as zf:
        names = set(zf.namelist())
    assert "manifest.json" in names
    assert "AGENTS.md" in names
    assert "model/active-model.json" in names


def test_backup_export_endpoint_rejects_empty_assets():
    from miloco.admin.router import router

    app = FastAPI()
    app.include_router(router, prefix="/api")

    resp = TestClient(app).post("/api/admin/backup/export", json={"assets": []})

    assert resp.status_code == 400
    assert "未选择" in resp.json()["detail"]
