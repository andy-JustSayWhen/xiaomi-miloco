from __future__ import annotations

import asyncio
import argparse
import json
import os
import sqlite3
import sys
import urllib.parse
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import x25519
from miot.cloud import MIoTHttpClient


DEFAULT_DB = Path.home() / ".openclaw" / "miloco" / "miloco.db"


def kv(db_path: Path, key: str) -> str | None:
    con = sqlite3.connect(db_path)
    try:
        row = con.execute("select value from kv where key=?", (key,)).fetchone()
        return row[0] if row else None
    finally:
        con.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Probe Xiaomi MISS vendor metadata with Miloco OAuth credentials "
            "and print a go2rtc xiaomi:// URL candidate."
        )
    )
    parser.add_argument("did", help="Xiaomi device id")
    parser.add_argument("model", help="Xiaomi model, for example chuangmi.camera.061a01")
    parser.add_argument("ip", help="Camera LAN IP address")
    parser.add_argument("region", nargs="?", default="cn", help="Xiaomi region, default cn")
    parser.add_argument(
        "subtype",
        nargs="?",
        default="sd",
        help="go2rtc subtype, for example sd or hd; default sd",
    )
    parser.add_argument(
        "--db",
        default=os.environ.get("MILOCO_DB_PATH", str(DEFAULT_DB)),
        help="Miloco sqlite db path. Defaults to MILOCO_DB_PATH or ~/.openclaw/miloco/miloco.db",
    )
    return parser.parse_args()


async def main() -> None:
    args = parse_args()
    db_path = Path(args.db).expanduser()

    oauth_raw = kv(db_path, "MIOT_TOKEN_INFO_KEY")
    if not oauth_raw:
        raise SystemExit(f"MIOT_TOKEN_INFO_KEY not found in {db_path}")
    oauth = json.loads(oauth_raw)
    uid = str(oauth.get("user_info", {}).get("uid") or "")
    if not uid:
        raise SystemExit("uid missing in MIOT_TOKEN_INFO_KEY.user_info")

    private_key = x25519.X25519PrivateKey.generate()
    public_key = private_key.public_key()
    client_private = private_key.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption(),
    ).hex()
    client_public = public_key.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    ).hex()

    http = MIoTHttpClient(cloud_server=args.region, access_token=oauth["access_token"])
    try:
        post = getattr(http, "_MIoTHttpClient__mihome_api_post_async")
        response = await post(
            "/app/v2/device/miss_get_vendor",
            {
                "app_pubkey": client_public,
                "did": args.did,
                "support_vendors": "TUTK_CS2_MTP",
            },
        )
    finally:
        await http.deinit_async()

    result = response.get("result", response)
    vendor = result.get("vendor", {})
    vendor_id = vendor.get("vendor")
    vendor_name = {1: "tutk", 3: "agora", 4: "cs2", 6: "mtp"}.get(
        vendor_id, str(vendor_id)
    )
    query = {
        "did": args.did,
        "model": args.model,
        "client_public": client_public,
        "client_private": client_private,
        "device_public": result.get("public_key", ""),
        "sign": result.get("sign", ""),
        "vendor": vendor_name,
        "subtype": args.subtype,
        "audio": "0",
    }
    p2p_id = vendor.get("vendor_params", {}).get("p2p_id")
    if p2p_id:
        query["uid"] = p2p_id

    print("MISS_RES", json.dumps(response, ensure_ascii=False))
    print(
        f"GO2RTC_URL xiaomi://{uid}:{args.region}@{args.ip}?"
        f"{urllib.parse.urlencode(query)}"
    )


if __name__ == "__main__":
    asyncio.run(main())
