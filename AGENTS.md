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
- If GitHub release upload/download or git network operations are slow, use the local Clash proxy at `http://127.0.0.1:7897` before waiting indefinitely.
- Never commit local secrets, credentials, Azure VM passwords, diagnostic reports containing private data, node_modules, build caches, or temporary VM transfer files.
- `.local-secrets/`, `.codegraph/`, `.codex/`, `dist/`, caches, and generated dependency folders must stay ignored.

## Script Encoding Rules

- Before writing or editing scripts, especially Windows `.bat` / `.ps1` files or any script that prints Chinese text, reference and follow `E:\obsidian repo\default\设备维护\AI 写脚本前的编码规范提示词.md`; do not copy that document into this repository.
