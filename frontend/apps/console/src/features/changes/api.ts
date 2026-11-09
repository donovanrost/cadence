import { request, type ApiResult } from "@/api";
import {
  configStateReader,
  revisionDetailReader,
  revisionsReader,
  type ConfigState,
  type RevisionDetail,
  type RevisionSummary,
} from "./shapes.ts";

const base = (missionId: string) => `/missions/${encodeURIComponent(missionId)}/config`;

/** The staged bar, `CONFIG rN · N STAGED`, and the caller's config capabilities. */
export function fetchConfigState(
  missionId: string,
  signal: AbortSignal,
): Promise<ApiResult<ConfigState>> {
  return request(base(missionId), configStateReader, { signal });
}

export async function fetchRevisions(
  missionId: string,
  signal: AbortSignal,
): Promise<ApiResult<readonly RevisionSummary[]>> {
  const result = await request(`${base(missionId)}/revisions?limit=50`, revisionsReader, {
    signal,
  });
  return result.ok ? { ok: true, value: result.value.revisions } : result;
}

export function fetchRevision(
  key: Readonly<{ missionId: string; revision: number }>,
  signal: AbortSignal,
): Promise<ApiResult<RevisionDetail>> {
  return request(`${base(key.missionId)}/revisions/${key.revision}`, revisionDetailReader, {
    signal,
  });
}

/** Field values are raw JSON; show them compactly and exactly. */
/** Display value: thousands separators, the schema unit, and `format: "version"` as v4. */
export function showValue(value: unknown, unit?: string | null, format?: string | null): string {
  if (value === null || value === undefined) return "—";
  if (format === "version" && typeof value === "number") return `v${value}`;
  const text =
    typeof value === "number"
      ? value.toLocaleString("en-US")
      : typeof value === "string"
        ? value
        : JSON.stringify(value);
  return unit && typeof value === "number" ? `${text} ${unit}` : text;
}
