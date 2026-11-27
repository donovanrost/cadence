import type { RouteLocationRaw } from "vue-router";
import { isKnown } from "@/api/index.ts";
import { plural } from "@/ui";
import { serverKey, short, type Attention } from "./attention.ts";
import { passLabel } from "./ingress.ts";
import type { QueueItem } from "./queue.ts";

/**
 * listener_refusal (ux U50; DECISIONS #87): a listener this pass shares with others refused
 * connections it couldn't match to exactly one pass. Never "someone else's frames" (U20): a refused
 * one may be this pass's own. Visible text says "connection"; the address, scid key and counts'
 * liveness stay in Technical details. P1/P2 is api's (P1 while not connected in the window).
 */

const connections = (n: number) => plural(n, "connection");

/** `EARENDIL-008 · SVB 03:10Z pass · 3 connections refused`. */
export function listenerTitle(a: Attention, spacecraft: string | null, now: Date = new Date()) {
  const what = `${connections(a.refused_count ?? 1)} refused`;
  return [spacecraft, passLabel(a, now), what].filter(Boolean).join(" · ");
}

const STILL_MS = 5 * 60_000;

/** `FIRST 03:12Z · LAST 03:14Z · STILL REFUSING`; one time when they're equal. */
export function listenerMeta(a: Attention, now: Date = new Date()): string | null {
  const first = a.raised_at;
  const last = a.last_refused_at ?? null;
  const still =
    a.state !== "resolved" && last !== null && now.getTime() - Date.parse(last) <= STILL_MS;
  return [
    `First ${short(first, now)}`,
    last && last !== first ? `Last ${short(last, now)}` : null,
    still ? "Still refusing" : null,
  ]
    .filter((p): p is string => p !== null)
    .join(" · ")
    .toUpperCase();
}

function reasonSentence(a: Attention): string {
  const r = a.last_refusal;
  const scid = r?.scid;
  const reason = r && isKnown(r.reason) ? r.reason : "unknown";
  switch (reason) {
    case "unregistered_scid":
      return scid != null
        ? `The last one sent frames for SCID ${scid}, which no pass on this listener expects.`
        : "The last one sent frames for a spacecraft no pass on this listener expects.";
    case "ambiguous_scid":
      return scid != null
        ? `The last one sent frames for SCID ${scid}, which more than one pass on this listener expects.`
        : "The last one sent frames for a spacecraft more than one pass on this listener expects.";
    case "unidentified":
      return "Cadence couldn't tell from its first frames which spacecraft the last one was for.";
    case "read_failed":
      return "Cadence couldn't read the last one's first frames.";
    case "unknown":
      return "Cadence couldn't match the last one to a pass.";
    case "second_connection":
      return "The last one was a second connection for this pass, and Cadence keeps the first.";
    case "no_registered_contact":
      return "No pass was registered on this listener when the last one arrived.";
    case "peer_not_allowed":
      return "The last one came from an address outside this listener's allowed source addresses, so Cadence refused it before reading anything.";
  }
}

const ALLOWED = "allowed source addresses";

/**
 * #993: peer_not_allowed's fix names who owns the allowlist. A provider's comes from its delivery
 * profile's egress (only the provider changes it); a Cadence transport's is edited in Setup, the
 * words linked to it. Unknown owner: a sentence true for both.
 */
export function peerFix(a: Attention): Readonly<{ text: string; to: RouteLocationRaw | null }> {
  const provider = a.provider?.name ?? null;
  const owner = a.allowlist_source && isKnown(a.allowlist_source) ? a.allowlist_source : null;
  if (owner === "provider")
    return {
      text: `Ask ${provider ?? "the provider"} to check the source addresses it connects from; Cadence can't change them.`,
      to: null,
    };
  if (owner === "transport")
    return {
      text: `Edit the transport's ${ALLOWED} in Setup.`,
      to: a.transport_id
        ? { name: "setup.comms.transports", params: { transportId: a.transport_id } }
        : null,
    };
  return { text: `Check who sets this listener's ${ALLOWED}.`, to: null };
}

/** Context, the last refusal's reason, then this pass's state (U50). */
export function listenerEvidence(
  a: Attention,
  spacecraft: string | null,
  now: Date = new Date(),
): string {
  const provider = a.provider?.name ?? null;
  const listener = provider ? `${provider}'s listener` : "the listener";
  const others = a.shared_with?.length ?? 0;
  // U50: from shared_with, never as this pass's fault (each open pass gets its own row).
  const context = others
    ? `This pass shares ${listener} with ${plural(others, "other open pass", "other open passes")}, and Cadence refuses any connection it can't match to exactly one of them.`
    : `Cadence refuses any connection on ${listener} that it can't match to this pass.`;
  // U50: its own connection gone quiet reads first; "connected" may still be true.
  if (a.own_quiet_since)
    return `${context} ${reasonSentence(a)} This pass's own connection has sent nothing since ${short(a.own_quiet_since, now)}. If the refused connection was the provider reconnecting, its telemetry isn't arriving.`;
  if (a.connected === true)
    return `${context} ${reasonSentence(a)} This pass has its own connection.`;
  const reason = a.last_refusal?.reason;
  const setup =
    reason === "unregistered_scid"
      ? ` Check ${spacecraft ? `${spacecraft}'s` : "the spacecraft's"} SCID and ${provider ? `${provider}'s` : "the provider's"} profile in Setup.`
      : reason === "peer_not_allowed"
        ? ` ${peerFix(a).text}`
        : "";
  return `${context} ${reasonSentence(a)} This pass isn't connected yet. If a refused connection was meant for it, its telemetry isn't arriving.${setup}`;
}

/** Technical details (U50): the keys, the address, the profile and the count's liveness. */
export function listenerTechnical(a: Attention): readonly string[] {
  const r = a.last_refusal;
  return [
    r ? `reason: ${serverKey(r.reason)}` : null,
    r?.peer ? `peer: ${r.peer}` : null,
    r?.scid != null ? `scid: ${r.scid}` : null,
    a.provider_profile_name || a.provider_profile_id
      ? `listen profile: ${[a.provider_profile_name, a.provider_profile_id].filter(Boolean).join(" · ")}`
      : null,
    a.ground_station_ref ? `ground_station_ref: ${a.ground_station_ref}` : null,
    a.refused_count != null ? `refused: ${a.refused_count}` : null,
    `id: ${a.id}`,
    "Counted live: a Cadence restart starts the count again.",
  ].filter((l): l is string => l !== null);
}

export function listenerRow(
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
  const sentence = listenerEvidence(a, spacecraftName, now);
  // #993: a Cadence transport's allowlist is edited in Setup; those words link there.
  const fix = a.last_refusal?.reason === "peer_not_allowed" ? peerFix(a) : null;
  const at = fix?.to ? sentence.lastIndexOf(ALLOWED) : -1;
  return {
    ...base,
    key,
    title: listenerTitle(a, spacecraftName, now),
    titleTo: to,
    sentence,
    ...(fix?.to && at >= 0
      ? {
          sentenceParts: [
            sentence.slice(0, at),
            { text: ALLOWED, to: fix.to },
            sentence.slice(at + ALLOWED.length),
          ],
        }
      : {}),
    meta: listenerMeta(a, now),
    // U50: no server actions, so Open pass takes the free slot.
    action: { label: "Open pass", to },
    ...(a.ends_at ? { due: { label: "LOS", at: a.ends_at } } : {}),
  };
}
