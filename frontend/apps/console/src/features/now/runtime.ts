import type { RouteLocationRaw } from "vue-router";
import { short, type Attention } from "./attention.ts";
import type { QueueItem } from "./queue.ts";

/**
 * U38 (ux 4f8b796c + bda6f91d; domain mission_runtime, generation_not_applied): the runtime hasn't
 * applied the active configuration, so no telemetry is processed for the whole mission. P1, no
 * Acknowledge, system-closed. Never "generation" in sentences, never "reconciler" or "spec".
 */
const noStop = (s: string) => s.trim().replace(/[.!?]+$/, "");

const KEEPS_TRYING = "Cadence keeps trying every 30 s.";
const NEEDS_FIX =
  "Retrying won't fix this. The configuration needs a fix, or a new one needs activating.";

/**
 * By domain's reason key (292c8e6b, final): the reason clause, then what happens next (ux). A fix
 * is needed for spec_mismatch and reconcile_crashed, so Review becomes the row's primary. Null or
 * an unknown key adds neither.
 */
export function reasonWords(
  reason: Attention["reason"],
  message: string | null | undefined,
): Readonly<{ text: string | null; needsFix: boolean }> {
  const why = message ? `: ${noStop(message)}` : "";
  switch (reason) {
    case "spec_mismatch":
      return { text: `What's running doesn't match it. ${NEEDS_FIX}`, needsFix: true };
    case "reconcile_crashed":
      return { text: `Cadence's apply process hit an error${why}. ${NEEDS_FIX}`, needsFix: true };
    case "runtime_not_running":
      return { text: `The runtime isn't running. ${KEEPS_TRYING}`, needsFix: false };
    case "apply_failed":
      return { text: `Applying it failed${why}. ${KEEPS_TRYING}`, needsFix: false };
    // contact_start's reasons (U45) share the field; its own row words them.
    case "listener_in_use":
    // U81 §3: another mission listens on the port; contactStart.ts words it (claimedWords).
    case "listen_endpoint_claimed":
    case "transport_archived":
    case "listener_unavailable":
    case "connect_failed":
    case "ingress_pipeline_failed":
    case "uplink_session_failed":
    case "no_runtime_spec":
    case "unknown":
    case null:
    case undefined:
    default:
      return { text: null, needsFix: false };
  }
}

export function runtimeEvidence(a: Attention): string {
  const running =
    a.applied_generation === null || a.applied_generation === undefined
      ? "no configuration is running"
      : "it's still running the earlier one";
  // No actor line: the server has no reliable activator (domain 292c8e6b, ux).
  return [
    `The runtime hasn't applied the active configuration; ${running}.`,
    reasonWords(a.reason, a.failure_message).text,
  ]
    .filter(Boolean)
    .join(" ");
}

/** `GENERATION 8 · RUNNING 7 · SINCE 23:10Z` (`RUNNING —` when none); the age follows live. */
export function runtimeMeta(a: Attention, now: Date = new Date()): string {
  return [
    a.desired_generation != null ? `Generation ${a.desired_generation}` : null,
    `Running ${a.applied_generation ?? "—"}`,
    a.since ? `Since ${short(a.since, now)}` : null,
  ]
    .filter(Boolean)
    .join(" · ")
    .toUpperCase();
}

export function runtimeRow(
  base: Pick<QueueItem, "priority" | "state" | "spacecraftIds">,
  key: string,
  a: Attention,
  missionName: string | null,
  now: Date = new Date(),
): QueueItem {
  // Review: Setup › Changes (no per-change-set deep link yet, so the list; ux's fallback).
  const to: RouteLocationRaw = { name: "setup.changes" };
  return {
    ...base,
    key,
    title: `${missionName ?? "This mission"} · Telemetry isn't being processed.`,
    titleTo: to,
    sentence: runtimeEvidence(a),
    meta: runtimeMeta(a, now),
    ...(a.since ? { due: { label: "", at: a.since } } : {}),
    action: { label: "Review", to },
    ...(reasonWords(a.reason, a.failure_message).needsFix ? { primary: true } : {}),
  };
}
