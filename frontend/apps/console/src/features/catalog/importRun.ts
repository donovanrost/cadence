import type { MissionId } from "@/api/index.ts";
import { decoders, request, type ApiResult, type Decoded, type Reader } from "@/api";
import { matchedRevisionReader, type MatchedRevision } from "./matchedRevision.ts";

/** Contract: docs/apogee/api/setup.md (C3) = setup-shapes.md §C3 + declaration_count. */
const { array, boolean, integer, nullable, object, oneOf, optional, string, timestamp, token } =
  decoders;

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
      /** The first change, e.g. `arguments/duration/type: size_in_bits 8 → 16`; null when added/removed. */
      change: nullable(string),
      breaking: boolean,
    }),
    20000,
  ),
  /** api cab661fe: at most 500 changes, breaking first; true when more exist. */
  truncated: optional(boolean),
});

export const importRunReader = object({
  id: token,
  status: oneOf(["running", "succeeded", "failed"]),
  started_at: timestamp,
  completed_at: nullable(timestamp),
  file: object({
    name: string,
    format_label: string,
    size_bytes: nullable(count),
    /** L18 (api 05aa7e399): the stored file; null when it's gone. */
    artifact: optional(nullable(object({ id: token, download_url: string }))),
  }),
  // free-text: the importer's sentence for why the run failed.
  failure_reason: nullable(string),
  declaration_count: nullable(count),
  diagnostics: array(
    object({
      severity: oneOf(["error", "warning", "info"]),
      // free-text: importer diagnostic codes, an open vocabulary per importer, shown mono.
      code: token,
      message: string,
      path: nullable(string),
    }),
    20000,
  ),
  revision: nullable(
    object({
      id: token,
      number: count,
      label: nullable(string),
      /** #119 U99: this revision's database ("of Payload catalog"); name null when it's gone. */
      database: optional(nullable(object({ id: token, name: nullable(string) }))),
    }),
  ),
  base_revision: nullable(object({ id: token, number: count })),
  diff: nullable(diff),
  /** #119 U99: the existing revision this run's content matched; null when it made a new one. */
  matched_revision: optional(nullable(matchedRevisionReader)),
});

export type ImportRunDetail = Decoded<typeof importRunReader>;

/**
 * #119 U99: the match when this run made NO revision of its own (its content matches one this
 * catalog database already has). A run into another database makes its own rev and is shown as a
 * new revision (`revision` set), so it returns null.
 */
export function sameDatabaseMatch(run: ImportRunDetail): MatchedRevision | null {
  return run.revision === null ? (run.matched_revision ?? null) : null;
}
export type Diagnostic = ImportRunDetail["diagnostics"][number];

export function fetchImportRun(
  key: Readonly<{ missionId: MissionId; importId: string }>,
  signal: AbortSignal,
): Promise<ApiResult<ImportRunDetail>> {
  return request(
    `/missions/${encodeURIComponent(key.missionId)}/catalog/imports/${encodeURIComponent(key.importId)}`,
    importRunReader,
    { signal },
  );
}

/** `4.1 GB`, `1.8 MB`, `412 KB`, `900 B` (decimal units, like file managers). */
export function formatBytes(bytes: number): string {
  if (bytes >= 1_000_000_000) return `${(bytes / 1_000_000_000).toFixed(1)} GB`;
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

/** Catalog.md C1 strip: "212→218" with "+7 ~4 −1" (zero parts dropped; "no changes" when none). */
export function kindTile(
  c: Readonly<{ before: number; after: number; added: number; changed: number; removed: number }>,
): Readonly<{ value: string; caption: string }> {
  const parts = [
    c.added > 0 ? `+${c.added}` : null,
    c.changed > 0 ? `~${c.changed}` : null,
    c.removed > 0 ? `−${c.removed}` : null,
  ].filter(Boolean);
  return {
    value: c.before === c.after ? String(c.after) : `${c.before}→${c.after}`,
    caption: parts.length > 0 ? parts.join(" ") : "no changes",
  };
}
