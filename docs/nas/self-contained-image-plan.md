# NAS self-contained image temporary plan

Status: temporary implementation note for the NAS branch.

## Problem

The current NAS image already costs users a large Docker image download, but it still downloads a GitHub Release zip during container startup. On NAS networks where GitHub Release is slow or blocked, both exposed ports stay closed because Miloco and OpenClaw never reach the service startup phase.

Observed failure:

- Docker image pulled successfully.
- Container started with ports `1810` and `18789` published.
- Container only ran `curl ... easy-miloco-v0.5-windows.zip`.
- No process listened on `1810` or `18789`.
- Browser showed `ERR_CONNECTION_REFUSED`.

## Target behavior

For normal YAML deployment:

```text
pull image -> start container -> initialize from bundled payload -> open 1810 / 18789
```

Runtime startup must not require GitHub Release access.

## Design

1. Docker build downloads the release zip once.
2. Docker build extracts only the release `payload/` files into `/opt/easy-miloco/runtime`.
3. Docker build stores the validation script in `/opt/easy-miloco/wsl-miloco-validate.sh`.
4. Container startup copies the bundled payload into `/data/runtime` before deciding whether a download is needed.
5. Runtime download is only a fallback for custom images, missing bundled payload, or explicit override.

## Acceptance

- A fresh container must not run `curl` against GitHub Release during normal startup.
- `/data/runtime/install.sh` and `/data/runtime/manifest.json` must come from bundled image files.
- At least one `miloco-linux-*.tar.gz` must exist in `/data/runtime`.
- `1810` and `18789` should only be unavailable while local initialization is still running, not because of external release download.

## Temporary architecture scope

The current public `v0.5` release only ships a Windows zip containing the Linux x86_64 payload. Until a NAS/Linux release asset contains both `linux-x86_64` and `linux-aarch64` payloads, publish this self-contained NAS image as `linux/amd64` only. Do not publish an `arm64` tag that embeds the wrong runtime.

## Follow-up cleanup

After validation, fold this note into the stable NAS Docker docs or remove it before merging back to `main`.
