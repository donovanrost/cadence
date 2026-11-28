import type { MissionId } from "@/api/index.ts";
import {
  actor,
  decoders as d,
  detailsOf,
  isError,
  request,
  type ApiError,
  type ApiResult,
  type Decoded,
} from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { formatShort } from "@/ui";
import { importRunRow } from "./api.ts";
import { formatBytes } from "./importRun.ts";

/**
 * L18 (api setup.md "Source files", 05aa7e399): one source file, the revisions made from it, its
 * import runs, Import again (K2) and Download (K3).
 */
const base = (missionId: MissionId) => `/missions/${encodeURIComponent(missionId)}/catalog`;

/** api serves K1-K3 (05aa7e399); on since the live check 11-13. */
export const ARTIFACT_LIVE = true;

const artifactReader = d.object({
  artifact: d.object({
    id: d.token,
    file_name: d.string,
    // Null when the file's format has no registered importer any more.
    format_label: d.nullable(d.string),
    format_version: d.nullable(d.string),
    // free-text: an IANA media type, shown as is.
    media_type: d.nullable(d.string),
    size_bytes: d.nullable(d.integer),
    sha256: d.string,
    uploaded_at: d.timestamp,
    // The artifact stores who uploaded it by name (an email), with no user id (api).
    uploaded_by: d.nullable(actor),
    database: d.object({ id: d.token, name: d.string }),
    download_url: d.string,
  }),
  revisions: d.array(
    d.object({
      id: d.token,
      number: d.integer,
      label: d.nullable(d.string),
      imported_at: d.timestamp,
    }),
    200,
  ),
  import_runs: d.array(importRunRow, 50),
  permissions: d.array(d.known(["catalog.import"] as const), 10),
});
export type ArtifactPage = Decoded<typeof artifactReader>;
export type ArtifactKey = Readonly<{ missionId: MissionId; artifactId: string }>;

export function fetchArtifact(
  k: ArtifactKey,
  signal: AbortSignal,
): Promise<ApiResult<ArtifactPage>> {
  return request(
    `${base(k.missionId)}/artifacts/${encodeURIComponent(k.artifactId)}`,
    artifactReader,
    {
      signal,
    },
  );
}

/** K2: a new import run on the stored file (202). */
export function reimportArtifact(k: ArtifactKey) {
  return request(
    `${base(k.missionId)}/artifacts/${encodeURIComponent(k.artifactId)}/reimport`,
    d.object({ import_run: d.object({ id: d.token }) }),
    { method: "POST", body: {} },
  );
}

/** "XTCE 1.2 · 2.4 MB · uploaded 11-12 14:03Z by Mira K." */
export function artifactLine(a: ArtifactPage["artifact"]): string {
  const format =
    a.format_label !== null && a.format_version
      ? `${a.format_label} ${a.format_version}`
      : a.format_label;
  const size = a.size_bytes === null ? null : formatBytes(a.size_bytes);
  const by = a.uploaded_by?.name ? ` by ${a.uploaded_by.name}` : "";
  return [format, size, `uploaded ${formatShort(new Date(a.uploaded_at))}${by}`]
    .filter(Boolean)
    .join(" · ");
}

/** A 409 import_running names the run already on this file, so Import again can open it. */
export function runningRun(error: ApiError): string | null {
  if (!isError(error, "import_running")) return null;
  return detailsOf(error, d.object({ import_run_id: d.token }))?.import_run_id ?? null;
}
export const reimportFailure = (error: ApiError) =>
  isError(error, "import_running")
    ? "An import of this file is already running."
    : failureOutcome(error, "changed").sentence;
