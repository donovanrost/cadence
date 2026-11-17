import { short, type Attention } from "./attention.ts";
import { size } from "./ingress.ts";

/**
 * replay_conflict on Now (ux U84 "Stuck processing"): the words, by `path`. Never "replay",
 * "conflict", "partition", "journal", "effect" or "runtime" in visible text; those go in Technical
 * details. A craft whose name is null is counted, never shown by id (U25).
 */

type Craft = NonNullable<Attention["affected_spacecraft"]>[number];

/** The craft the item names, and how many more it counts (named past 3, or unnamed). */
function craft(a: Attention): Readonly<{ named: string[]; unnamed: number }> {
  const list: readonly Craft[] = a.affected_spacecraft ?? [];
  const named = list.flatMap((c) => (c.name ? [c.name] : []));
  const total = Math.max(list.length, a.spacecraft_count ?? 0);
  return { named, unnamed: total - named.length };
}

/** "A", "A and B", "A, B and C". */
const list = (names: readonly string[]) =>
  names.length < 2 ? (names[0] ?? "") : `${names.slice(0, -1).join(", ")} and ${names.at(-1)}`;

/** U47's pass label: "SVA 18:49Z pass"; no station, "18:49Z pass"; no pass known, null. */
function passLabel(a: Attention, now: Date): string | null {
  const c = a.contact;
  if (!c) return null;
  const where = [c.station_code, c.starts_at ? short(c.starts_at, now) : null].filter(Boolean);
  return where.length ? `${where.join(" ")} pass` : null;
}

/** The title: storage names its lead craft and the pass; the other paths name nobody (U84). */
export function stuckTitle(a: Attention, now: Date = new Date()): string {
  if (a.path === "processing") return "Incoming data is stuck";
  if (a.path === "timer") return "Timed actions are stuck";
  if (a.path !== "storage") return "Processing is stuck";
  const { named, unnamed } = craft(a);
  const others = named.length - 1 + unnamed;
  const lead = named[0]
    ? others > 0
      ? `${named[0]} and ${others} ${others === 1 ? "other" : "others"}`
      : named[0]
    : null;
  const parts = [lead, passLabel(a, now), "telemetry storage is stuck"].filter(Boolean);
  const text = parts.join(" · ");
  return text.charAt(0).toUpperCase() + text.slice(1);
}

/**
 * Who's affected off storage (U84, ux 11-17): never an exact set. One named: "It affects A, and
 * may affect others."; all named: "It affects at least 2 spacecraft: A and B."; some unnamed or
 * more than 3: "It affects at least 3 spacecraft, including A and B."; none named: "It affects at
 * least 1 spacecraft."; none known: "It isn't known yet which spacecraft it affects."
 */
export function affects(a: Attention): string {
  const { named, unnamed } = craft(a);
  const total = named.length + unnamed;
  if (total === 0) return "It isn't known yet which spacecraft it affects.";
  const first = named[0];
  if (total === 1 && first) return `It affects ${first}, and may affect others.`;
  const atLeast = `It affects at least ${total} spacecraft`;
  if (named.length === 0) return `${atLeast}.`;
  if (unnamed === 0 && named.length <= 3) return `${atLeast}: ${list(named)}.`;
  return `${atLeast}, including ${list(named.slice(0, 3))}.`;
}

/** What stopped (the first line), by path. */
export function whatStopped(a: Attention): string {
  if (a.path === "storage") {
    const { named, unnamed } = craft(a);
    const one = named.length === 1 && unnamed === 0 ? named[0] : null;
    const whose = one
      ? `${one}'s alarms and current values aren't updating`
      : "alarms and current values for this pass's spacecraft aren't updating";
    return `Cadence stopped storing this pass's telemetry, so ${whose}.`;
  }
  if (a.path === "timer") return `Timed actions aren't running. ${affects(a)}`;
  return `Cadence stopped processing incoming data, so telemetry isn't stored and alarms and current values aren't updating. ${affects(a)}`;
}

const FAULT = "It's a fault in Cadence, not in this mission's setup or data.";

/** Why (the second line): tries since, the last at; stopped at start has no counts (U84 (3)). */
export function stuckWhy(a: Attention, now: Date = new Date()): string {
  if (a.partition_stopped)
    return `${FAULT} It stopped while starting up and won't start again until Cadence is fixed.`;
  const tries =
    a.occurrences != null ? `${a.occurrences} ${a.occurrences === 1 ? "try" : "tries"}` : null;
  const since = a.first_seen_at ? `since ${short(a.first_seen_at, now)}` : null;
  const last = a.last_seen_at ? `the last at ${short(a.last_seen_at, now)}` : null;
  const count = [tries, since].filter(Boolean).join(" ");
  const facts = [count || null, last].filter(Boolean).join(", ");
  return `${FAULT} Cadence retries by itself and hits the same fault each time${facts ? `: ${facts}` : ""}.`;
}

export const STUCK_TODO =
  "Tell the team that runs Cadence for you, and send them the details. Nothing in the console fixes this.";

/** "3.3 of 8.6 GB": the unit once when both share it. */
function usedOf(used: number, max: number): string {
  const [u, uUnit] = size(used).split(" ");
  const m = size(max);
  return uUnit === m.split(" ")[1] ? `${u} of ${m}` : `${size(used)} of ${m}`;
}

/** The buffer line, storage and processing only; null on timer or without a buffer. */
export function bufferLine(a: Attention, now: Date = new Date()): string | null {
  if (a.dropping)
    return `Cadence's buffer is full, so new telemetry from ${a.path === "storage" ? "this pass" : "these spacecraft"} is being lost. ${
      a.dropping_since
        ? `Telemetry received before ${short(a.dropping_since, now)} is kept.`
        : "Telemetry already received is kept."
    }`;
  const b = a.buffer;
  if (!b) return null;
  return `Incoming telemetry is kept in Cadence's buffer meanwhile: ${usedOf(b.used_bytes, b.max_bytes)} used. Once it's full, new telemetry is lost.`;
}

/** The ack line; a re-raised item says the ack came before the loss (U84). Null when not acked. */
export function stuckAckLine(a: Attention, now: Date = new Date()): string | null {
  if (!a.acknowledged_by || !a.acknowledged_at) return null;
  const who = a.acknowledged_by.name ?? "an operator";
  const before = a.reraised ? ", before new telemetry started being lost" : "";
  const note = a.acknowledged_note?.trim();
  return `Acknowledged by ${who} at ${short(a.acknowledged_at, now)}${before}${note ? `: ${note.replace(/[.\s]+$/, "")}` : ""}.`;
}

/** Meta: dropping, stopped, or buffer · since · tries; ACK while acknowledged (not re-raised). */
export function stuckMeta(a: Attention, now: Date = new Date()): string {
  const ack =
    a.state === "acknowledged" && !a.reraised
      ? `ACK ${a.acknowledged_by?.name ?? ""}`.trim()
      : null;
  const since = a.first_seen_at ? `SINCE ${short(a.first_seen_at, now)}` : null;
  const parts = a.dropping
    ? ["BUFFER FULL", "LOSING NEW TELEMETRY"]
    : a.partition_stopped
      ? ["STOPPED", since]
      : [
          a.buffer && a.buffer.max_bytes > 0
            ? `BUFFER ${Math.floor((a.buffer.used_bytes / a.buffer.max_bytes) * 100)}%`
            : null,
          since,
          a.occurrences != null
            ? `${a.occurrences} ${a.occurrences === 1 ? "TRY" : "TRIES"}`
            : null,
        ];
  return [...parts, ack].filter(Boolean).join(" · ").toUpperCase();
}
