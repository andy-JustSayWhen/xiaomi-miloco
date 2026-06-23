# SSH 命令传输方法

用途：固定 `Codex/PowerShell -> Windows OpenSSH -> wsl.exe -> Linux` 链路里的命令传输方法，避免每次排障都临时修引号、管道、重定向和 PATH。

## 先认清三层 shell

这条链路至少有三层解释器：

1. 本机 PowerShell。
2. 远端 Windows OpenSSH 默认 shell。
3. `wsl.exe` 拉起的 Linux shell。

同一条命令里的 `"`、`'`、`|`、`>`、`2>/dev/null`、`$PATH`、`~`、`*` 会被多层重复解释。如果一条命令同时跨三层还带管道、重定向、变量展开，出错概率很高。

## 固定规则

### 能不用 `bash -lc` 就不用

优先让 `wsl.exe` 直接执行单个 Linux 二进制或读取单个文件。

```powershell
ssh <windows-user>@<host> "wsl.exe -d <distro> -u <wsl-user> -- cat /home/<wsl-user>/.openclaw/miloco/config.json"
ssh <windows-user>@<host> "wsl.exe -d <distro> -u <wsl-user> -- /home/<wsl-user>/.local/bin/miloco-cli scope camera list --pretty"
```

适用场景：

- `cat`
- `find`
- `ls`
- `python /path/script.py`
- 绝对路径可执行文件

### 需要 shell 特性时才进入 `bash -lc`

只有在需要管道、重定向、`grep`、`tail`、变量展开或多条命令串联时才用 `bash -lc`。

```powershell
ssh <windows-user>@<host> "wsl.exe -d <distro> -u <wsl-user> -- bash -lc 'grep -n <pattern> /home/<wsl-user>/.openclaw/miloco/log/miloco-backend.log'"
```

关键点：

- 外层给 PowerShell/SSH 用双引号。
- `bash -lc` 内层命令尽量用单引号整体包住。
- 内层避免继续嵌双引号。

### 复杂命令先落脚本再执行

只要命令满足任一条件，就不要继续手写一行：

- 超过一层引号嵌套。
- 带 heredoc。
- 带多个管道。
- 带 stderr/stdout 重定向。
- 需要环境变量准备。
- 需要多步诊断并保留复用性。

固定做法：

1. 本地生成 `.sh`、`.py` 或 `.ps1`。
2. `scp` 到远端 Windows 临时目录。
3. 通过 `wsl.exe` 执行。

```powershell
scp .\diagnose-camera.py <windows-user>@<host>:C:/Users/<windows-user>/AppData/Local/Temp/diagnose-camera.py
ssh <windows-user>@<host> "wsl.exe -d <distro> -u <wsl-user> -- python /mnt/c/Users/<windows-user>/AppData/Local/Temp/diagnose-camera.py"
```

## 判定表

| 命令类型 | 固定做法 |
| --- | --- |
| 单个 CLI、`cat`、`ip`、`supervisorctl status` | `ssh "... wsl.exe ... -- <binary> <args>"` |
| 需要管道、重定向、循环、复杂 JSON | 写 `.py` 或 `.sh`，`scp` 后执行 |
| patch 传输 | `git diff --output=...` 生成原始 patch，再传输 |
| 多步远程操作 | 多次简单 SSH，或上传脚本 |

## 常见坑

- 不要在远端 Windows shell 里直接写 Linux 风格重定向，例如 `2>/dev/null`；Windows PowerShell 可能把它解释成写到 `C:\dev\null`。
- 不要把 `grep | tail | sed` 一整串直接塞进远端，而没有明确进入 `bash -lc`。
- 不要依赖远端非交互 shell 的 PATH。自定义 CLI 尽量用绝对路径，例如 `/home/<wsl-user>/.local/bin/miloco-cli`。
- 不要把多个 Linux 动作用 `&&` 直接跟在 `wsl.exe ...` 后面；`&&` 可能先被远端 Windows 命令层解析。需要链式执行时，把整段包进 `bash -lc`，或拆成多次 SSH。
- 生成 patch 时优先用 `git diff --output=patchfile`，不要用 PowerShell `>` 保存 patch；PowerShell 可能写成 UTF-16，导致远端 `git apply` 报 `no valid patches`。

一句话：短命令直传，复杂逻辑脚本化，patch 用 `--output`，执行用绝对路径。
