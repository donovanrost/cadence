import type { MissionId } from "@/api/index.ts";
import { configKind } from "./shapes.ts";
import { decoders as d, request, type ApiResult } from "@/api";
import { entryOps, field, type RevisionEntry } from "./shapes.ts";

/** GET /config/compare?from=&to= (Changes.md §4 Compare): the combined diff between two revisions. */
const compareReader = d.object({
  from: d.integer,
  to: d.integer,
  entries: d.array(
    d.object({
      kind: configKind,
      entity_id: d.nullable(d.token),
      entity_name: d.optional(d.nullable(d.string)),
      op: d.knownText(entryOps),
      /** Revisions in (from, to] that touched this entity. */
      revisions: d.array(d.integer, 1000),
      fields: d.array(field, 2000),
    }),
    5000,
  ),
});

export type Comparison = Readonly<{
  from: number;
  to: number;
  entries: readonly (RevisionEntry & { revisions: readonly number[] })[];
}>;

/** Compare entries in the revision entry shape, so the revision page's list renders them. */
export async function fetchComparison(
  key: Readonly<{ missionId: MissionId; from: number; to: number }>,
  signal: AbortSignal,
): Promise<ApiResult<Comparison>> {
  const r = await request(
    `/missions/${encodeURIComponent(key.missionId)}/config/compare?from=${key.from}&to=${key.to}`,
    compareReader,
    { signal },
  );
  if (!r.ok) return r;
  return {
    ok: true,
    value: {
      from: r.value.from,
      to: r.value.to,
      entries: r.value.entries.map((e) => ({
        ...e,
        entity_name: e.entity_name ?? null,
        revision: e.revisions.at(-1) ?? r.value.to,
        paths: e.fields.map((f) => f.path),
      })),
    },
  };
}
