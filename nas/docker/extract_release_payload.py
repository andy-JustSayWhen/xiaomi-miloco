#!/usr/bin/env python3
import shutil
import sys
import zipfile
from pathlib import Path


REQUIRED_MODEL_FILES = {
    "det_4C.onnx",
    "human_body_reid_v2.onnx",
}


def main() -> int:
    zip_path = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    copied = 0
    copied_models = 0

    with zipfile.ZipFile(zip_path) as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue
            name = info.filename.replace("\\", "/")
            parts = [p for p in name.split("/") if p]
            rel = None
            if "payload" in parts:
                idx = parts.index("payload")
                rel_parts = parts[idx + 1 :]
                if rel_parts:
                    rel = Path(*rel_parts)
            elif (
                len(parts) >= 4
                and parts[-4] == "scripts"
                and parts[-3] == "windows"
                and parts[-2] == "models"
            ):
                rel = Path("models") / parts[-1]
                copied_models += 1
            elif "models" in parts and parts[-1].endswith((".onnx", ".json", ".txt")):
                rel = Path("models") / parts[-1]
                copied_models += 1
            elif (
                parts[-1] in {"install.sh", "install.py", "manifest.json"}
                or parts[-1].startswith(("miloco-linux-", "miloco-models-"))
            ):
                rel = Path(parts[-1])
            if rel is None:
                continue
            target = out_dir / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info) as src, target.open("wb") as dst:
                shutil.copyfileobj(src, dst)
            copied += 1

    if not (out_dir / "install.sh").is_file():
        raise SystemExit("release zip does not contain payload/install.sh")
    if not (out_dir / "manifest.json").is_file():
        raise SystemExit("release zip does not contain payload/manifest.json")
    if not list(out_dir.glob("miloco-linux-*.tar.gz")):
        raise SystemExit("release zip does not contain a linux runtime bundle")
    missing_models = [
        name for name in sorted(REQUIRED_MODEL_FILES) if not (out_dir / "models" / name).is_file()
    ]
    if missing_models:
        raise SystemExit(
            "release zip does not contain required perception model(s): "
            + ", ".join(missing_models)
        )
    print(
        f"bundled {copied} runtime file(s), including {copied_models} model file(s), to {out_dir}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
