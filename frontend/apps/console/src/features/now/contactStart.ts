import type { RouteLocationRaw } from "vue-router";
import { plural } from "@/ui";
import { short, startReasons, type Attention } from "./attention.ts";
import type { QueueItem } from "./queue.ts";

/**
 * contact_start (ux U45; domain + api shape 11-14): a realized contact that failed to start. While
 * the pass is on it reads "hasn't started" (P1, due at LOS) and Cadence retries on its own; once
 * its window ends unstarted it reads "was missed" (P2) and stays until an operator marks it seen.
 * The reason key and failure_message stay out of the line (the pass detail's Technical details).
 */
export type StartReason = (typeof startReasons)[number];
type Holder = NonNullable<Attention["holder"]>;

/** The item's reason when it's one of U45's keys; null when missing or not one of them. */
export const startReasonOf = (a: Attention): StartReason | null =>
  startReasons.find((k) => k === a.reason) ?? null;

/** "EARENDIL-047 · SVA 02:55Z pass", dropping what the server doesn't say. */
export function holderPass(h: Holder, now: Date = new Date()): string {
  const where = [h.station?.code ?? h.station?.name, h.starts_at ? short(h.starts_at, now) : null]
    .filter((p): p is string => Boolean(p))
    .join(" ");
  const name = h.spacecraft?.name;
  return `${[name, where].filter(Boolean).join(" · ")}${name || where ? " " : ""}pass`;
}

const REASON_WORDS: Readonly<
  Record<Exclude<StartReason, "listener_in_use" | "listen_endpoint_claimed">, string>
> = {
  listener_unavailable: "Cadence couldn't open the station connection on its side.",
  connect_failed: "Cadence couldn't reach the provider's endpoint for this pass.",
  ingress_pipeline_failed: "Cadence couldn't start storing telemetry for this pass.",
  uplink_session_failed: "Cadence couldn't start the uplink session for this pass.",
  no_runtime_spec: "The mission's runtime has no active configuration, so passes can't start.",
  unknown: "Starting failed.",
};

/** U81 §3: another mission holds our transport's port. The other mission is never named. */
function claimedWords(a: Attention): string {
  const port = a.listen_port != null ? ` (${a.listen_port})` : "";
  const fix = "Change that transport's port.";
  if (a.transport_name)
    return `Another mission already listens on the port ${a.transport_name} uses${port}. ${fix}`;
  const on = a.listen_port != null ? `port ${a.listen_port}` : "the port";
  return `Another mission already listens on ${on}, which this pass's transport uses. ${fix}`;
}

/** U45's reason line; a key this console doesn't know reads as unknown, a missing one says so. */
export function startReasonWords(a: Attention, now: Date = new Date()): string {
  const reason = startReasonOf(a);
  if (reason === "listener_in_use")
    return `Cadence couldn't open the station connection because ${a.holder ? `the ${holderPass(a.holder, now)}` : "another pass"} was still holding it.`;
  if (reason === "listen_endpoint_claimed") return claimedWords(a);
  if (reason === "connect_failed" && a.provider?.name)
    return `Cadence couldn't reach ${a.provider.name}'s endpoint for this pass.`;
  if (reason) return REASON_WORDS[reason];
  return a.reason ? REASON_WORDS.unknown : "No reason was recorded.";
}

/** ux U45: reasons whose fix is elsewhere get a second action. */
export function startReasonAction(
  a: Attention,
): Readonly<{ label: string; to: RouteLocationRaw }> | null {
  switch (startReasonOf(a)) {
    case "connect_failed":
      return { label: "Check provider", to: { name: "setup.stations.providers" } };
    case "no_runtime_spec":
      return { label: "Open Changes", to: { name: "setup.changes" } };
    case "listen_endpoint_claimed":
      return a.transport_id
        ? {
            label: "Open transport",
            to: { name: "setup.comms.transports", params: { transportId: a.transport_id } },
          }
        : null;
    case "listener_in_use":
    case "listener_unavailable":
    case "ingress_pipeline_failed":
    case "uplink_session_failed":
    case "unknown":
    case null:
      return null;
  }
}

const missed = (a: Attention) => a.conflict === "missed";

/** "SVA 03:10Z pass hasn't started" / "was missed" (U45 title tail). */
export function startTitle(a: Attention, now: Date = new Date()): string {
  const where = [a.station?.code ?? a.station?.name, a.starts_at ? short(a.starts_at, now) : null]
    .filter((p): p is string => Boolean(p))
    .join(" ");
  const pass = where ? `${where} pass` : "Pass";
  return `${pass} ${missed(a) ? "was missed" : "hasn't started"}`;
}

export function startEvidence(a: Attention, now: Date = new Date()): string {
  const why = startReasonWords(a, now);
  return missed(a) ? `The pass ended before Cadence could start it. ${why}` : why;
}

/** U45 meta: `CADENCE IS RETRYING · 3 TRIES` while on (tries only if sent); the LOS countdown follows. */
export function startMeta(a: Attention, now: Date = new Date()): string | null {
  if (!missed(a))
    return ["Cadence is retrying", a.attempts != null ? plural(a.attempts, "try", "tries") : null]
      .filter(Boolean)
      .join(" · ")
      .toUpperCase();
  const window = a.starts_at
    ? `${short(a.starts_at, now)}${a.ends_at ? `–${short(a.ends_at, now)}` : ""}`
    : null;
  const parts = [a.provider_profile_name ?? a.provider?.name, window].filter((p): p is string =>
    Boolean(p),
  );
  return parts.length ? parts.join(" · ").toUpperCase() : null;
}

export function contactStartRow(
  base: Pick<QueueItem, "priority" | "state" | "spacecraftIds">,
  key: string,
  a: Attention,
  spacecraftName: string | null,
  now: Date = new Date(),
): QueueItem {
  const pass = a.reservation_id ?? a.contact_id;
  const to: RouteLocationRaw = pass
    ? { name: "ops.contacts", query: { contact: pass } }
    : { name: "ops.contacts" };
  return {
    ...base,
    key,
    title: `${spacecraftName ?? "Spacecraft"} · ${startTitle(a, now)}`,
    titleTo: to,
    sentence: startEvidence(a, now),
    meta: startMeta(a, now),
    action: { label: "Open pass", to },
    ...(missed(a)
      ? { command: { label: "Mark as seen", kind: "seen" as const, targets: [a] } }
      : a.ends_at
        ? { due: { label: "LOS", at: a.ends_at } }
        : {}),
  };
}
