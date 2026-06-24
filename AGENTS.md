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
- Never commit local secrets, credentials, Azure VM passwords, diagnostic reports containing private data, node_modules, build caches, or temporary VM transfer files.
- `.local-secrets/`, `.codegraph/`, `.codex/`, `dist/`, caches, and generated dependency folders must stay ignored.
