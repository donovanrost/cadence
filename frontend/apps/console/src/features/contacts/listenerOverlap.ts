import { decoders as d, isKnown, orNull, type Decoded } from "@/api";

/**
 * U58 (b), #361: a pass that may lose its start because another pass of the mission holds a
 * station listener that takes one connection at a time. Read on the plan's passes, Book a pass
 * offers and booked passes (ca-engineer's #640). Additive: absent or null on a server before it.
 */
export const listenerOverlapReader = d.object({
  /** The worst overlap's other pass. */
  with: d.object({
    spacecraft: orNull(d.object({ id: orNull(d.string), name: orNull(d.string) })),
    station: orNull(d.object({ code: orNull(d.string), name: orNull(d.string) })),
    starts_at: orNull(d.timestamp),
    state: orNull(d.knownText(["booked", "planned"] as const)),
  }),
  /**
   * An upper bound: the runtime's claim windows, lead and teardown included (U58). null when
   * neither pass has an end (open-ended; #640 e1831dac5).
   */
  seconds: orNull(d.integer),
  loses: d.knownText(["this", "other", "either"] as const),
  direction: orNull(d.knownText(["downlink", "uplink"] as const)),
  /** Technical details only: U58 never puts a port in a sentence. */
  listener: orNull(d.object({ host: d.string, port: d.integer })),
  /** How many passes it overlaps (1 when single). */
  count: orNull(d.integer),
});
export type ListenerOverlap = Decoded<typeof listenerOverlapReader>;
/** The optional key every pass read carries since #640. */
export const listenerOverlapKey = d.optional(d.nullable(listenerOverlapReader));

/** §4 durations: "26 s", "1 m 40 s", "2 m", "1 h 5 m". */
export function overlapDuration(total: number): string {
  const s = Math.max(0, Math.round(total));
  if (s < 60) return `${s} s`;
  if (s < 3600) {
    const m = Math.floor(s / 60);
    const rest = s % 60;
    return rest ? `${m} m ${rest} s` : `${m} m`;
  }
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return m ? `${h} h ${m} m` : `${h} h`;
}

const upper = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

/** "EARENDIL-006's SNTG 00:05Z pass"; a null name reads "an unknown spacecraft's …" (U25, #635). */
function otherPass(o: ListenerOverlap): string {
  const craft = o.with.spacecraft?.name?.trim() || "an unknown spacecraft";
  const code = o.with.station?.code?.trim();
  const at = o.with.starts_at ? `${o.with.starts_at.slice(11, 16)}Z` : null;
  return `${craft}'s ${[code, at].filter(Boolean).join(" ")}${code || at ? " " : ""}pass`;
}

/** "Santiago's listener", "SNTG's listener" without a name, "The station's listener" with neither. */
function listenerOf(o: ListenerOverlap): string {
  const station = o.with.station;
  const name = station?.name?.trim() || station?.code?.trim();
  return name ? `${name}'s listener` : "The station's listener";
}

/** " and 2 other passes" when the pass overlaps more than one. */
function others(o: ListenerOverlap): string {
  const more = (o.count ?? 1) - 1;
  return more > 0 ? ` and ${more} other ${more === 1 ? "pass" : "passes"}` : "";
}

/**
 * The seconds' words, in one place (#640: `seconds` can be null when neither pass has an end).
 * Until ux words that case in U58 (b), the sentence drops the number: "may lose its start".
 */
const by = (seconds: number | null) => (seconds === null ? "" : ` by ${overlapDuration(seconds)}`);
const loseStart = (seconds: number | null) =>
  seconds === null
    ? "may lose its start"
    : `may lose up to ${overlapDuration(seconds)} of its start`;
const longest = (seconds: number | null) =>
  seconds === null ? "" : `; the longest overlap is ${overlapDuration(seconds)}`;

/**
 * U58 (b)'s words for one pass: the LISTENER OVERLAP tag and its sentence on the pass that may lose
 * time (`this`, and both under `either`), or the earlier pass's `text-3` note (`other`). Null with
 * none, or a `loses` this console doesn't know (it never guesses who loses).
 */
export function overlapWords(
  o: ListenerOverlap | null | undefined,
): Readonly<{ tag: boolean; text: string }> | null {
  if (!o || !isKnown(o.loses)) return null;
  const s = o.seconds;
  switch (o.loses) {
    case "this":
      return {
        tag: true,
        text: `Overlaps ${otherPass(o)}${by(s)}${others(o)}. ${listenerOf(o)} takes one connection at a time, so this pass ${loseStart(s)}.`,
      };
    case "either":
      return {
        tag: true,
        text: `Overlaps ${otherPass(o)}${by(s)}${others(o)}. ${listenerOf(o)} takes one connection at a time, and both claim it at once, so whichever connects second ${loseStart(s)}.`,
      };
    case "other":
      return {
        tag: false,
        text:
          (o.count ?? 1) > 1
            ? `${upper(otherPass(o))}${others(o)} overlap this one${longest(s)}.`
            : `${upper(otherPass(o))} overlaps this one${by(s)} and ${loseStart(s)}.`,
      };
  }
}

/** Technical details: the listener (host:port), the direction and the count; never in a sentence. */
export function overlapTechnical(o: ListenerOverlap | null | undefined): string | null {
  if (!o) return null;
  const parts = [
    o.listener ? `listener ${o.listener.host}:${o.listener.port}` : null,
    o.direction ? (isKnown(o.direction) ? o.direction : o.direction.unrecognized) : null,
    isKnown(o.loses) ? null : `loses ${o.loses.unrecognized}`,
    o.seconds === null ? "no end" : `${o.seconds} s`,
    o.count !== null && o.count > 1 ? `${o.count} passes` : null,
  ];
  return parts.filter(Boolean).join(" · ");
}
