import type { MissionId } from "@/api/index.ts";
import type { RouteLocationRaw } from "vue-router";
import { decoders as d, request, type ApiResult } from "@/api/index.ts";
import { attentionReader, serverKey, short, type Attention } from "./attention.ts";
import { passLabel } from "./ingress.ts";
import type { QueueItem } from "./queue.ts";

/**
 * job_outcome_unknown (ux U54; api-ops' shape, lead's changes): a job that isn't safe to rerun was
 * running when Cadence stopped, so nobody knows whether it finished. Say "outcome unknown", never
 * "failed" or "interrupted" (U20). The server sends each type's words (noun, place to check,
 * double-run consequence); they slot in as-is. An operator checks, then retries or closes.
 */

const UNKNOWN = {
  noun: "A Cadence job",
  check_place: "where it acts",
  consequence: "repeat what it did",
} as const;
export const jobWords = (a: Attention) => a.words ?? UNKNOWN;

/** `EARENDIL-312 · SVA 03:10Z pass · Booking at Northlight: outcome unknown`, or the noun alone. */
export function jobTitle(a: Attention, spacecraft: string | null, now: Date = new Date()) {
  const what = `${jobWords(a).noun}: outcome unknown`;
  return [spacecraft, passLabel(a, now), what].filter(Boolean).join(" · ");
}

/** `STARTED 03:01Z · FOUND AT RESTART 03:09Z`: the stop isn't recorded, only these two (U54). */
export function jobMeta(a: Attention, now: Date = new Date()): string | null {
  const found = a.found_at ?? a.raised_at;
  return [
    a.started_at ? `Started ${short(a.started_at, now)}` : null,
    `Found at restart ${short(found, now)}`,
  ]
    .filter((p): p is string => p !== null)
    .join(" · ")
    .toUpperCase();
}

/** How it closed, from the item (until the next read replaces the row). */
export function jobClosed(a: Attention, now: Date = new Date()): string | null {
  const r = a.resolution;
  if (a.state !== "resolved" || !r) return null;
  const who = r.actor.name ?? "an operator";
  if (r.action === "closed")
    return r.note
      ? `Closed without retry by ${who} at ${short(r.at, now)}: “${r.note.trim()}”`
      : `Closed without retry by ${who} at ${short(r.at, now)}.`;
  return `Retried by ${who} at ${short(r.at, now)}; it's queued.`;
}

export function jobEvidence(a: Attention, now: Date = new Date()): string {
  const closed = jobClosed(a, now);
  if (closed) return closed;
  const w = jobWords(a);
  return `Cadence stopped while this was running, so it doesn't know whether it finished. It won't run it again by itself: running it twice could ${w.consequence}. Check ${w.check_place}, then retry it or close this.`;
}

export const NO_ACCESS_JOB = "Operators decide what happens to jobs whose outcome is unknown.";

/** Which of Retry / Close the item offers (the server's list for this viewer). */
export const jobOffers = (a: Attention, action: "retry" | "close") =>
  a.state !== "resolved" && (a.actions == null || a.actions.includes(action));

/** Technical details (U54): job id, type key, worker, attempt, node, run id, and the item id. */
export function jobTechnical(a: Attention): readonly string[] {
  const j = a.job;
  return [
    j ? `job: ${j.id}` : null,
    j ? `type: ${serverKey(j.type_key)}` : null,
    j?.worker ? `worker: ${j.worker}` : null,
    j?.attempt != null ? `attempt: ${j.attempt}` : null,
    j?.node ? `node: ${j.node}` : null,
    j?.run_id ? `run: ${j.run_id}` : null,
    `id: ${a.id}`,
  ].filter((l): l is string => l !== null);
}

/** Retry sheet (U54, title 'Retry this job?'): the noun on its own line, then this. */
export const retryBody = (a: Attention) => {
  const w = jobWords(a);
  return `Retry only if you've checked ${w.check_place} that it didn't happen. If it did, retrying could ${w.consequence}.`;
};
export const retryCheck = (a: Attention) =>
  `I've checked ${jobWords(a).check_place}: it didn't happen.`;
export const CLOSE_BODY =
  "Use this when you've checked that it finished, or when it shouldn't run again. Cadence leaves the job as it is.";

const itemPath = (missionId: MissionId, a: Attention) =>
  `/missions/${encodeURIComponent(missionId)}/attention/${encodeURIComponent(serverKey(a.source))}/${encodeURIComponent(a.id)}`;

/** 202 {item, run}: only the item is read; the job's own run shows where the job shows. */
const retried = d.object({ item: attentionReader });

/** POST …/retry {confirmed: true, note?}: the job is queued again. */
export async function retryJob(
  missionId: MissionId,
  a: Attention,
  note: string,
): Promise<ApiResult<Attention>> {
  const r = await request(`${itemPath(missionId, a)}/retry`, retried, {
    method: "POST",
    body: { confirmed: true, ...(note ? { note } : {}) },
  });
  return r.ok ? { ok: true, value: r.value.item } : r;
}

/** Close without retry = resolve with the required note as action_text. */
export function closeJob(missionId: MissionId, a: Attention, note: string) {
  return request(`${itemPath(missionId, a)}/resolve`, attentionReader, {
    method: "POST",
    body: { action_text: note },
  });
}

export function jobRow(
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
  const closed = a.state === "resolved";
  return {
    ...base,
    ...(closed ? { state: "off" as const } : {}),
    key,
    title: jobTitle(a, spacecraftName, now),
    titleTo: pass ? to : null,
    sentence: jobEvidence(a, now),
    meta: jobMeta(a, now),
    action: { label: "Open pass", to },
    // Without a pass there's nowhere to open; operators still get Retry… and Close….
    ...(pass ? {} : { noAction: true }),
    ...(jobOffers(a, "retry") || jobOffers(a, "close") ? { job: a } : {}),
  };
}
