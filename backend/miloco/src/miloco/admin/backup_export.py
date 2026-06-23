"""Agent-readable backup export for portable household assets.

This module intentionally builds a logical restore pack instead of copying the
whole SQLite database. The pack is meant for an Agent to inspect, diff, and
restore interactively.
"""

from __future__ import annotations

import json
import shutil
import sqlite3
import tempfile
import uuid
import zipfile
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from miloco.config import get_settings
from miloco.database.connector import get_db_connector
from miloco.perception.engine.identity.config_loader import resolve_library_root
from miloco.utils.paths import config_file, miloco_home
from miloco.utils.time_utils import deploy_timezone

BACKUP_KIND = "miloco-agent-restore-pack"
SCHEMA_VERSION = 1
RESTORE_CONTRACT = "agent_restore_v1"

ASSET_HOME_PROFILE = "home_profile"
ASSET_MEMBERS = "members"
ASSET_TASKS = "tasks"
ASSET_MODEL_CONFIG = "model_config"
SUPPORTED_ASSETS = {
    ASSET_HOME_PROFILE,
    ASSET_MEMBERS,
    ASSET_TASKS,
    ASSET_MODEL_CONFIG,
}
DEFAULT_ASSETS = [
    ASSET_HOME_PROFILE,
    ASSET_MEMBERS,
    ASSET_TASKS,
    ASSET_MODEL_CONFIG,
]

TASK_TABLES = [
    "task",
    "rule",
    "task_link",
    "task_record_progress",
    "task_record_duration",
    "task_record_duration_session",
    "task_record_event",
    "task_record_event_entry",
]

HOME_PROFILE_DIRNAME = "home-profile"


@dataclass(frozen=True)
class BackupExportResult:
    path: Path
    filename: str
    size_bytes: int
    created_at: str
    assets: list[str]


class BackupExportError(RuntimeError):
    def __init__(self, asset: str, message: str) -> None:
        super().__init__(message)
        self.asset = asset
        self.message = message


def normalize_assets(assets: list[str] | None) -> list[str]:
    if assets is None:
        return list(DEFAULT_ASSETS)
    selected = list(dict.fromkeys(assets))
    if not selected:
        raise ValueError("未选择备份资产")
    unsupported = [a for a in selected if a not in SUPPORTED_ASSETS]
    if unsupported:
        raise ValueError(f"不支持的备份资产: {', '.join(unsupported)}")
    return selected


def build_agent_restore_pack(assets: list[str] | None = None) -> BackupExportResult:
    selected = normalize_assets(assets)
    created_at = _now_iso()
    stamp = _stamp(created_at)
    filename = f"miloco-agent-restore-pack-{stamp}-{uuid.uuid4().hex[:8]}.zip"
    packs_dir = miloco_home() / "packs"
    packs_dir.mkdir(parents=True, exist_ok=True)
    final_path = packs_dir / filename

    with tempfile.TemporaryDirectory(prefix="miloco-backup-") as tmp_name:
        root = Path(tmp_name)
        _write_json(root / "manifest.json", _manifest(created_at, selected))
        (root / "RESTORE.md").write_text(
            _restore_markdown(created_at, selected), encoding="utf-8"
        )

        try:
            if ASSET_HOME_PROFILE in selected:
                _export_home_profile(root)
            if ASSET_MEMBERS in selected:
                _export_members(root)
            if ASSET_TASKS in selected:
                _export_tasks(root)
            if ASSET_MODEL_CONFIG in selected:
                _export_model_config(root)
        except BackupExportError:
            raise
        except Exception as exc:  # noqa: BLE001
            raise BackupExportError("unknown", str(exc)) from exc

        tmp_zip = final_path.with_suffix(".tmp")
        tmp_zip.unlink(missing_ok=True)
        try:
            with zipfile.ZipFile(
                tmp_zip,
                "w",
                compression=zipfile.ZIP_DEFLATED,
                compresslevel=6,
            ) as zf:
                for path in sorted(p for p in root.rglob("*") if p.is_file()):
                    zf.write(path, path.relative_to(root).as_posix())
            tmp_zip.replace(final_path)
        except BaseException:
            tmp_zip.unlink(missing_ok=True)
            raise

    return BackupExportResult(
        path=final_path,
        filename=filename,
        size_bytes=final_path.stat().st_size,
        created_at=created_at,
        assets=selected,
    )


