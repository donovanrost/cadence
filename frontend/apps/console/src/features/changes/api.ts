import type { MissionId } from "@/api/index.ts";
import { decoders, request, type ApiResult } from "@/api";
import {
  configStateReader,
  revisionDetailReader,
  revisionsReader,
  type ConfigState,
  type RevisionDetail,
  type RevisionSummary,
} from "./shapes.ts";

const base = (missionId: MissionId) => `/missions/${encodeURIComponent(missionId)}/config`;

/** The staged bar, `CONFIG rN · N STAGED`, and the caller's config capabilities. */
export function fetchConfigState(
  missionId: MissionId,
  signal: AbortSignal,
): Promise<ApiResult<ConfigState>> {
  return request(base(missionId), configStateReader, { signal });
}

export async function fetchRevisions(
  missionId: MissionId,
  signal: AbortSignal,
): Promise<ApiResult<readonly RevisionSummary[]>> {
  const result = await request(`${base(missionId)}/revisions?limit=50`, revisionsReader, {
    signal,
  });
  return result.ok ? { ok: true, value: result.value.revisions } : result;
}

export function fetchRevision(
  key: Readonly<{ missionId: MissionId; revision: number }>,
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

type DiffSide = Readonly<{
  before: unknown;
  after: unknown;
  unit?: string | null | undefined;
  format?: string | null | undefined;
  before_label?: string | null | undefined;
  after_label?: string | null | undefined;
  note?: string | null | undefined;
}>;
/** A diff row's old side: the option's words when the server sends them (U83), else the value. */
export const beforeText = (f: DiffSide) => f.before_label ?? showValue(f.before, f.unit, f.format);
/** The new side, with the row's reason in brackets after it (ux U83). */
export const afterText = (f: DiffSide) =>
  `${f.after_label ?? showValue(f.after, f.unit, f.format)}${f.note ? ` (${f.note})` : ""}`;

/**
 * The revisions touching one entity, newest first, each with just that entity's labelled entries
 * (api c3b07440d; Profile History). An unknown kind is 422 details.entity_kind.
 */
export async function fetchEntityRevisions(
  key: Readonly<{ missionId: MissionId; kind: string; entityId: string; limit?: number }>,
  signal: AbortSignal,
): Promise<ApiResult<readonly RevisionDetail[]>> {
  const q = new URLSearchParams({ entity_kind: key.kind, entity_id: key.entityId });
  if (key.limit) q.set("limit", String(key.limit));
  const r = await request(
    `${base(key.missionId)}/revisions?${q.toString()}`,
    decoders.object({ revisions: decoders.array(revisionDetailReader, 200) }),
    { signal },
  );
  return r.ok ? { ok: true, value: r.value.revisions } : r;
}
