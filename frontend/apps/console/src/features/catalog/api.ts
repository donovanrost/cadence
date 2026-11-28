import type { MissionId } from "@/api/index.ts";
import { actor, decoders, request, type ApiResult, type Decoded, type Reader } from "@/api";
import { formatCount, formatShort } from "@/ui";

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

/**
 * #146 (mms-engineer #365, U103): who started a run. `name` is null for anyone the server won't
 * name (not a member of the mission's organization, gone, or no display name); never an email.
 */
const requester = object({
  kind: decoders.knownText(["user", "service", "system"] as const),
  name: nullable(string),
});
export type Requester = Decoded<typeof requester>;

/** One import run row (the index's; the artifact page lists the same rows, api L18). A run names
 * its own source file; null only if that file is gone, so one row can't break the page. */
export const importRunRow = object({
  id: token,
  file_name: nullable(string),
  format_label: nullable(string),
  status: oneOf(importStatuses),
  diagnostic_counts: object({ error: count, warning: count, info: count }),
  revision_number: nullable(count),
  started_at: timestamp,
  completed_at: nullable(timestamp),
  /** Optional: absent on a server before #365, which reads as the time alone. */
  requested_by: optional(nullable(requester)),
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

/**
 * U103's Started cell (amended by #370, #372): "11-19 05:40Z by Mira K."; an own-org service
 * "by Nightly planner (a service identity)", one the server doesn't name "by a service identity";
 * Cadence itself "by Cadence". A person the server doesn't name, a kind the console doesn't know,
 * or no record: the time alone, never an id (U25).
 */
export function startedLine(run: Pick<ImportRun, "started_at" | "requested_by">): string {
  const at = formatShort(new Date(run.started_at));
  const by = run.requested_by;
  if (by?.kind === "user" && by.name !== null) return `${at} by ${by.name}`;
  if (by?.kind === "service")
    return `${at} by ${by.name === null ? "a service identity" : `${by.name} (a service identity)`}`;
  if (by?.kind === "system") return `${at} by Cadence`;
  return at;
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
