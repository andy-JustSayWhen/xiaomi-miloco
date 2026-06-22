# miloco-openclaw-plugin

OpenClaw plugin for Xiaomi Miloco — brings smart home perception and automation into OpenClaw.

## Install

This plugin is installed as part of Miloco via the easy-miloco one-click package. Download the matching `.zip` package from GitHub Release and run the package root installer:

https://github.com/andy-JustSayWhen/easy-miloco/releases

## What It Does

The plugin registers Miloco services, hooks, and webhook routes into OpenClaw, exposing the following AI skills:

| Skill | Description |
|-------|-------------|
| `miloco-devices` | Query and control IoT devices |
| `miloco-perception` | Visual perception and recognition |
| `miloco-miot-identity` | Person / pet identity management |
| `miloco-miot-admin` | System administration and cost stats |
| `miloco-create-task` | Task lifecycle: create / list / logs / enable / disable / update |
| `miloco-terminate-task` | Task termination: audit log + cascade cleanup + cron pending |
| `miloco-notify` | Perception anomaly response: grading + push notification |

## Configuration

Plugin settings can be overridden in the OpenClaw plugin config page. Leave fields empty to fall back to `$MILOCO_HOME/config.json`.

The Miloco backend must be running for the plugin to work:

```bash
miloco-cli service start
```

## Development

```bash
pnpm install
pnpm run build          # Build
pnpm run check          # Type check
pnpm test               # Run tests
pnpm run lint           # Lint
```

## License

For license details, please see [LICENSE.md](../../LICENSE.md).

**Important Notice**: This project is limited to non-commercial use only. Without written authorization from Xiaomi Corporation, this project may not be used for developing applications, web services, or other forms of software.
