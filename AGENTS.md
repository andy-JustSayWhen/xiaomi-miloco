# easy-miloco Agent Rules

## First Step For Every Turn

- Before planning, editing, testing, or answering about this repository, read this file.
- If the conversation was resumed, compacted, interrupted, or the task feels blurry, read this file again before continuing.
- Treat this file as the local project contract. If it conflicts with a direct newer user instruction, follow the newer user instruction and update this file when the new rule should persist.

## Current Primary Goal

Make the Windows "用户自己动" path genuinely reliable for non-technical Chinese users:

1. The user opens the repository README.
2. The user follows the GitHub Release / zip package instruction.
3. The user extracts the zip.
4. The user double-clicks root `install.bat`.
5. The installer automatically advances whenever possible.
6. When the installer cannot continue, it stops with clear Chinese instructions.
7. The window must not flash-close, show mojibake, show drifting/misaligned output, or end with unexplained English errors.

The goal is not complete until Azure VM visual testing confirms the flow.

## Test Policy

- Local CLI tests are necessary but not sufficient.
- Azure MCP, GitHub Copilot CLI, SSH, PowerShell remoting, and Run Command are allowed for setup and observation, but they cannot replace visual deployment testing.
- At least one full deployment test must be done visually from the user's perspective through Remote Desktop / Computer Use / Chrome-visible interaction.
- During visual deployment testing, behave like a non-technical user:
  - Do not manually fix the VM environment while testing.
  - Do not hand-run hidden corrective commands to make the installer pass.
  - If the installer fails, record what the user saw, return to local code, fix the installer, rebuild, then test again.
- Test coverage must include:
  - First install on a fresh or near-fresh Windows VM.
  - Reinstall / repair over an existing installation.
  - Update / overwrite from an existing package.
  - Missing or incomplete dependencies, especially WSL / Ubuntu / WSL2 capability handling.

## Acceptance Standard

The baseline acceptance target is:

- `install.bat` launches reliably by double-click.
- Administrator elevation is understandable in Chinese.
- The installer checks README-listed dependencies.
- The installer automatically handles what it can handle.
- All blocking messages are beginner-friendly Chinese.
- No mojibake appears.
- No text "drifts" or becomes visually misaligned in the main installer output.
- Logs and diagnostic reports are saved in the extracted package root.
- The basic Miloco/OpenClaw framework can start.
- Xiaomi account authorization, MiMo API key, and OpenClaw LLM configuration may remain as later manual steps for this phase.

## Azure VM Test Rules

- The Azure VM is the real user test machine.
- Use local code changes to build a release-like zip package, then move that package to the VM and run it visually.
- Check Azure balance periodically during long testing, roughly every 10 minutes or at natural pauses.
- Do not over-optimize for Azure cost; correctness of visual testing is the priority.
- Keep RDP restricted to the current trusted source IP when possible.
- Stop/deallocate or delete test resources when the user asks or when the testing session ends.

## Git Rules

- Before code edits, check `git status`.
- Commit small useful checkpoints. Commit frequency should favor rollback safety over tidiness.
- Push when a checkpoint is useful remotely, after tests, or when the user asks. Do not keep saying "later" when a commit/push is practical now.
- Never commit local secrets, credentials, Azure VM passwords, diagnostic reports containing private data, node_modules, build caches, or temporary VM transfer files.
- `.local-secrets/`, `.codegraph/`, `.codex/`, `dist/`, caches, and generated dependency folders must stay ignored.

## Documentation Rules

- Durable deployment findings must be written back to repository docs or Obsidian, not left only in chat.
- Azure VM creation and testing experience belongs in:
  `E:\obsidian repo\default\App学习笔记\Azure\Azure VM 创建二次虚拟化测试机经验.md`
- Windows installer / user manual path findings belong in repository `docs/windows/` or the most relevant runbook.

## Current Known VM

- Resource group: `rg-nestedvm-test`
- VM name: `vm-nested-test-01`
- OS: Windows Server 2025 Datacenter
- Region: Japan East
- Public IP: stored in local private notes and Azure Portal
- VM password: stored only under `.local-secrets/`, never in this file or docs.
