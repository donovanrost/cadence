import {
  decoders as d,
  requestPageMeta,
  scid as scidReader,
  spacecraftId as spacecraftIdReader,
  type ApiResult,
  type Decoded,
  type MissionId,
  type Page,
} from "@/api/index.ts";

/**
 * #678 (setup.md `GET …/catalog/revisions/:revision_id/spacecraft`): the spacecraft that use one
 * catalog revision, paged by name then id, with the whole count in `meta.total`. A fixed number of
 * queries for any fleet size.
 */
export const usesValues = ["saved", "active"] as const;
type Use = (typeof usesValues)[number];

export const revisionSpacecraftReader = d.object({
  id: spacecraftIdReader,
  name: d.string,
  scid: d.nullable(scidReader),
  /** Which of the craft's configurations name the revision: its latest saved, its active, or both. */
  uses: d.array(d.known(usesValues), 2),
  /** The craft's latest saved configuration version; null when it has none. */
  configuration_version: d.nullable(d.integer),
});
export type RevisionSpacecraft = Decoded<typeof revisionSpacecraftReader>;

export type RevisionSpacecraftKey = Readonly<{ missionId: MissionId; catalogRevisionId: string }>;

export const USAGE_PAGE = 200;

export async function fetchRevisionSpacecraftPage(
  key: RevisionSpacecraftKey,
  cursor: string | null,
  signal: AbortSignal,
): Promise<ApiResult<Page<RevisionSpacecraft, Readonly<{ total: number }>>>> {
  const params = new URLSearchParams({ limit: String(USAGE_PAGE) });
  if (cursor !== null) params.set("cursor", cursor);
  const r = await requestPageMeta(
    `/missions/${encodeURIComponent(key.missionId)}/catalog/revisions/${encodeURIComponent(key.catalogRevisionId)}/spacecraft?${params.toString()}`,
    d.object({ spacecraft: d.array(revisionSpacecraftReader, 500) }),
    d.object({ total: d.integer }),
    { signal },
  );
  if (!r.ok) return r;
  return {
    ok: true,
    value: { items: r.value.value.spacecraft, next: r.value.nextCursor, meta: r.value.meta },
  };
}

const USE_WORDS: Readonly<Record<Use, string>> = {
  saved: "Saved configuration",
  active: "Running",
};

/**
 * "Running · Saved configuration": what uses it, by the craft's own configurations. An unknown use
 * (`known` decodes it as "unrecognized") says only that it's used.
 */
export function usesText(row: RevisionSpacecraft): string {
  const words = [...row.uses]
    .sort((a, b) => (a === "active" ? -1 : b === "active" ? 1 : 0))
    .map((u) => (u === "unrecognized" ? "Used" : USE_WORDS[u]));
  return [...new Set(words)].join(" · ");
}

/** "v3"; "No saved configuration" when the craft has none (it can still run the revision). */
export const versionText = (row: RevisionSpacecraft) =>
  row.configuration_version === null ? "No saved configuration" : `v${row.configuration_version}`;

/** A craft's name; U25: one with no name is "Unknown spacecraft", never its id. */
export const craftName = (row: RevisionSpacecraft) => row.name.trim() || "Unknown spacecraft";
