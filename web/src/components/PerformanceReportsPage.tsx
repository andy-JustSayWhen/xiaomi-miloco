import { useEffect, useMemo, useState, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { getPerformanceReport, listPerformanceReports } from "@/api";
import { useAsync } from "@/hooks/useAsync";
import type {
  PerformanceReportDetail,
  PerformanceReportMeta,
} from "@/lib/types";

export function PerformanceReportsPage() {
  const { t } = useTranslation();
  const [selected, setSelected] = useState<string | null>(null);
  const reports = useAsync(() => listPerformanceReports(), [], {
    errorLabel: t("perfReports.errList"),
  });

  useEffect(() => {
    if (!reports.data || reports.data.length === 0) {
      setSelected(null);
      return;
    }
    if (!selected || !reports.data.some((r) => r.filename === selected)) {
      setSelected(reports.data[0].filename);
    }
  }, [reports.data, selected]);

  const detail = useAsync<PerformanceReportDetail | null>(
    () => (selected ? getPerformanceReport(selected) : Promise.resolve(null)),
    [selected],
    { errorLabel: t("perfReports.errDetail") },
  );

  const selectedMeta = useMemo(
    () => reports.data?.find((r) => r.filename === selected) ?? null,
    [reports.data, selected],
  );

  return (
    <div className="space-y-5">
      <header className="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-heading text-text-primary">
            {t("perfReports.title")}
          </h1>
          <div className="text-caption text-text-tertiary mt-1">
            {t("perfReports.count", { count: reports.data?.length ?? 0 })}
          </div>
        </div>
        <button
          type="button"
          onClick={() => {
            reports.reload();
            detail.reload();
          }}
          className="text-caption px-3 py-1.5 rounded-md border border-border text-text-secondary hover:text-text-primary hover:border-border-strong transition-colors"
        >
          {t("perfReports.refresh")}
        </button>
      </header>

      <div className="grid grid-cols-1 lg:grid-cols-[320px_minmax(0,1fr)] gap-4 items-start">
        <section className="rounded-xl bg-bg-secondary border border-border shadow-sm overflow-hidden">
          <div className="px-4 py-3 border-b border-border flex items-center justify-between">
            <h2 className="text-title text-text-primary">
              {t("perfReports.runs")}
            </h2>
            {reports.loading && (
              <span className="text-caption text-text-tertiary">
                {t("perf.loading")}
              </span>
            )}
          </div>
          <div className="max-h-[calc(100vh-190px)] overflow-y-auto p-2 space-y-1">
            {reports.error && (
              <PanelState text={reports.error.message} tone="error" />
            )}
            {!reports.loading && !reports.error && reports.data?.length === 0 && (
              <PanelState text={t("perfReports.empty")} />
            )}
            {(reports.data ?? []).map((report) => (
              <ReportListItem
                key={report.filename}
                report={report}
                active={report.filename === selected}
                onClick={() => setSelected(report.filename)}
              />
            ))}
          </div>
        </section>

        <section className="rounded-xl bg-bg-secondary border border-border shadow-sm overflow-hidden min-w-0">
          <ReportHeader
            report={detail.data ?? selectedMeta}
            loading={detail.loading}
          />
          <div className="p-4 md:p-5 min-h-[420px]">
            {detail.error && (
              <PanelState text={detail.error.message} tone="error" />
            )}
            {!detail.error && detail.loading && (
              <PanelState text={t("perf.loading")} />
            )}
            {!detail.error && !detail.loading && !detail.data && (
              <PanelState text={t("perfReports.noSelection")} />
            )}
            {!detail.error && !detail.loading && detail.data && (
              <MarkdownReport content={detail.data.content} />
            )}
          </div>
        </section>
      </div>
    </div>
  );
}

function ReportListItem({
  report,
  active,
  onClick,
}: {
  report: PerformanceReportMeta;
  active: boolean;
  onClick: () => void;
}) {
  const { t } = useTranslation();
  return (
    <button
      type="button"
      onClick={onClick}
      className={`w-full text-left rounded-lg px-3 py-2.5 transition-colors border ${
        active
          ? "bg-brand-soft border-brand-primary/30"
          : "border-transparent hover:bg-bg-tertiary"
      }`}
    >
      <div className="flex items-center justify-between gap-2">
        <span className="text-body font-semibold text-text-primary truncate">
          {formatDate(report.started_at) ?? report.filename}
        </span>
        <StatusPill status={report.status} />
      </div>
      <div className="text-caption text-text-tertiary mt-1 flex items-center gap-2 min-w-0">
        <span className="truncate">
          {t("perfReports.duration", { value: report.duration ?? "-" })}
        </span>
        <span className="shrink-0">·</span>
        <span className="truncate">run {report.run_id ?? "-"}</span>
      </div>
    </button>
  );
}

function ReportHeader({
  report,
  loading,
}: {
  report: PerformanceReportMeta | null;
  loading: boolean;
}) {
  const { t } = useTranslation();
  return (
    <div className="px-4 md:px-5 py-3 border-b border-border flex items-center justify-between gap-3 flex-wrap">
      <div className="min-w-0">
        <h2 className="text-title text-text-primary truncate">
          {report ? formatDate(report.started_at) : t("perfReports.detail")}
        </h2>
        <div className="text-caption text-text-tertiary mt-1 truncate">
          {report
            ? `${report.filename} · ${formatBytes(report.size_bytes)}`
            : t("perfReports.noSelection")}
        </div>
      </div>
      <div className="flex items-center gap-2 shrink-0">
        {loading && (
          <span className="text-caption text-text-tertiary">
            {t("perf.loading")}
          </span>
        )}
        {report && <StatusPill status={report.status} />}
      </div>
    </div>
  );
}

function StatusPill({ status }: { status: string | null }) {
  const label = status ?? "-";
  const tone =
    status === "stopped"
      ? "bg-success/10 text-success border-success/30"
      : status === "running"
        ? "bg-brand-soft text-brand-primary border-brand-primary/30"
        : "bg-bg-tertiary text-text-tertiary border-border";
  return (
    <span className={`text-caption-mono px-2 py-0.5 rounded-full border ${tone}`}>
      {label}
    </span>
  );
}

function PanelState({
  text,
  tone = "muted",
}: {
  text: string;
  tone?: "muted" | "error";
}) {
  return (
    <div
      className={`rounded-lg border p-6 text-center text-body ${
        tone === "error"
          ? "border-error text-error bg-error-bg"
          : "border-border text-text-secondary bg-bg-primary"
      }`}
    >
      {text}
    </div>
  );
}

function MarkdownReport({ content }: { content: string }) {
  const lines = content.split(/\r?\n/);
  const nodes: ReactNode[] = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) {
      i += 1;
      continue;
    }
    if (line.startsWith("|")) {
      const rows: string[][] = [];
      while (i < lines.length && lines[i].startsWith("|")) {
        const cells = lines[i]
          .split("|")
          .slice(1, -1)
          .map((cell) => cell.trim());
        if (!cells.every((cell) => /^:?-{3,}:?$/.test(cell))) {
          rows.push(cells);
        }
        i += 1;
      }
      nodes.push(<ReportTable key={nodes.length} rows={rows} />);
      continue;
    }
    if (line.startsWith("# ")) {
      nodes.push(
        <h2 key={nodes.length} className="text-heading text-text-primary mt-1 mb-4">
          {line.slice(2)}
        </h2>,
      );
      i += 1;
      continue;
    }
    if (line.startsWith("## ")) {
      nodes.push(
        <h3 key={nodes.length} className="text-title text-text-primary mt-6 mb-2">
          {line.slice(3)}
        </h3>,
      );
      i += 1;
      continue;
    }
    if (line.startsWith("- ")) {
      const items: string[] = [];
      while (i < lines.length && lines[i].startsWith("- ")) {
        items.push(lines[i].slice(2));
        i += 1;
      }
      nodes.push(
        <ul key={nodes.length} className="space-y-1.5 my-3">
          {items.map((item, idx) => (
            <li key={`${idx}-${item}`} className="text-body text-text-secondary flex gap-2">
              <span className="text-text-tertiary">-</span>
              <span className="min-w-0">{renderInline(item)}</span>
            </li>
          ))}
        </ul>,
      );
      continue;
    }
    nodes.push(
      <p key={nodes.length} className="text-body text-text-secondary my-2">
        {renderInline(line)}
      </p>,
    );
    i += 1;
  }

  return <article className="max-w-none">{nodes}</article>;
}

