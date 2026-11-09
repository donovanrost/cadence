import { decoders, request, type ApiResult, type Decoded, type Reader } from "@/api";

/** Contract: docs/apogee/api/setup.md (C3) = setup-shapes.md §C3 + declaration_count. */
const { array, boolean, integer, nullable, object, oneOf, string, timestamp, token } = decoders;

const count: Reader<number> = (value, path = "") => {
  const n = integer(value, path);
  if (n < 0) throw new decoders.DecodeError(path, "non-negative integer");
  return n;
};
const kindCounts = object({
  before: count,
  after: count,
  added: count,
  changed: count,
  removed: count,
});

const diff = object({
  summary: object({
    commands: nullable(kindCounts),
    telemetry: nullable(kindCounts),
    unchanged: count,
    total_before: count,
    breaking: nullable(count),
  }),
  changes: array(
    object({
      op: oneOf(["added", "changed", "removed"]),
      kind: oneOf(["command", "telemetry", "other"]),
      name: string,
      change: string,
      breaking: boolean,
    }),
    20000,
  ),
});

export const importRunReader = object({
  id: token,
  status: oneOf(["running", "succeeded", "failed"]),
  started_at: timestamp,
  completed_at: nullable(timestamp),
  file: object({ name: string, format_label: string, size_bytes: nullable(count) }),
  failure_reason: nullable(string),
  declaration_count: nullable(count),
  diagnostics: array(
    object({
      severity: oneOf(["error", "warning", "info"]),
      code: token,
      message: string,
      path: nullable(string),
    }),
    20000,
  ),
  revision: nullable(object({ id: token, number: count, label: nullable(string) })),
  base_revision: nullable(object({ id: token, number: count })),
  diff: nullable(diff),
});

export type ImportRunDetail = Decoded<typeof importRunReader>;
export type Diagnostic = ImportRunDetail["diagnostics"][number];

export function fetchImportRun(
  key: Readonly<{ missionId: string; importId: string }>,
  signal: AbortSignal,
): Promise<ApiResult<ImportRunDetail>> {
  return request(
    `/missions/${encodeURIComponent(key.missionId)}/catalog/imports/${encodeURIComponent(key.importId)}`,
    importRunReader,
    { signal },
  );
}

/** `1.8 MB`, `412 KB`, `900 B` (decimal units, like file managers). */
export function formatBytes(bytes: number): string {
  if (bytes >= 1_000_000) return `${(bytes / 1_000_000).toFixed(1)} MB`;
  if (bytes >= 1_000) return `${Math.round(bytes / 1_000)} KB`;
  return `${bytes} B`;
}

export function severityCounts(diagnostics: readonly Diagnostic[]) {
  return {
    error: diagnostics.filter((d) => d.severity === "error").length,
    warning: diagnostics.filter((d) => d.severity === "warning").length,
    info: diagnostics.filter((d) => d.severity === "info").length,
  };
}

export type DiagnosticGroup = Readonly<{
  key: string;
  severity: Diagnostic["severity"];
  code: string;
  message: string;
  count: number;
  paths: readonly string[];
}>;

/** Identical diagnostics collapse into one line with a count (errors first, then warnings, info). */
export function groupDiagnostics(diagnostics: readonly Diagnostic[]): readonly DiagnosticGroup[] {
  const groups = new Map<
    string,
    {
      severity: Diagnostic["severity"];
      code: string;
      message: string;
      count: number;
      paths: string[];
    }
  >();
  for (const d of diagnostics) {
    const key = `${d.severity}|${d.code}|${d.message}`;
    const group = groups.get(key) ?? {
      severity: d.severity,
      code: d.code,
      message: d.message,
      count: 0,
      paths: [],
    };
    group.count += 1;
    if (d.path !== null && group.paths.length < 3) group.paths.push(d.path);
    groups.set(key, group);
  }
  const rank = { error: 0, warning: 1, info: 2 } as const;
  return [...groups.entries()]
    .map(([key, g]) => ({ key, ...g }))
    .sort((a, b) => rank[a.severity] - rank[b.severity] || b.count - a.count);
}
