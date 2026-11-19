import type { MissionId } from "@/api/index.ts";
import { actor, decoders, request, type ApiResult, type Decoded, type Reader } from "@/api";
import { formatCount } from "@/ui";
import { runMatchReader } from "./matchedRevision.ts";

/**
 * Catalog index. Requested shape: docs/apogee/plans/setup-shapes.md §C1; the final contract
 * lands in docs/apogee/api/setup.md.
 */
const { array, integer, nullable, object, oneOf, optional, string, timestamp, token } = decoders;

const count: Reader<number> = (value, path = "") => {
  const n = integer(value, path);
  if (n < 0) throw new decoders.DecodeError(path, "non-negative integer");
  return n;
};

const currentRevision = object({
  id: token,
  number: count,
  label: nullable(string),
  declaration_count: count,
  command_count: nullable(count),
  telemetry_count: nullable(count),
  spacecraft_count: count,
});

const revision = object({
  id: token,
  number: count,
  label: nullable(string),
  notes: nullable(string),
  artifact: object({
    id: token,
    file_name: string,
    format_label: string,
    size_bytes: nullable(count),
    /** L18 K3 (api 05aa7e399): the stored file's download link (a plain link; the session is enough). */
    download_url: optional(string),
  }),
  declaration_count: count,
  spacecraft_count: count,
  imported_at: timestamp,
  actor: nullable(actor),
  /**
   * ux U65 (api, 11-15): the compiled mission model behind this revision and its approval state;
   * null for a revision without one, absent on older reads (no tag then).
   */
  model: optional(
    nullable(
      object({
        revision_id: token,
        status: decoders.knownText(["candidate", "approved", "rejected", "retired"] as const),
      }),
    ),
  ),
});

// api: no separate "pending"; a queued run reads as running.
export const importStatuses = ["running", "succeeded", "failed"] as const;
export type ImportStatus = (typeof importStatuses)[number];

/** One import run row (the index's; the artifact page lists the same rows, api L18). */
export const importRunRow = object({
  id: token,
  file_name: string,
  status: oneOf(importStatuses),
  diagnostic_counts: object({ error: count, warning: count, info: count }),
  revision_number: nullable(count),
  started_at: timestamp,
  completed_at: nullable(timestamp),
  /** #119 U99: the revision this run's content matched (its tag); null when it made its own. */
  matched: optional(nullable(runMatchReader)),
});

const database = object({
  id: token,
  current_revision: nullable(currentRevision),
  revisions: array(revision, 50),
  import_runs: array(importRunRow, 20),
});

export const catalogIndexReader = object({
  databases: array(object({ id: token, name: string, slug: token }), 100),
  database: nullable(database),
});

export type CatalogIndex = Decoded<typeof catalogIndexReader>;
export type CatalogRevision = Decoded<typeof revision>;
export type ImportRun = Decoded<typeof importRunRow>;
export type CurrentRevision = Decoded<typeof currentRevision>;

export type CatalogKey = Readonly<{ missionId: MissionId; databaseId: string | null }>;

export function fetchCatalogIndex(
  key: CatalogKey,
  signal: AbortSignal,
): Promise<ApiResult<CatalogIndex>> {
  const query = key.databaseId ? `?database_id=${encodeURIComponent(key.databaseId)}` : "";
  return request(
    `/missions/${encodeURIComponent(key.missionId)}/catalog${query}`,
    catalogIndexReader,
    { signal },
  );
}

/** "547 declarations · 212 commands · 335 telemetry points · applied to 500 spacecraft". */
export function revisionSummary(rev: CurrentRevision): string {
  const parts = [`${formatCount(rev.declaration_count)} declarations`];
  if (rev.command_count !== null) parts.push(`${formatCount(rev.command_count)} commands`);
  if (rev.telemetry_count !== null)
    parts.push(`${formatCount(rev.telemetry_count)} telemetry points`);
  parts.push(`applied to ${formatCount(rev.spacecraft_count)} spacecraft`);
  return parts.join(" · ");
}