function ReportTable({ rows }: { rows: string[][] }) {
  if (rows.length === 0) return null;
  const [head, ...body] = rows;
  return (
    <div className="overflow-x-auto my-3 rounded-lg border border-border">
      <table className="w-full text-caption whitespace-nowrap">
        <thead className="bg-bg-tertiary text-text-secondary">
          <tr>
            {head.map((cell, idx) => (
              <th key={`${idx}-${cell}`} className="px-3 py-2 text-left font-semibold">
                {renderInline(cell)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {body.map((row, idx) => (
            <tr key={idx} className="border-t border-border">
              {row.map((cell, cellIdx) => (
                <td
                  key={`${idx}-${cellIdx}`}
                  className="px-3 py-2 text-text-secondary"
                >
                  {renderInline(cell)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function renderInline(text: string) {
  const parts = text.split(/(`[^`]+`)/g).filter(Boolean);
  return parts.map((part, idx) => {
    if (part.startsWith("`") && part.endsWith("`")) {
      return (
        <code
          key={idx}
          className="text-caption-mono text-text-primary bg-bg-tertiary rounded px-1"
        >
          {part.slice(1, -1)}
        </code>
      );
    }
    return <span key={idx}>{part}</span>;
  });
}

function formatDate(value: string | null): string | null {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return value;
  return d.toLocaleString();
}

function formatBytes(value: number): string {
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / 1024 / 1024).toFixed(1)} MB`;
}
