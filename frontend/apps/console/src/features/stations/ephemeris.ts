import { decoders as d, type Decoded } from "@/api";
import { formatCount, plural } from "@/ui";

/**
 * A provider row's `ephemeris` (#968, #974, #975; setup.md "Mission providers"): how the provider
 * gets orbits, and its bound spacecraft with a current element set counted by state. The console
 * only shows the server's counts.
 */
export const orbitSources = ["accepts_ephemeris_upload", "looks_up_by_norad_id"] as const;

export const ephemerisReader = d.object({
  /** The provider's latest version's declaration; null when it declared nothing. */
  orbit_source: d.nullable(d.known(orbitSources)),
  uploaded: d.integer,
  failed: d.integer,
  /** #981 (#974): absent until it merges, then required. */
  not_ready: d.optional(d.integer),
  pending: d.integer,
  lookup: d.integer,
  norad_id_missing: d.integer,
});
export type Ephemeris = Decoded<typeof ephemerisReader>;

const uploadBuckets = ["uploaded", "failed", "not_ready", "pending"] as const;
const lookupBuckets = ["lookup", "norad_id_missing"] as const;
type Bucket = (typeof uploadBuckets)[number] | (typeof lookupBuckets)[number];
type Kind = "upload" | "lookup";

/** Each bucket's words after its count, and whether a non-zero count is a caution. */
const bucketWords: Readonly<Record<Bucket, { words: string; caution: boolean }>> = {
  uploaded: { words: "uploaded", caution: false },
  failed: { words: "upload failed, retrying", caution: true },
  not_ready: {
    words: "not ready, no route to this provider is ready, nothing sent",
    caution: true,
  },
  pending: { words: "waiting to upload", caution: false },
  lookup: { words: "looked up by NORAD id", caution: false },
  norad_id_missing: { words: "without a NORAD id, the provider can't find them", caution: true },
};

type Source = Ephemeris["orbit_source"];
/** The row's lead (U20: an unknown source says so). */
const leadWords: Readonly<Record<NonNullable<Source>, string>> = {
  accepts_ephemeris_upload: "Cadence uploads orbits",
  looks_up_by_norad_id: "Looks orbits up by NORAD id",
  unrecognized: "Orbit source not recognized",
};

/** The kind the source names; null (declared nothing) behaves as lookup, so it is assumed. */
function ownKind(source: Source): Kind | null {
  if (source === "accepts_ephemeris_upload") return "upload";
  if (source === "looks_up_by_norad_id" || source === null) return "lookup";
  return null;
}

export type EphemerisLine = Readonly<{
  key: Bucket;
  text: string;
  caution: boolean;
  /** Why a count's kind differs from the lead: assumed, or an older pinned version's. */
  note: string | null;
}>;

export type EphemerisSummary = Readonly<{
  lead: string;
  /** `12 spacecraft with an orbit`, or the honest empty line when there are none. */
  total: string;
  lines: readonly EphemerisLine[];
}>;

/**
 * Every non-zero bucket: each spacecraft is bucketed by the provider version its transport pins,
 * so one row can carry both kinds. The kind `orbit_source` names comes first; the other kind's
 * counts belong to an older pinned version and say so.
 */
export function ephemerisSummary(e: Ephemeris): EphemerisSummary {
  const own = ownKind(e.orbit_source);
  const kinds: readonly Kind[] = own === "lookup" ? ["lookup", "upload"] : ["upload", "lookup"];
  const count = (b: Bucket) => (b === "not_ready" ? (e.not_ready ?? 0) : e[b]);
  const note = (kind: Kind) => {
    if (own === null) return null;
    if (kind !== own) return "older pinned version";
    return e.orbit_source === null ? "assumed" : null;
  };
  const lines = kinds.flatMap((kind) =>
    (kind === "upload" ? uploadBuckets : lookupBuckets)
      .filter((b) => count(b) > 0)
      .map((b) => ({
        key: b,
        text: `${formatCount(count(b))} ${bucketWords[b].words}`,
        caution: bucketWords[b].caution,
        note: note(kind),
      })),
  );
  const sum = [...uploadBuckets, ...lookupBuckets].reduce((n, b) => n + count(b), 0);
  return {
    lead: e.orbit_source === null ? "Orbit source not declared" : leadWords[e.orbit_source],
    total:
      sum === 0
        ? "No bound spacecraft has an orbit yet"
        : `${plural(sum, "spacecraft", "spacecraft")} with an orbit`,
    lines,
  };
}
