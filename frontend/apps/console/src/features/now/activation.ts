import type { RouteLocationRaw } from "vue-router";
import { short, type Attention } from "./attention.ts";
import type { QueueItem } from "./queue.ts";

/**
 * activation_apply (domain 9b8456132 / 8f30aac21, L10 resume; ux U41): an approved activation
 * whose apply failed, or stopped partway with nothing still working on it. One row per request,
 * linking to its review page (fe-setup's setup.activation), where Retry apply lives. Nothing to
 * acknowledge: it closes when the apply succeeds or a newer activation replaces it.
 *
 * The server's `error` is U41's sentence (it names the spacecraft when there's one), and
 * `retryable` says whether retrying can help; the console keeps no code list of its own.
 */
const AGAIN = "Request activation again so the current version can be approved.";

export function activationWords(a: Attention): Readonly<{ title: string; evidence: string }> {
  const parts = [
    a.error ?? "Applying failed.",
    a.runtime_not_applied ? "Telemetry isn't being processed until this applies." : null,
    a.retryable === false ? AGAIN : null,
  ];
  return {
    title: `${a.summary ?? "An approved activation"} · approved, not applied`,
    evidence: parts.filter(Boolean).join(" "),
  };
}

/** U41 meta: `APPROVED BY MIRA K. AT 02:10Z · SINCE 02:14Z`, dropping what the server doesn't say. */
export function activationMeta(a: Attention, now: Date = new Date()): string | null {
  const by = a.approved_by?.name;
  const approved = a.approved_at
    ? `Approved${by ? ` by ${by}` : ""} at ${short(a.approved_at, now)}`
    : by
      ? `Approved by ${by}`
      : null;
  const parts = [approved, a.since ? `since ${short(a.since, now)}` : null].filter(
    (p): p is string => Boolean(p),
  );
  return parts.length ? parts.join(" · ").toUpperCase() : null;
}

export function activationRow(
  base: Pick<QueueItem, "priority" | "state" | "spacecraftIds">,
  key: string,
  a: Attention,
  now: Date = new Date(),
): QueueItem {
  const requestId = a.activation_request_id ?? a.id;
  const to: RouteLocationRaw = { name: "setup.activation", params: { requestId } };
  const w = activationWords(a);
  return {
    ...base,
    key,
    title: w.title,
    titleTo: to,
    sentence: w.evidence,
    meta: activationMeta(a, now),
    action: { label: "Review", to },
    // U41: P1 while telemetry isn't processed; the fix is here, so the action leads.
    ...(a.runtime_not_applied ? { primary: true } : {}),
  };
}
