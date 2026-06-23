"""``MIoTVideoStreamManager.has_emitted_frame`` 单测。

首帧看门狗(router.py::_first_frame_watchdog)用它判定"该不该判摄像头连不上"——
注册成功(reg_id≥0)但 12s 内一帧没出 → 连不上。这里钉死它的契约:

- 反映的是 ``_camera_seen_keyframe``(回调广播首个 IDR 时填充)的成员资格;
- key 必须是 ``f"{camera_id}.{channel}"``,与 ws.py 全局 camera_tag 拼法一致——
  若有人改了拼法,这条立刻红,挡住"看门狗永远早退/永远误判"的隐性回归。
"""

from __future__ import annotations

import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock

from fastapi.websockets import WebSocketState
from miloco.miot.ws import MIoTVideoStreamManager
import miloco.miot.ws as ws_module


def test_false_before_any_frame():
    mgr = MIoTVideoStreamManager()
    assert mgr.has_emitted_frame("cam1", 0) is False


def test_true_after_keyframe_seen():
    mgr = MIoTVideoStreamManager()
    # 回调广播首个 IDR 时即 add 这个 tag(见 __video_stream_callback)
    mgr._camera_seen_keyframe.add("cam1.0")
    assert mgr.has_emitted_frame("cam1", 0) is True


def test_channel_not_conflated():
    """同一 camera_id 不同 channel 互不串——key 含 channel。"""
    mgr = MIoTVideoStreamManager()
    mgr._camera_seen_keyframe.add("cam1.0")
    assert mgr.has_emitted_frame("cam1", 0) is True
    assert mgr.has_emitted_frame("cam1", 1) is False


def test_key_format_matches_camera_tag():
    """key 拼法与 ws.py 各处 ``f"{camera_id}.{channel}"`` 一致——钉死防回归。"""
    mgr = MIoTVideoStreamManager()
    camera_id, channel = "1190512910", 2
    mgr._camera_seen_keyframe.add(f"{camera_id}.{channel}")
    assert mgr.has_emitted_frame(camera_id, channel) is True


def test_false_again_after_teardown_discard():
    """teardown 清掉 tag(全部订阅者退出)后回 False——看门狗生命周期回收依赖这点:
    下次新连接重新起看门狗。``_ensure_sdk_subscription``/``_teardown_if_idle`` 都会
    discard 这个 tag。"""
    mgr = MIoTVideoStreamManager()
    mgr._camera_seen_keyframe.add("cam1.0")
    assert mgr.has_emitted_frame("cam1", 0) is True
    mgr._camera_seen_keyframe.discard("cam1.0")
    assert mgr.has_emitted_frame("cam1", 0) is False


def _ws():
    return SimpleNamespace(
        client_state=WebSocketState.CONNECTED,
        close=AsyncMock(),
        send_text=AsyncMock(),
    )


async def test_idle_grace_keeps_sdk_stream_warm(monkeypatch):
    service = SimpleNamespace(
        start_video_stream=AsyncMock(return_value=7),
        stop_video_stream=AsyncMock(),
    )
    monkeypatch.setattr(ws_module, "manager", SimpleNamespace(miot_service=service))

    mgr = MIoTVideoStreamManager()
    mgr._IDLE_TEAR_DOWN_DELAY_S = 60
    cid = await mgr.new_connection(_ws(), "u", "t", "cam1", 0)
    mgr._camera_encoder["cam1.0"] = SimpleNamespace(close=AsyncMock())

    await mgr.close_connection("u", "t", "cam1", 0, cid)

    service.start_video_stream.assert_awaited_once()
    service.stop_video_stream.assert_not_awaited()
    assert "cam1.0" in mgr._camera_reg_id
    assert "cam1.0" in mgr._camera_idle_teardown_tasks
    mgr._cancel_idle_teardown("cam1.0")


async def test_new_connection_cancels_idle_teardown_without_restarting(monkeypatch):
    service = SimpleNamespace(
        start_video_stream=AsyncMock(return_value=7),
        stop_video_stream=AsyncMock(),
    )
    monkeypatch.setattr(ws_module, "manager", SimpleNamespace(miot_service=service))

    mgr = MIoTVideoStreamManager()
    mgr._IDLE_TEAR_DOWN_DELAY_S = 60
    cid = await mgr.new_connection(_ws(), "u", "t", "cam1", 0)
    mgr._camera_encoder["cam1.0"] = SimpleNamespace(close=AsyncMock())
    await mgr.close_connection("u", "t", "cam1", 0, cid)

    await mgr.new_connection(_ws(), "u", "t", "cam1", 0)

    service.start_video_stream.assert_awaited_once()
    service.stop_video_stream.assert_not_awaited()
    assert "cam1.0" not in mgr._camera_idle_teardown_tasks


async def test_idle_grace_eventually_tears_down(monkeypatch):
    service = SimpleNamespace(
        start_video_stream=AsyncMock(return_value=7),
        stop_video_stream=AsyncMock(),
    )
    monkeypatch.setattr(ws_module, "manager", SimpleNamespace(miot_service=service))

    mgr = MIoTVideoStreamManager()
    mgr._IDLE_TEAR_DOWN_DELAY_S = 0.01
    cid = await mgr.new_connection(_ws(), "u", "t", "cam1", 0)
    encoder = SimpleNamespace(close=AsyncMock())
    mgr._camera_encoder["cam1.0"] = encoder
    mgr._camera_seen_keyframe.add("cam1.0")

    await mgr.close_connection("u", "t", "cam1", 0, cid)
    await asyncio.sleep(0.02)

    service.stop_video_stream.assert_awaited_once_with("cam1", 0, 7)
    encoder.close.assert_awaited_once()
    assert "cam1.0" not in mgr._camera_reg_id
    assert mgr.has_emitted_frame("cam1", 0) is False
