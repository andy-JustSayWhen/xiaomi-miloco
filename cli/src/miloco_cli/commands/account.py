"""account 命令组：小米账号绑定 / 解绑 / 状态查询。"""

import base64
import binascii
import json
import platform
import subprocess
import sys
from urllib.parse import parse_qs, urlparse

import click

from miloco_cli.output import print_result


@click.group("account")
def account_group():
    """小米账号管理：绑定 / 解绑 / 状态查询。"""


@account_group.command("status")
@click.option("--pretty", is_flag=True)
def account_status(pretty):
    """查看小米账号绑定状态及登录状态。"""
    from miloco_cli.client import api_get

    data = api_get("/api/miot/status")
    print_result(data, pretty)


def _state_from_oauth_url(oauth_url: str) -> str:
    parsed = urlparse(oauth_url)
    qs = parse_qs(parsed.query)
    return (qs.get("state") or [""])[0].strip()


def _parse_auth_payload(payload: str, expected_state: str = "") -> tuple[str, str]:
    """解析授权码、回调 URL、JSON 或 base64(JSON)，返回 (code, state)。"""
    payload = payload.strip()
    if not payload:
        raise click.ClickException("授权信息为空。")

    parsed_url = urlparse(payload)
    if parsed_url.scheme and parsed_url.netloc:
        qs = parse_qs(parsed_url.query)
        code = (qs.get("code") or [""])[0].strip()
        state = (qs.get("state") or [""])[0].strip()
        if code and state:
            return code, state
        raise click.ClickException("授权信息中 code 或 state 为空。")

    if (
        expected_state
        and "://" not in payload
        and "code=" not in payload
        and "state=" not in payload
    ):
        return payload, expected_state

    try:
        if payload.startswith("{"):
            decoded = payload
        else:
            padded = payload + "=" * ((4 - (len(payload) % 4)) % 4)
            decoded = base64.urlsafe_b64decode(padded).decode("utf-8")
        data = json.loads(decoded)
        code = data["code"].strip()
        state = data["state"].strip()
    except (
        binascii.Error,
        UnicodeDecodeError,
        json.JSONDecodeError,
        KeyError,
        AttributeError,
    ):
        raise click.ClickException(
            "授权信息格式错误。请粘贴页面显示的授权码，或粘贴浏览器地址栏里包含 code= 和 state= 的完整地址。"
        )
    if not code or not state:
        raise click.ClickException("授权信息中 code 或 state 为空。")
    return code, state


def _submit_authorize(code: str, state: str, pretty: bool) -> None:
    from miloco_cli.client import api_get, api_post

    data = api_post("/api/miot/authorize", {"code": code, "state": state})
    print_result(data, pretty)

    # 登录成功后列出家庭
    try:
        homes = api_get("/api/miot/scope/homes")
        home_list = homes.get("data", []) if isinstance(homes, dict) else []
    except (Exception, SystemExit):
        home_list = []

    if not home_list:
        click.echo("\n暂未获取到家庭列表，稍后可运行 miloco-cli scope home list 查看")
        return

    from miloco_cli.client import api_put

    if len(home_list) == 1:
        # 只有一个家庭，直接启用
        target = home_list[0]["home_id"]
        api_put("/api/miot/scope/homes", {"home_id": target})
        click.echo(f"\n已启用家庭：{home_list[0].get('home_name', target)}")
    elif not sys.stdin.isatty():
        # 非交互终端，无法选择，自动启用第一个家庭
        target = home_list[0]["home_id"]
        api_put("/api/miot/scope/homes", {"home_id": target})
        click.echo(
            f"\n检测到非交互终端，已自动启用第一个家庭：{home_list[0].get('home_name', target)}"
            "\n如需切换，可运行 miloco-cli scope home switch <home_id>"
        )
    else:
        # 多个家庭，让用户选择
        click.echo("\n请选择一个家庭：")
        for i, h in enumerate(home_list, 1):
            name = h.get("home_name", "")
            click.echo(f"  {i}. {h['home_id']}  {name}")
        while True:
            choice = click.prompt("\n输入编号", type=str)
            try:
                idx = int(choice) - 1
                if 0 <= idx < len(home_list):
                    break
            except ValueError:
                pass
            if any(h["home_id"] == choice for h in home_list):
                idx = next(
                    i for i, h in enumerate(home_list) if h["home_id"] == choice
                )
                break
            click.echo("无效选择，请重新输入")
        target = home_list[idx]["home_id"]
        api_put("/api/miot/scope/homes", {"home_id": target})
        click.echo(f"\n已切换到 {home_list[idx].get('home_name', target)}")


def _open_user_url(url: str) -> None:
    try:
        if sys.platform == "darwin":
            subprocess.run(
                ["open", url],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        elif sys.platform == "win32":
            subprocess.run(
                ["cmd", "/c", "start", "", url],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        elif platform.system().lower() == "linux":
            subprocess.run(
                ["xdg-open", url],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
    except OSError:
        pass


@account_group.command("bind")
@click.option("--no-wait", is_flag=True, help="只打印授权 URL 后退出，不等待粘贴授权信息。")
@click.option("--pretty", is_flag=True)
def account_bind(no_wait, pretty):
    """绑定小米账号：获取授权 URL，在浏览器中完成授权后粘贴回调信息。"""
    from miloco_cli.client import api_post

    data = api_post("/api/miot/bind")
    oauth_url = (
        data.get("data", {}).get("oauth_url")
        if isinstance(data.get("data"), dict)
        else None
    )
    if not oauth_url:
        raise click.ClickException("后端未返回 oauth_url。")

    _open_user_url(oauth_url)
    click.echo(
        "\n已尝试自动打开浏览器完成小米账号授权。"
        f"\n如果浏览器没有弹出，请手动打开：\n\n  {oauth_url}\n"
    )
    expected_state = _state_from_oauth_url(oauth_url)

    if no_wait:
        print_result(data, pretty)
        click.echo("\n授权完成后，请运行：")
        click.echo("  miloco-cli account authorize '<浏览器地址栏完整回调地址>'")
        click.echo("  如果页面只显示授权码，请重新运行 miloco-cli account bind 交互提交。")
        return

    payload = click.prompt(
        "授权完成后：如果页面直接显示授权码，就粘贴授权码；如果浏览器显示无法访问/报错页，就粘贴地址栏里包含 code= 和 state= 的完整地址",
        type=str,
    )
    code, state = _parse_auth_payload(payload, expected_state=expected_state)
    _submit_authorize(code, state, pretty)


@account_group.command("authorize")
@click.argument("payload")
@click.option("--pretty", is_flag=True)
def account_authorize(payload, pretty):
    """提交回调页面复制的 base64 授权码完成账号绑定。"""
    code, state = _parse_auth_payload(payload)
    _submit_authorize(code, state, pretty)


@account_group.command("unbind")
@click.option("--pretty", is_flag=True)
def account_unbind(pretty):
    """解绑小米账号（清除所有 MiOT 认证信息）。"""
    from miloco_cli.client import api_post

    data = api_post("/api/miot/unbind")
    print_result(data, pretty)