def _now_iso() -> str:
    return datetime.now(deploy_timezone()).isoformat(timespec="seconds")


def _stamp(created_at: str) -> str:
    dt = datetime.fromisoformat(created_at)
    return dt.strftime("%Y%m%d-%H%M%S")


def _manifest(created_at: str, assets: list[str]) -> dict:
    settings = get_settings()
    return {
        "kind": BACKUP_KIND,
        "schema_version": SCHEMA_VERSION,
        "created_at": created_at,
        "source": {
            "app": "easy-miloco",
            "miloco_home_hint": str(miloco_home()),
            "app_version": settings.app.version,
            "timezone": str(deploy_timezone()),
        },
        "assets": assets,
        "restore_contract": RESTORE_CONTRACT,
    }


def _restore_markdown(created_at: str, assets: list[str]) -> str:
    asset_lines = "\n".join(f"- `{a}`" for a in assets)
    return f"""# Miloco Agent 恢复说明

创建时间: {created_at}
恢复契约: `{RESTORE_CONTRACT}`

这是 Agent 恢复包, 不是直接覆盖包。不要把其中的数据库表快照、身份库文件或配置文件原样覆盖到当前安装。

## 恢复原则

1. 读取 `manifest.json`, 校验 `kind`、`schema_version` 和 `assets`。
2. 在写入任何内容前创建导入前 checkpoint。
3. 读取当前 Miloco 状态, 生成差异计划并让用户确认高风险项。
4. 恢复家庭任务时优先落为 disabled 或 draft, 由用户确认后再启用。
5. 通知动作按当前环境重新映射。找不到原渠道或设备时, 询问用户替代方案。
6. 恢复失败时按导入日志回滚。

## 包含资产

{asset_lines}

## 建议恢复顺序

1. 家庭档案
2. 家庭成员
3. 模型配置
4. 家庭任务
"""


def _write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def _export_home_profile(root: Path) -> None:
    try:
        out = root / "home-profile"
        out.mkdir(parents=True, exist_ok=True)
        source_dir = miloco_home() / HOME_PROFILE_DIRNAME
        profile_json = source_dir / "profile.json"
        candidates_json = source_dir / "candidates.json"
        profile_md = source_dir / "profile.md"
        task_suggestions = source_dir / "task-suggestions.json"

        files: list[dict[str, object]] = []
        for src, name in (
            (profile_json, "profile.json"),
            (candidates_json, "candidates.json"),
            (profile_md, "profile.md"),
            (task_suggestions, "task-suggestions.json"),
        ):
            if src.exists():
                shutil.copy2(src, out / name)
                files.append({"path": name, "present": True, "size_bytes": src.stat().st_size})
            else:
                files.append({"path": name, "present": False, "size_bytes": 0})

        index = {
            "asset": ASSET_HOME_PROFILE,
            "source_dir": str(source_dir),
            "files": files,
        }
        _write_json(out / "index.json", index)
        if not (out / "profile.json").exists():
            _write_json(out / "profile.json", {"entries": []})
        if not (out / "candidates.json").exists():
            _write_json(out / "candidates.json", {"by_date": {}})
        if not (out / "profile.md").exists():
            (out / "profile.md").write_text("", encoding="utf-8")
    except Exception as exc:  # noqa: BLE001
        raise BackupExportError(ASSET_HOME_PROFILE, str(exc)) from exc


def _export_members(root: Path) -> None:
    try:
        out = root / "members"
        out.mkdir(parents=True, exist_ok=True)
        with _db_snapshot_connection() as conn:
            members = _table_rows(conn, "person")
        _write_json(out / "members.json", {"members": members, "total": len(members)})

        identity_root = resolve_library_root()
        if identity_root.exists():
            _copy_tree(identity_root, out / "identity-lib")
        else:
            (out / "identity-lib").mkdir(parents=True, exist_ok=True)
        _write_json(
            out / "index.json",
            {
                "asset": ASSET_MEMBERS,
                "person_rows": len(members),
                "identity_lib_source": str(identity_root),
                "identity_lib_present": identity_root.exists(),
            },
        )
    except Exception as exc:  # noqa: BLE001
        raise BackupExportError(ASSET_MEMBERS, str(exc)) from exc


