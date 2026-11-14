import type { RouteLocationRaw } from "vue-router";
import { plural } from "@/ui";
import { short, type Attention } from "./attention.ts";
import type { QueueItem } from "./queue.ts";

/**
 * ingress_backpressure (ux U47; api-ops' shape, #83): one contact's downlink buffer backing up
 * (journal_near_full, clears itself when it drains), or frames a transport dropped because its
 * buffer was full (frames_dropped, data loss, acknowledged by an operator). Visible text says
 * "buffer", never "journal"; the stream and raw error stay in Technical details. Nobody is named
 * to tell: the Now row is the notice (ux). State lives in node memory (api-ops).
 */

const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;

/** "412 MB", "6.9 MB", "48 KB": no trailing ".0", whole numbers from 100 up (U47). */
export function size(bytes: number): string {
  const [v, unit] =
    bytes >= 1e9
      ? [bytes / 1e9, "GB"]
      : bytes >= 1e6
        ? [bytes / 1e6, "MB"]
        : bytes >= 1e3
          ? [bytes / 1e3, "KB"]
          : [bytes, "B"];
  return `${v >= 100 || unit === "B" ? Math.round(v) : Number(v.toFixed(1))} ${unit}`;
}

/** "SVB 03:10Z pass", or "SVB contact" when it isn't a booked pass (U47). */
export function contactName(a: Attention, now: Date = new Date()): string {
  const station = a.station?.code ?? a.station?.name ?? null;
  const pass = a.reservation_id != null || a.contact_label != null;
  if (pass) {
    const where = [station, a.starts_at ? short(a.starts_at, now) : null].filter(Boolean).join(" ");
    return where ? `${where} pass` : "pass";
  }
  return station ? `${station} contact` : "contact";
}

/**
 * U47's label, or null with nothing to name. api renders a passless item's station as an object
 * of nulls ({ref: null, …}), so "has a station" means it has a code or name, not that it's set.
 */
export function passLabel(a: Attention, now: Date = new Date()): string | null {
  const station = a.station?.code ?? a.station?.name ?? null;
  const pass = a.reservation_id != null || a.contact_label != null;
  return station || pass ? contactName(a, now) : null;
}

const frames = (n: number) => plural(n, "telemetry frame", "telemetry frames");

export function ingressTitle(a: Attention, now: Date = new Date()): string {
  // U47: without a station or pass, the spacecraft alone (the row adds it).
  const where = passLabel(a, now);
  const what =
    a.conflict === "frames_dropped" && a.drops
      ? `${frames(a.drops.count)} lost`
      : "telemetry is backing up";
  return where ? `${where} · ${what}` : what.charAt(0).toUpperCase() + what.slice(1);
}

const BACKING_UP = "Cadence is storing this pass's telemetry more slowly than it arrives.";
const STOPS = "At 100% Cadence stops reading, and new telemetry arrives late.";

export function ingressEvidence(a: Attention): string {
  if (a.conflict === "frames_dropped")
    return `Cadence's buffer was full, so these frames from ${a.provider?.name ?? "the provider"} were dropped. Cadence can't recover them.`;
  const full = (a.journal_usage?.ratio ?? 0) >= 0.95;
  return `${full ? "The buffer is almost full. " : ""}${BACKING_UP} ${STOPS}`;
}

/** `BUFFER 87% · RISING · 412 MB WAITING` / `12 FRAMES · 48 KB · 03:14Z–03:15Z`. */
export function ingressMeta(a: Attention): string | null {
  const ack = a.state === "acknowledged" ? `Ack ${a.acknowledged_by?.name ?? ""}`.trim() : null;
  let parts: readonly (string | null)[] = [];
  if (a.conflict === "frames_dropped" && a.drops) {
    const d = a.drops;
    const span =
      d.first_at === d.last_at ? hhmm(d.first_at) : `${hhmm(d.first_at)}–${hhmm(d.last_at)}`;
    parts = [plural(d.count, "frame"), size(d.bytes), span, ack];
  } else if (a.journal_usage) {
    const u = a.journal_usage;
    parts = [
      `Buffer ${Math.floor(u.ratio * 100)}%`,
      u.rising ? "Rising" : null,
      u.backlog_bytes > 0 ? `${size(u.backlog_bytes)} waiting` : null,
    ];
  }
  const shown = parts.filter((p): p is string => Boolean(p));
  return shown.length ? shown.join(" · ").toUpperCase() : null;
}

export function ingressRow(
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
  const lost = a.conflict === "frames_dropped";
  const acknowledged = a.state === "acknowledged";
  return {
    ...base,
    key,
    title: `${spacecraftName ?? "Spacecraft"} · ${ingressTitle(a, now)}`,
    titleTo: to,
    sentence: ingressEvidence(a),
    meta: ingressMeta(a),
    action: { label: "Open pass", to },
    ...(acknowledged ? { acknowledged: true } : {}),
    // U47: lost frames are acknowledged (no reason); a backlog clears by itself.
    ...(lost && !acknowledged
      ? { command: { label: "Acknowledge", kind: "seen" as const, targets: [a] } }
      : {}),
  };
}
