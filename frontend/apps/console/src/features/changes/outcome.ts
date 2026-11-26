import { decoders as d, type Decoded } from "@/api";
import { formatCount } from "@/ui";

/**
 * #522 (ca-engineer; ca-ux's K3 words, Changes.md K3): what applying the staged set does, from the
 * preview's rolled-back run. Readers first: every part is optional, and `outcome: null` (the
 * pipeline halted, or a read failed) leaves K3 with the Changes tile alone.
 */
const nowAfter = d.object({ now: d.integer, after: d.integer });
const counts = d.object({
  blocker: d.optional(d.integer),
  caution: d.optional(d.integer),
  stale: d.optional(d.integer),
  not_set_up: d.optional(d.integer),
});
export const outcomeReader = d.optional(
  d.nullable(
    d.object({
      spacecraft: d.optional(d.nullable(nowAfter)),
      routes: d.optional(
        d.nullable(
          d.object({ now: d.integer, after: d.integer, added: d.integer, removed: d.integer }),
        ),
      ),
      readiness: d.optional(d.nullable(d.object({ now: counts, after: counts }))),
    }),
  ),
);
export type Outcome = NonNullable<Decoded<typeof outcomeReader>>;

/** The Routes tile: added − removed ("+300", "−50", "0"), or both when both ("+300 −50"). */
export function routesDelta(r: NonNullable<Outcome["routes"]>): string {
  if (r.added > 0 && r.removed > 0) return `+${formatCount(r.added)} −${formatCount(r.removed)}`;
  const net = r.added - r.removed;
  return net > 0 ? `+${formatCount(net)}` : net < 0 ? `−${formatCount(-net)}` : "0";
}

const severityWords = [
  ["blocker", "blocker", "blockers"],
  ["caution", "caution", "cautions"],
  ["stale", "stale", "stale"],
  ["not_set_up", "not set up", "not set up"],
] as const;

/**
 * "Readiness after: 0 blockers (no change) · 2 cautions (no change) · 0 not set up (was 1)":
 * blockers always; the others only when nonzero now or after.
 */
export function readinessAfterLine(r: NonNullable<Outcome["readiness"]>): string {
  const parts = severityWords.flatMap(([key, one, many]) => {
    const now = r.now[key] ?? 0;
    const after = r.after[key] ?? 0;
    if (key !== "blocker" && now === 0 && after === 0) return [];
    const word = after === 1 ? one : many;
    const change = now === after ? "no change" : `was ${now}`;
    return [`${after} ${word} (${change})`];
  });
  return `Readiness after: ${parts.join(" · ")}`;
}

type Author = Readonly<{ kind: unknown; id: string | null; name: string | null }>;

/**
 * K9's Authors meta line (ca-ux 11-20; four-eyes needs them, not a tile): "Staged by you, Mira K.
 * and 2 more". The viewer first, as "you"; a service in a sentence with "(a service identity)"
 * (U103, #371); a nameless person drops from the names but still counts; up to three names, then
 * "and N more" (designers §3). Nobody named: "Staged by 2 people". Never an id.
 */
export function authorsLine(authors: readonly Author[], viewerId: string | null): string {
  if (authors.length === 0) return "";
  const isViewer = (a: Author) => viewerId !== null && a.id === viewerId;
  // A nameless service is still named as one (U25's sentence form, ca-ux on #578), so "people"
  // only ever counts people.
  const named = authors.flatMap((a) => {
    if (isViewer(a)) return [];
    if (a.kind === "service")
      return [a.name ? `${a.name} (a service identity)` : "a service identity"];
    // The system actor reads "Cadence" (U103), never a nameless person (mms-ux on #578).
    if (a.kind === "system") return [a.name ?? "Cadence"];
    return a.name ? [a.name] : [];
  });
  const names = [...(authors.some(isViewer) ? ["you"] : []), ...named];
  if (names.length === 0)
    return `Staged by ${authors.length} ${authors.length === 1 ? "person" : "people"}`;
  const shown = names.slice(0, 3);
  const more = authors.length - shown.length;
  if (more > 0) return `Staged by ${shown.join(", ")} and ${more} more`;
  return shown.length === 1
    ? `Staged by ${shown[0]}`
    : `Staged by ${shown.slice(0, -1).join(", ")} and ${shown.at(-1)}`;
}
