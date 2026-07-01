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

1. The NAS image workflow builds the current branch runtime payload with `scripts/build.sh`.
2. The workflow copies `install.sh`, `manifest.json`, the `miloco-linux-x86_64-*.tar.gz` bundle, and loose perception model files into `nas/docker/.build-payload/`.
3. Docker build copies `.build-payload/` into `/opt/easy-miloco/runtime`.
4. Docker build stores the validation script in `/opt/easy-miloco/wsl-miloco-validate.sh`.
5. Container startup copies the bundled payload into `/data/runtime` before deciding whether a download is needed.
6. Runtime download is only a fallback for custom images, missing bundled payload, or explicit override.

Local custom Docker builds that do not prepare `.build-payload/` still fall back to downloading and extracting the configured release zip at Docker build time.

## Acceptance

- A fresh container must not run `curl` against GitHub Release during normal startup.
- `/data/runtime/install.sh` and `/data/runtime/manifest.json` must come from bundled image files.
- At least one `miloco-linux-*.tar.gz` must exist in `/data/runtime`.
- `1810` and `18789` should only be unavailable while local initialization is still running, not because of external release download.

## Temporary architecture scope

The current public `v0.5` user-facing image tag is still `linux/amd64` only. Until arm64 NAS runtime validation is complete, do not publish an `arm64` tag.

## Follow-up cleanup

After validation, fold this note into the stable NAS Docker docs or remove it before merging back to `main`.
