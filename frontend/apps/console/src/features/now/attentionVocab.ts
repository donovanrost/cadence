import { isKnown, type Unrecognized } from "@/api/index.ts";

/** The attention vocabularies: sources, conflicts and each source's reason keys (U31…U81). */

/** The attention sources the console words (ops.md §attention, contacts.md U33, #71, U38). */
export const attentionSources = [
  "pass_resolution",
  "uplink_blocked",
  "pass_release",
  "contact_settlement",
  "mission_runtime",
  // An approved activation whose apply failed or stalled (domain 9b8456132, L10 resume).
  "activation_apply",
  // §11 L14 (api 30b3f60b9): a provider changed a booked pass.
  "provider_change",
  // U45: a realized contact that failed to start; cleared when it starts (domain, api).
  "contact_start",
  // U47 (api-ops, #83): a contact's ingest buffer backing up, or frames a transport dropped.
  "ingress_backpressure",
  // U49 (#88): a contact's raw records the archive couldn't take; their telemetry was stored.
  "archive_quarantine",
  // U50 (#87): connections a shared listener refused during this pass's window.
  "listener_refusal",
  // U54 (api-ops): a job that isn't safe to rerun was running when Cadence stopped.
  "job_outcome_unknown",
  // U61 (api, domain 47aabe3ba): a day whose first window nears with no approved plan.
  "plan_coverage",
  // U75 (api 5766e494a, #97): a command request that expired before all of it went out.
  "expired_group",
  // U81 §2 (api, #102): most of a settled contact's frames carried another SCID.
  "contact_scid_mismatch",
  // U84 (api, after #99): processing stuck on a fault in Cadence ("Stuck processing").
  "replay_conflict",
  // U109 (E2, #546): a craft on a composition that's no longer approved.
  "model_approval_withdrawn",
] as const;
/** pass_resolution conflicts (ops.md §attention). */
export const attentionConflicts = [
  "cancel_failed",
  "late_confirmation",
  "contradicts_attestation",
  // contact_settlement (#71) and mission_runtime (U38).
  "unsettled",
  "generation_not_applied",
  // activation_apply: execution failed, or in progress >10 min with no live executor.
  "apply_failed",
  "apply_stalled",
  // provider_change: decide before deadline_at · already applied · shown only.
  "approval_required",
  "acknowledgment_required",
  "configuration_failure",
  // contact_start (U45): failing to start while the pass is on · its window ended unstarted.
  "not_started",
  "missed",
  // ingress_backpressure (U47): the buffer is >= 80% full · frames were lost.
  "journal_near_full",
  "frames_dropped",
  // U66: the buffer DISK every pass shares (one item per mission, no pass of its own).
  "journal_disk",
  // archive_quarantine (U49): one item per contact and error code.
  "quarantined",
  // listener_refusal (U50): one item per open contact on the shared listener.
  "listener_refusal",
  // job_outcome_unknown (U54): one item per cut-off run.
  "outcome_unknown",
  // replay_conflict (U84): one item per stuck unit.
  "replay_id_conflict",
] as const;
/** U50 listener_refusal: why the shared listener refused the last connection. */
export const listenerRefusals = [
  "unregistered_scid",
  "ambiguous_scid",
  "unexpected_peer",
  "unidentified",
  "read_failed",
  "unknown",
  // U50: a second connection while this pass's own was up (counted; opens only if it's quiet).
  "second_connection",
] as const;
/** U38 mission_runtime reason keys (domain 292c8e6b, final). */
export const runtimeReasons = [
  "spec_mismatch",
  "reconcile_crashed",
  "runtime_not_running",
  "apply_failed",
] as const;
/** U45 contact_start: why the pass didn't start (domain's keys; null: no reason recorded). */
export const startReasons = [
  "listener_in_use",
  // U81 §3: another mission listens on the port our transport uses.
  "listen_endpoint_claimed",
  // U45 (api, Archive control): the pass's path is pinned to an archived transport's profile.
  "transport_archived",
  "listener_unavailable",
  "connect_failed",
  "ingress_pipeline_failed",
  "uplink_session_failed",
  "no_runtime_spec",
  "unknown",
] as const;
/** U37 contact_settlement: why the telemetry isn't stored (null: a slow drain past the deadline). */
export const settlementFailures = [
  "telemetry_storage_unavailable",
  "settle_failed",
  // U84: the stored failure is the stuck processing (the item carries stuck_processing_id).
  "replay_id_conflict",
] as const;

/** The server's own key, known or not: attention routes, fold keys. */
export const serverKey = <T extends string>(value: T | Unrecognized): string =>
  isKnown(value) ? value : value.unrecognized;

/**
 * How an attention item closed, as far as the console words it (U32, U37, U38, U41, U44, U45, U47,
 * U49, U50, U54, U61). Anything else arrives as the server's own phrase and is shown as said.
 */
export const resolutionActions = [
  "acknowledged",
  "accepted",
  "applied",
  "approved",
  "closed",
  "day_ended",
  // U61 (domain 702223355): booking began after the grace, or resumed after a stop.
  "booking_started",
  "discarded",
  "drained",
  "ended",
  "nothing_left",
  "rejected",
  "replayed",
  "retried",
  // U84 replay_conflict: the system closed it when the fix landed (per-path words).
  "resumed",
  // U81 §2 contact_scid_mismatch: unseen 7 days after settle; marked seen (the person, with name).
  "retired",
  "seen",
  "started",
  "superseded",
] as const;
export type ResolutionAction = (typeof resolutionActions)[number];
/** The action as text: a known key, or the server's (or operator's) own words. */
export const actionText = (action: ResolutionAction | Unrecognized): string =>
  isKnown(action) ? action : action.unrecognized;
