import type { MissionId } from "@/api/index.ts";
import { decoders, request, type ApiResult, type Decoded } from "@/api";

/** Contract: docs/apogee/api/setup.md (C2): importers + multipart upload. */
const { array, integer, object, string, token } = decoders;

export const importersReader = object({
  importers: array(object({ key: token, label: string, extensions: array(string, 20) }), 50),
  max_bytes: integer,
});
export type Importers = Decoded<typeof importersReader>;

const base = (missionId: MissionId) => `/missions/${encodeURIComponent(missionId)}/catalog`;

export function fetchImporters(
  missionId: MissionId,
  signal: AbortSignal,
): Promise<ApiResult<Importers>> {
  return request(`${base(missionId)}/importers`, importersReader, { signal });
}

export type UploadInput = Readonly<{
  file: File;
  target: Readonly<{ databaseId: string }> | Readonly<{ newName: string }>;
  revisionLabel: string;
  revisionNotes: string;
}>;

export function uploadCatalog(missionId: MissionId, input: UploadInput) {
  const form = new FormData();
  form.append("file", input.file);
  if ("databaseId" in input.target) form.append("database_id", input.target.databaseId);
  else form.append("name", input.target.newName);
  if (input.revisionLabel.trim()) form.append("revision_label", input.revisionLabel.trim());
  if (input.revisionNotes.trim()) form.append("revision_notes", input.revisionNotes.trim());
  return request(`${base(missionId)}/imports`, object({ import_run_id: token }), {
    method: "POST",
    body: form,
  });
}

/** Browser-side pre-checks (the server decides): extension and size. */
export function precheck(file: File, importers: Importers): string | null {
  if (file.size > importers.max_bytes)
    return `The file is ${formatMiB(file.size)}; the limit is ${formatMiB(importers.max_bytes)}.`;
  const name = file.name.toLowerCase();
  const known = importers.importers.flatMap((i) => i.extensions.map((e) => e.toLowerCase()));
  if (known.length > 0 && !known.some((ext) => name.endsWith(ext)))
    return `Cadence can't import ${file.name}. Accepted: ${known.join(", ")}.`;
  return null;
}

/** Limits are binary on the server (50 MiB = 52,428,800 bytes), so say MiB. */
export function formatMiB(bytes: number): string {
  const mib = bytes / 1_048_576;
  return `${Number.isInteger(mib) ? mib : mib.toFixed(1)} MiB`;
}
