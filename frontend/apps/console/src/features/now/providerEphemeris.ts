import type { RouteLocationRaw } from "vue-router";
import {
  causeWords,
  ephemerisCauses,
  ephemerisReasonWords,
  type EphemerisCause,
} from "@/features/stations/ephemerisReasons.ts";
import { plural } from "@/ui";
import { serverKey, short, type Attention } from "./attention.ts";
import type { QueueItem } from "./queue.ts";

/**
 * provider_ephemeris (#972; ops.md): a provider that can't use some spacecraft's current orbit,
 * one row per provider and cause (and reason code), never per spacecraft. P2 from the server;
 * nothing to acknowledge, it leaves when its group empties. The item's `spacecraft` is only a
 * sample of 10, so the row names the provider and the count, and opens the provider's member list.
 */
const causeOf = (a: Attention): EphemerisCause | null => {
  const key = a.conflict === null ? null : serverKey(a.conflict);
  return ephemerisCauses.find((c) => c === key) ?? null;
};

/** Stations › Providers › this provider, its member list on this cause and reason. */
export function ephemerisRoute(a: Attention): RouteLocationRaw {
  const providerId = a.provider?.id;
  if (!providerId) return { name: "setup.stations.providers" };
  const cause = a.conflict === null ? null : serverKey(a.conflict);
  const reason = a.reason ? serverKey(a.reason) : null;
  return {
    name: "setup.stations.providers",
    params: { providerId },
    query: { ...(cause ? { cause } : {}), ...(reason ? { reason } : {}) },
  };
}

export function ephemerisRow(
  base: Pick<QueueItem, "priority" | "state" | "spacecraftIds">,
  key: string,
  a: Attention,
  /** The queue item's `since` (ops.md): when the group's earliest member entered this outcome. */
  since: string | null,
  now: Date = new Date(),
): QueueItem {
  const cause = causeOf(a);
  const provider = a.provider?.name?.trim() || "A provider";
  const count = a.spacecraft_count ?? base.spacecraftIds.length;
  const who = plural(count, "spacecraft", "spacecraft");
  const to = ephemerisRoute(a);
  const retry = a.next_retry_at ?? null;
  return {
    ...base,
    key,
    title: cause
      ? `${provider} · ${who} ${causeWords[cause]}`
      : `${provider} · ${who} whose orbits it can't use`,
    titleTo: to,
    sentence: cause
      ? ephemerisReasonWords(cause, a.reason ?? null)
      : `Cause not recognized (${a.conflict === null ? "none" : serverKey(a.conflict)}).`,
    meta: since ? `Since ${short(since, now)}`.toUpperCase() : null,
    ...(retry ? { due: { label: cause === "failed" ? "Retry" : "Re-check", at: retry } } : {}),
    action: { label: "Review", to },
  };
}
