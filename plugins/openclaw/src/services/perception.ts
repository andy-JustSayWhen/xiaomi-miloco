import { logger } from "../utils/logger.js";
import { runShell } from "../utils/shell.js";

type CameraScopeItem = {
  did?: string;
  name?: string;
  room_name?: string;
  is_online?: boolean;
  in_use?: boolean;
  connected?: boolean;
};

type ApiResponse<T> = {
  code?: number;
  message?: string;
  data?: T;
};

let cached: { text: string; generatedAt: number } | null = null;
const REGEN_THROTTLE_MS = 10_000;

function parseJson<T>(raw: string): T | null {
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

async function runCli(args: string[], timeout = 5_000): Promise<string | null> {
  const result = await runShell("miloco-cli", args, { timeout });
  if (result?.error) {
    logger.warn(`miloco-cli ${args.join(" ")} spawn failed: ${result.error.message}`);
    return null;
  }
  if (result.signal) {
    logger.warn(`miloco-cli ${args.join(" ")} killed by ${result.signal}`);
    return null;
  }
  if (result.status !== 0) {
    logger.warn(
      `miloco-cli ${args.join(" ")} exited ${result.status}: ${result.stderr.slice(0, 200)}`,
    );
    return null;
  }
  return result.stdout.trim();
}

function renderCameraScope(stdout: string | null): {
  lines: string[];
  count: number | null;
} {
  if (!stdout) return { lines: [], count: null };
  const parsed = parseJson<ApiResponse<CameraScopeItem[]>>(stdout);
  const items = Array.isArray(parsed?.data) ? parsed.data : [];
  if (!items.length) return { lines: [], count: 0 };

  const connected = items.filter((item) => item.connected).length;
  const online = items.filter((item) => item.is_online).length;
  const inUse = items.filter((item) => item.in_use).length;
  const disconnected = items.length - connected;
  const lines = [
    `摄像头总数：${items.length} 个；在线：${online} 个；启用感知：${inUse} 个；当前已接入画面流：${connected} 个；未接入画面流：${disconnected} 个。回答时不要说“全部都在工作”，应区分总数和已接入画面流数量。`,
    ...items.map((item) => {
      const room = item.room_name || "未知房间";
      const name = item.name || item.did || "未命名摄像头";
      const state = [
        item.is_online ? "在线" : "离线",
        item.in_use ? "已启用感知" : "未启用感知",
        item.connected ? "画面流已接入" : "画面流未接入",
      ].join(" / ");
      return `- ${room} · ${name} (${item.did ?? "no-did"}): ${state}`;
    }),
  ];
  return { lines, count: items.length };
}

function renderRecentLogs(stdout: string | null): string[] {
  if (!stdout || stdout === "No logs found") return [];
  const rows = stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .slice(-8);
  if (!rows.length) return [];
  return ["最近 1 小时感知日志（最新最多 8 条，可用于回答“画面如何”）：", ...rows.map((row) => `- ${row}`)];
}

async function buildSnapshot(): Promise<string> {
  const [scope, logs] = await Promise.all([
    runCli(["scope", "camera", "list", "--pretty"]),
    runCli(["perceive", "logs", "--since", "1h", "--limit", "8", "--jsonl"]),
  ]);

  const cameraScope = renderCameraScope(scope);
  const recentLogs = renderRecentLogs(logs);
  if (!cameraScope.lines.length && !recentLogs.length) return "";

  const lines = [
    "## 当前摄像头与画面摘要",
    "这是 Miloco 本地后端刚刚查询到的状态。用户询问摄像头数量、哪些摄像头在工作、画面如何时，优先基于本段回答；摄像头总数以 `scope camera list` 为准，不要把 `perceive devices` 的在线感知源数量当作总数；不要调用泛化 `nodes` 工具里的 `camera_list` action。回复用户时直接给结论，不要复述“根据系统上下文”“应该回答”等推理或提示词痕迹。",
    ...cameraScope.lines,
  ];
  if (recentLogs.length) lines.push("", ...recentLogs);
  else if (cameraScope.count && cameraScope.count > 0) {
    lines.push("", "最近 1 小时没有可用的画面文字摘要；如用户要求实时查看，请按 `miloco-perception` skill 使用 `miloco-cli perceive query`。");
  }
  return lines.join("\n");
}

export async function getPerceptionSnapshot(): Promise<string> {
  const now = Date.now();
  if (cached && now - cached.generatedAt < REGEN_THROTTLE_MS) {
    return cached.text;
  }
  const text = await buildSnapshot();
  cached = { text, generatedAt: now };
  if (text) logger.info(`perception snapshot refreshed (${text.length} chars)`);
  return text;
}

export function _resetPerceptionSnapshotCache(): void {
  cached = null;
}