def _export_tasks(root: Path) -> None:
    try:
        out = root / "tasks"
        records_dir = out / "records"
        out.mkdir(parents=True, exist_ok=True)
        records_dir.mkdir(parents=True, exist_ok=True)
        with _db_snapshot_connection() as conn:
            tables = {name: _table_rows(conn, name) for name in TASK_TABLES}

        _write_json(out / "task-table.json", {"rows": tables["task"]})
        _write_json(out / "rule-table.json", {"rows": tables["rule"]})
        _write_json(out / "task-link-table.json", {"rows": tables["task_link"]})
        for name in TASK_TABLES:
            if name.startswith("task_record_"):
                _write_json(records_dir / f"{name}.json", {"rows": tables[name]})

        _write_json(out / "tasks.restore.json", _tasks_restore_view(tables))
    except Exception as exc:  # noqa: BLE001
        raise BackupExportError(ASSET_TASKS, str(exc)) from exc


def _export_model_config(root: Path) -> None:
    try:
        out = root / "model"
        out.mkdir(parents=True, exist_ok=True)
        raw = _read_config_json()
        model = raw.get("model", {}) if isinstance(raw, dict) else {}
        omni = model.get("omni", {}) if isinstance(model, dict) else {}
        profiles = model.get("omni_profiles", []) if isinstance(model, dict) else []

        _write_json(
            out / "active-model.json",
            {
                "model": omni,
                "source": "config.json::model.omni",
            },
        )
        _write_json(
            out / "model-profiles.json",
            {
                "profiles": profiles if isinstance(profiles, list) else [],
                "source": "config.json::model.omni_profiles",
            },
        )
    except Exception as exc:  # noqa: BLE001
        raise BackupExportError(ASSET_MODEL_CONFIG, str(exc)) from exc


def _read_config_json() -> dict:
    path = config_file()
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


def _copy_tree(src: Path, dest: Path) -> None:
    ignore = shutil.ignore_patterns(".DS_Store", "Thumbs.db", "__pycache__")
    shutil.copytree(src, dest, dirs_exist_ok=True, ignore=ignore)


def _table_exists(conn: sqlite3.Connection, table: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)
    ).fetchone()
    return row is not None


def _table_rows(conn: sqlite3.Connection, table: str) -> list[dict]:
    if not _table_exists(conn, table):
        return []
    rows = conn.execute(f'SELECT * FROM "{table}"').fetchall()
    return [dict(row) for row in rows]


@contextmanager
def _db_snapshot_connection():
    """Short-lived consistent SQLite snapshot connection."""
    conn = sqlite3.connect(
        str(get_db_connector().db_path),
        timeout=get_settings().database.timeout,
    )
    try:
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys=ON")
        conn.execute("BEGIN")
        yield conn
    finally:
        try:
            conn.execute("ROLLBACK")
        finally:
            conn.close()


def _tasks_restore_view(tables: dict[str, list[dict]]) -> dict:
    rules_by_task: dict[str, list[dict]] = {}
    for rule in tables["rule"]:
        task_id = rule.get("task_id")
        if task_id:
            rules_by_task.setdefault(str(task_id), []).append(rule)

    links_by_task: dict[str, list[dict]] = {}
    for link in tables["task_link"]:
        task_id = str(link.get("task_id"))
        links_by_task.setdefault(task_id, []).append(link)

    records_by_task: dict[str, dict[str, list[dict]]] = {}
    for table, rows in tables.items():
        if not table.startswith("task_record_"):
            continue
        for row in rows:
            task_id = str(row.get("task_id"))
            records_by_task.setdefault(task_id, {}).setdefault(table, []).append(row)

    restore_tasks = []
    for task in tables["task"]:
        task_id = str(task.get("task_id"))
        restore_tasks.append(
            {
                "task": task,
                "rules": rules_by_task.get(task_id, []),
                "links": links_by_task.get(task_id, []),
                "records": records_by_task.get(task_id, {}),
                "restore_policy": {
                    "default_status": "disabled",
                    "notification_actions_require_remap": True,
                    "enable_after_user_confirmation": True,
                },
            }
        )

    return {
        "asset": ASSET_TASKS,
        "tasks": restore_tasks,
        "totals": {
            "tasks": len(tables["task"]),
            "rules": len(tables["rule"]),
            "links": len(tables["task_link"]),
        },
    }
