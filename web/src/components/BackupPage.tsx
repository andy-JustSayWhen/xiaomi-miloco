import { useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { exportBackupPack } from "@/api";
import type { BackupAsset, BackupExportResult } from "@/lib/types";

const ASSETS: BackupAsset[] = [
  "home_profile",
  "members",
  "tasks",
  "model_config",
];

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KB", "MB", "GB"];
  let value = bytes / 1024;
  for (const unit of units) {
    if (value < 1024) return `${value.toFixed(value >= 10 ? 1 : 2)} ${unit}`;
    value /= 1024;
  }
  return `${value.toFixed(1)} TB`;
}

export function BackupPage() {
  const { t, i18n } = useTranslation();
  const [selected, setSelected] = useState<BackupAsset[]>(ASSETS);
  const [exporting, setExporting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastResult, setLastResult] = useState<BackupExportResult | null>(null);

  const selectedSet = useMemo(() => new Set(selected), [selected]);
  const canExport = selected.length > 0 && !exporting;

  const toggleAsset = (asset: BackupAsset) => {
    setSelected((current) =>
      current.includes(asset)
        ? current.filter((item) => item !== asset)
        : ASSETS.filter((item) => item === asset || current.includes(item)),
    );
  };

  const handleExport = async () => {
    if (!canExport) return;
    setExporting(true);
    setError(null);
    try {
      const result = await exportBackupPack(selected);
      setLastResult(result);
    } catch (e) {
      setError(e instanceof Error ? e.message : t("backup.exportFailed"));
    } finally {
      setExporting(false);
    }
  };

  const exportedAt = lastResult
    ? new Intl.DateTimeFormat(i18n.language === "en" ? "en-US" : "zh-CN", {
        dateStyle: "medium",
        timeStyle: "medium",
      }).format(new Date(lastResult.exportedAt))
    : "";

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-page-title text-text-primary">{t("backup.title")}</h1>
        <p className="mt-1 text-body text-text-secondary">
          {t("backup.subtitle")}
        </p>
      </header>

      <section className="rounded-xl bg-bg-secondary border border-border shadow-sm p-5 md:p-6">
        <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
          <h2 className="text-section-title text-text-primary">
            {t("backup.assetsTitle")}
          </h2>
          <button
            type="button"
            disabled={!canExport}
            onClick={handleExport}
            className="inline-flex min-h-10 items-center justify-center rounded-md bg-brand-primary px-4 text-body font-medium text-white transition-opacity disabled:cursor-not-allowed disabled:opacity-50 hover:opacity-90"
          >
            {exporting ? t("backup.exporting") : t("backup.export")}
          </button>
        </div>

        <div className="mt-5 grid gap-3 md:grid-cols-2">
          {ASSETS.map((asset) => {
            const checked = selectedSet.has(asset);
            return (
              <label
                key={asset}
                className={`flex min-h-[88px] cursor-pointer items-start gap-3 rounded-lg border p-4 transition-colors ${
                  checked
                    ? "border-brand-primary bg-brand-soft"
                    : "border-border bg-bg-primary hover:border-border-strong"
                }`}
              >
                <input
                  type="checkbox"
                  checked={checked}
                  onChange={() => toggleAsset(asset)}
                  className="mt-1 h-4 w-4 accent-brand-primary"
                />
                <span className="min-w-0">
                  <span className="block text-title text-text-primary">
                    {t(`backup.assets.${asset}.label`)}
                  </span>
                  <span className="mt-1 block text-caption text-text-tertiary">
                    {t(`backup.assets.${asset}.hint`)}
                  </span>
                </span>
              </label>
            );
          })}
        </div>

        {selected.length === 0 && (
          <div className="mt-4 text-caption text-warning">{t("backup.selectOne")}</div>
        )}
        {error && <div className="mt-4 text-caption text-error">{error}</div>}
      </section>

      {lastResult && (
        <section className="rounded-xl bg-bg-secondary border border-border shadow-sm p-5 md:p-6">
          <h2 className="text-section-title text-text-primary">
            {t("backup.success")}
          </h2>
          <dl className="mt-4 grid gap-4 md:grid-cols-3">
            <div>
              <dt className="text-caption text-text-tertiary">
                {t("backup.filename")}
              </dt>
              <dd className="mt-1 break-all text-body text-text-primary">
                {lastResult.filename}
              </dd>
            </div>
            <div>
              <dt className="text-caption text-text-tertiary">{t("backup.size")}</dt>
              <dd className="mt-1 text-body text-text-primary">
                {formatBytes(lastResult.sizeBytes)}
              </dd>
            </div>
            <div>
              <dt className="text-caption text-text-tertiary">{t("backup.time")}</dt>
              <dd className="mt-1 text-body text-text-primary">{exportedAt}</dd>
            </div>
          </dl>
        </section>
      )}
    </div>
  );
}
