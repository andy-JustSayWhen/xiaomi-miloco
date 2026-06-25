# easy-miloco Agent Rules

## First Step For Every Turn

- Before planning, editing, testing, or answering about this repository, read this file.
- If the conversation was resumed, compacted, interrupted, or the task feels blurry, read this file again before continuing.
- Treat this file as the local project contract. If it conflicts with a direct newer user instruction, follow the newer user instruction and update this file when the new rule should persist.
- Before code edits, read the `README.md` `### 目录树` section; do not add new top-level directories unless clearly necessary.

## Git Rules

- Before code edits, check `git status`.
- Commit small useful checkpoints. Commit frequency should favor rollback safety over tidiness.
- Push when a checkpoint is useful remotely, after tests, or when the user asks. Do not keep saying "later" when a commit/push is practical now.
- Before replacing or uploading any GitHub Release asset, ask the user for explicit confirmation. Do not auto-clobber release zips after every fix.
- Release packaging should default to Windows-side repackaging with the existing `payload/`; only use GitHub Actions, Docker, a Linux machine, or WSL when the Linux runtime bundle truly needs to be rebuilt.
- After the user explicitly confirms GitHub Release replacement, use `docs/scripts/publish-github-release-asset.ps1` as the fixed publish path. Do not hand-roll different `gh release upload` variants; the script must upload, verify size/digest, and fail loudly on mismatch.
- If GitHub release upload/download or git network operations are slow, use the local Clash proxy at `http://127.0.0.1:7897` before waiting indefinitely.
- For Azure VM or other remote deployment tests, do not run long blocking commands silently. If a VM step may exceed 60 seconds, prefer `docs/scripts/azure-vm-run-job-and-deallocate.ps1`; it starts/submits/polls and deallocates in `finally`. Its default mode polls small `status.json` every 20 seconds and fetches stdout tail only every few polls. Report user-facing progress every 30-60 seconds from the runner log.
- After every Azure VM test or remote execution session, promptly stop/deallocate the VM with `docs/scripts/azure-vm-deallocate.ps1` unless the user explicitly asks to keep it running.
- Never commit local secrets, credentials, Azure VM passwords, diagnostic reports containing private data, node_modules, build caches, or temporary VM transfer files.
- `.local-secrets/`, `.codegraph/`, `.codex/`, `dist/`, caches, and generated dependency folders must stay ignored.

## Deployment Test Loop

- During release, VM, or remote Windows deployment tests, do not stop at the first non-blocking issue and immediately patch. Record the issue, evidence, screenshot/log path, and affected step in the relevant validation document first, then continue the remaining planned steps.
- Stop mid-test only for hard blockers: data loss risk, security/system permission prompt that needs the user, unrecoverable install failure, or a step that makes later checks meaningless.
- After the test pass finishes, summarize all issues, decide one scoped iteration, patch it, rebuild or republish only when needed, then rerun the affected deployment path. Repeat this record -> complete pass -> iterate -> retest loop until the deployment is fully green.
- For Windows release validation, write the running notes to `docs/windows/validation-record.md` or the specific runbook/report referenced by the task. Keep private secrets out of public docs.

## Script Encoding Rules

- Before writing or editing scripts, especially Windows `.bat` / `.ps1` files or any script that prints Chinese text, reference and follow `E:\obsidian repo\default\设备维护\AI 写脚本前的编码规范提示词.md`; do not copy that document into this repository.
