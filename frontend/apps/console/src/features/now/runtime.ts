import type { RouteLocationRaw } from "vue-router";
import { short, type Attention } from "./attention.ts";
import type { QueueItem } from "./queue.ts";
import { NO_TELEMETRY, nextPassLine } from "./runtimePass.ts";

/**
 * U38 (ux 4f8b796c + bda6f91d; domain mission_runtime, generation_not_applied): the runtime hasn't
 * applied the active configuration, so no telemetry is processed for the whole mission. P1, no
 * Acknowledge, system-closed. Never "generation" in sentences, never "reconciler" or "spec".
 */
const noStop = (s: string) => s.trim().replace(/[.!?]+$/, "");

const KEEPS_TRYING = "Cadence keeps trying every 30 s.";
/** U91: spec_mismatch and reconcile_crashed are faults in Cadence; nothing in the console fixes them. */
const TELL_TEAM =
  "It's a fault in Cadence, not in this mission's setup. Tell the team that runs Cadence for you; nothing in the console fixes it.";

/**
 * By domain's reason key (292c8e6b, final): the reason clause, then what happens next (ux). U91:
 * spec_mismatch and reconcile_crashed need a fix in Cadence (tell the team), with no Review
 * primary and never a suggestion to activate again. Null or an unknown key adds nothing.
 */
export function reasonWords(
  reason: Attention["reason"],
  message: string | null | undefined,
): Readonly<{ text: string | null }> {
  const why = message ? `: ${noStop(message)}` : "";
  switch (reason) {
    case "spec_mismatch":
      return { text: TELL_TEAM };
    case "reconcile_crashed":
      return { text: `Cadence's apply process hit an error${why}. ${TELL_TEAM}` };
    case "runtime_not_running":
      return { text: `The runtime isn't running. ${KEEPS_TRYING}` };
    case "apply_failed":
      return { text: `Applying it failed${why}. ${KEEPS_TRYING}` };
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
      return { text: null };
  }
}

export function runtimeEvidence(a: Attention, now: Date = new Date()): string {
  const nothing = a.applied_generation === null || a.applied_generation === undefined;
  const running = nothing ? "no configuration is running" : "it's still running the earlier one";
  // U91: spec_mismatch reads as Cadence failing to verify it, not as a mismatch to activate past.
  const what =
    a.reason === "spec_mismatch"
      ? `Cadence can't verify this mission's active configuration, so it won't run it.${nothing ? "" : " It's still running the earlier one."}`
      : `The runtime hasn't applied the active configuration; ${running}.`;
  // No actor line: the server has no reliable activator (domain 292c8e6b, ux).
  return [
    what,
    reasonWords(a.reason, a.failure_message).text,
    // U91: only while nothing runs do passes fail to start for it.
    nothing ? NO_TELEMETRY : null,
    nextPassLine(a.next_pass, now),
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
    sentence: runtimeEvidence(a, now),
    meta: runtimeMeta(a, now),
    ...(a.since ? { due: { label: "", at: a.since } } : {}),
    action: { label: "Review", to },
  };
}
