import type { RouteLocationRaw } from "vue-router";
import { decoders as d } from "@/api/index.ts";
import { plural } from "@/ui";
import type { Attention } from "./attention.ts";
import { short } from "./attention.ts";
import type { QueueItem } from "./queue.ts";

/**
 * expired_group (ux U75, api 5766e494a): a command request that expired before all of it went out
 * (DECISIONS #97). One item per request, P2; caution when part of it went out, info when none did.
 * Mark as seen acknowledges it. Its own fields, spread into the attention reader, all optional.
 */
export const expiredGroupFields = {
  group: d.optional(d.nullable(d.object({ id: d.token, title: d.string }))),
  target_count: d.optional(d.nullable(d.integer)),
  sent: d.optional(d.nullable(d.integer)),
  total: d.optional(d.nullable(d.integer)),
  expired_at: d.optional(d.nullable(d.timestamp)),
} as const;

/**
 * 'EARENDIL-004 · Low power safe expired before all its uplinks went out'; several targets:
 * 'Low power safe expired on 3 spacecraft before…'; none sent: '…before any uplink went out'.
 */
export function expiredTitle(a: Attention, spacecraft: string | null): string {
  const title = a.group?.title ?? "A command request";
  const several = (a.target_count ?? 1) > 1;
  const on = several ? ` on ${plural(a.target_count ?? 0, "spacecraft", "spacecraft")}` : "";
  const tail = (a.sent ?? 0) > 0 ? "before all its uplinks went out" : "before any uplink went out";
  const head = !several && spacecraft ? `${spacecraft} · ` : "";
  return `${head}${title} expired${on} ${tail}`;
}

/** '2 OF 5 SENT · EXPIRED 04:00Z' / 'NONE SENT · EXPIRED 04:00Z'. */
export function expiredMeta(a: Attention, now: Date = new Date()): string {
  const sent = a.sent ?? 0;
  const head = sent > 0 ? `${sent} of ${a.total ?? sent} sent` : "None sent";
  const at = a.expired_at ? ` · Expired ${short(a.expired_at, now)}` : "";
  return `${head}${at}`.toUpperCase();
}

/** The Now row: Open goes to the request; Mark as seen acknowledges (no resolve). */
export function expiredRow(
  base: Pick<QueueItem, "priority" | "state" | "spacecraftIds">,
  key: string,
  a: Attention,
  spacecraft: string | null,
  now: Date = new Date(),
): QueueItem {
  const to: RouteLocationRaw = a.group
    ? { name: "ops.commands.request", params: { requestId: a.group.id } }
    : { name: "ops.commands" };
  const sent = a.sent ?? 0;
  const sentence =
    sent > 0
      ? `${sent} of ${plural(a.total ?? sent, "uplink")} went out; the rest expired before they were sent.`
      : "None of its uplinks went out before it expired.";
  return {
    ...base,
    key,
    title: expiredTitle(a, spacecraft),
    titleTo: to,
    sentence,
    meta: expiredMeta(a, now),
    action: { label: "Open", to },
    ...(a.state === "open"
      ? { command: { label: "Mark as seen", kind: "seen" as const, targets: [a] } }
      : {}),
  };
}
