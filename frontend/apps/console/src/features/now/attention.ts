import {
  decoders as d,
  isKnown,
  spacecraftId as spacecraftIdReader,
  type Decoded,
  type Unrecognized,
} from "@/api/index.ts";
import type { QueueItem } from "./queue.ts";
import { plural } from "@/ui";
import { formatBytes } from "@/features/catalog/importRun.ts";
import { attentionUplinkReader, reasonSentence } from "@/features/contacts/readiness.ts";
import { coveragePlanStates, planCoverageFields } from "./coverageFields.ts";
import { expiredGroupFields } from "./expiredGroup.ts";
import { diskResolvedWords, journalDiskFields } from "./journalDisk.ts";

/**
 * Attention items in Now's queue (U31, DECISIONS #54; ops.md §action-queue `attention`): mission
 * "needs acknowledgment" items, for now pass-resolution conflicts. One row each, never grouped;
 * the pass's contact drawer holds the detail and the actions.
 */

/** U32: who closed or acknowledged it. */
const who = d.object({
  kind: d.knownText(["user", "provider", "system"] as const),
  id: d.nullable(d.token),
  name: d.nullable(d.string),
});

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
  "listener_unavailable",
  "connect_failed",
  "ingress_pipeline_failed",
  "uplink_session_failed",
  "no_runtime_spec",
  "unknown",
] as const;
/** U37 contact_settlement: why the telemetry isn't stored (null: a slow drain past the deadline). */
export const settlementFailures = ["telemetry_storage_unavailable", "settle_failed"] as const;

/** The server's own key, known or not: attention routes, fold keys. */
export const serverKey = <T extends string>(value: T | Unrecognized): string =>
  isKnown(value) ? value : value.unrecognized;

/** Provider-change fields (ProviderReservationChanges' document keys); values are JSON text. */
export const changeFields = [
  "starts_at",
  "ends_at",
  "ground_station_ref",
  "antenna_or_service_pool_ref",
  "service_profile_ref",
  "delivery_profile_ref",
  "spacecraft_ref",
  "pass_phase",
  "status",
] as const;
const providerChangeFields = {
  id: d.token,
  classification: d.knownText([
    "approval_required",
    "acknowledgment_required",
    "configuration_failure",
    "policy_accept",
  ] as const),
  // Domain's lifecycle plus expired (api, L14 flown passes); an unknown one reads as evidence only.
  state: d.knownText([
    "pending_approval",
    "acknowledgment_required",
    "configuration_failure",
    "expired",
    "approved",
    "rejected",
    "acknowledged",
    "superseded",
    "policy_accepted",
    "observed",
    "apply_failed",
  ] as const),
  deadline_at: d.nullable(d.timestamp),
  provider_revision: d.nullable(d.integer),
  // The decision's guard, sent back verbatim with approve / reject / acknowledge.
  proposal_hash: d.string,
  already_effective: d.boolean,
  fields: d.array(
    d.object({
      field: d.knownText(changeFields),
      // free-text: a server label for the field when it has one (null today)
      label: d.nullable(d.string),
      before_json: d.nullable(d.string),
      after_json: d.nullable(d.string),
    }),
    50,
  ),
} as const;
export const providerChangeReader = d.object(providerChangeFields);

export type ProviderChange = Decoded<typeof providerChangeReader>;
/** GET /passes/:id provider_changes[] (api, L14 flown passes): the change plus when it was raised. */
export const passChangeReader = d.object({
  ...providerChangeFields,
  raised_at: d.timestamp,
  resolution: d.nullable(
    d.object({
      // free-text: the decision's own key; the state carries the outcome (ux U44)
      action: d.string,
      by: d.nullable(d.object({ id: d.nullable(d.token), name: d.nullable(d.string) })),
      at: d.timestamp,
      // free-text: the decider's reason
      reason: d.nullable(d.string),
    }),
  ),
});
export type PassChange = Decoded<typeof passChangeReader>;

const stationReader = d.object({
  ref: d.nullable(d.string),
  id: d.nullable(d.token),
  // free-text: a station's call sign, not a vocabulary
  code: d.nullable(d.string),
  name: d.nullable(d.string),
});

/** U45: the pass holding the station connection, served like the item's own pass fields. */
const holderReader = d.object({
  realized_contact_id: d.nullable(d.token),
  contact_id: d.nullable(d.token),
  reservation_id: d.optional(d.nullable(d.token)),
  spacecraft: d.optional(
    d.nullable(d.object({ id: spacecraftIdReader, name: d.nullable(d.string) })),
  ),
  station: d.optional(d.nullable(stationReader)),
  starts_at: d.optional(d.nullable(d.timestamp)),
  ends_at: d.nullable(d.timestamp),
});

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
  "started",
  "superseded",
] as const;
export type ResolutionAction = (typeof resolutionActions)[number];
/** The action as text: a known key, or the server's (or operator's) own words. */
export const actionText = (action: ResolutionAction | Unrecognized): string =>
  isKnown(action) ? action : action.unrecognized;

export const attentionReader = d.object({
  id: d.token,
  source: d.knownText(attentionSources),
  /** null on uplink_blocked (U33). */
  conflict: d.nullable(d.knownText(attentionConflicts)),
  // contacts.md: resolve answers the item in state resolved (api drift sweep 11-13).
  state: d.oneOf(["open", "acknowledged", "resolved"] as const),
  acknowledged_by: d.nullable(who),
  // d2632794: cancel_failed/late_confirmation may have no contact; reservation_id is the pass
  // row id, which the Contacts drawer selects on.
  contact_id: d.nullable(d.token),
  // Null when a contact has no provider booking (domain, #71).
  reservation_id: d.optional(d.nullable(d.token)),
  // Null on mission-wide sources (mission_runtime: no station, provider or pass).
  station: d.nullable(stationReader),
  provider: d.nullable(d.object({ id: d.nullable(d.token), name: d.nullable(d.string) })),
  starts_at: d.nullable(d.timestamp),
  raised_at: d.timestamp,
  provider_message: d.nullable(d.string),
  /** U33 uplink_blocked only; null (or absent) on pass_resolution. */
  uplink: d.optional(d.nullable(attentionUplinkReader)),
  /** pass_release only (api-ops, ahead of domain): what happened to the Release's cancel. */
  release: d.optional(
    d.nullable(
      d.object({
        // contacts.md §release: refused | not_sent | unknown (no answer yet).
        outcome: d.knownText(["refused", "not_sent", "unknown"] as const),
        // free-text: the provider's own reason sentence
        reason: d.nullable(d.string),
      }),
    ),
  ),
  /** contact_settlement (#71): telemetry still on disk, not yet in the TSDB; null elsewhere. */
  backlog: d.optional(
    d.nullable(
      d.object({
        entries: d.integer,
        bytes: d.integer,
        journals: d.integer,
        /** Journal off (domain 96307ac5): batches that were in memory when the runtime stopped. */
        queued: d.optional(d.nullable(d.integer)),
        /** true: those batches are gone, not on disk (U37 journal off). */
        lost: d.optional(d.nullable(d.boolean)),
      }),
    ),
  ),
  /** mission_runtime (U38) or contact_start (U45): the reason key. */
  reason: d.optional(d.nullable(d.knownText([...runtimeReasons, ...startReasons] as const))),
  desired_generation: d.optional(d.nullable(d.integer)),
  applied_generation: d.optional(d.nullable(d.integer)),
  since: d.optional(d.nullable(d.timestamp)),
  change_set_id: d.optional(d.nullable(d.token)),
  activated_at: d.optional(d.nullable(d.timestamp)),
  /** enabled | disabled: whether the mission keeps a disk copy of incoming telemetry. */
  journal: d.optional(d.nullable(d.knownText(["enabled", "disabled"] as const))),
  // Null when the contact has no provider booking (domain, U45).
  ends_at: d.optional(d.nullable(d.timestamp)),
  deadline_at: d.optional(d.nullable(d.timestamp)),
  /** telemetry_storage_unavailable | settle_failed | null (a slow drain past the deadline). */
  failure_kind: d.optional(d.nullable(d.knownText(settlementFailures))),
  failure_message: d.optional(d.nullable(d.string)),
  /** automatic | manual (domain #71 replay: manual after 6 failed replays, operator retries). */
  retry: d.optional(d.nullable(d.knownText(["automatic", "manual"] as const))),
  attempts: d.optional(d.nullable(d.integer)),
  /** Set while automatic and backing off (5 min doubling to 2 h); null when manual. */
  next_attempt_at: d.optional(d.nullable(d.timestamp)),
  last_attempt_at: d.optional(d.nullable(d.timestamp)),
  /** activation_apply (domain 9b8456132): the request, in the words its review page uses. */
  activation_request_id: d.optional(d.nullable(d.token)),
  error_code: d.optional(
    d.nullable(
      d.knownText([
        "activation_execution_interrupted",
        "spacecraft_configuration_review_stale",
        "approved_activation_content_mismatch",
        // archive_quarantine (#88): why the archive refused the records.
        "identity_conflict",
        "data_rejected",
        "unknown",
      ] as const),
    ),
  ),
  // free-text: the server's sentence for the failure (never the raw reason)
  error: d.optional(d.nullable(d.string)),
  // free-text: the server's sentence for what it activates ("Decom composition for 3 spacecraft")
  summary: d.optional(d.nullable(d.string)),
  kind: d.optional(
    d.nullable(d.knownText(["telemetry_decom", "spacecraft_configuration"] as const)),
  ),
  app: d.optional(d.nullable(d.object({ key: d.token, name: d.nullable(d.string) }))),
  spacecraft_ids: d.optional(d.nullable(d.array(spacecraftIdReader, 10_000))),
  spacecraft_count: d.optional(d.nullable(d.integer)),
  /** false: retrying can't help (review stale, content mismatch); request activation again (U41). */
  retryable: d.optional(d.nullable(d.boolean)),
  /** U41 meta: who approved it and when (api be59d4f32; null when the record has no approver). */
  approved_by: d.optional(d.nullable(d.object({ name: d.nullable(d.string) }))),
  approved_at: d.optional(d.nullable(d.timestamp)),
  /** true: the runtime isn't running the active configuration either (mission_runtime is left out). */
  runtime_not_applied: d.optional(d.nullable(d.boolean)),
  provider_change: d.optional(d.nullable(providerChangeReader)),
  /** contact_start (U45): the realized contact that didn't start, and the profile it runs on. */
  realized_contact_id: d.optional(d.nullable(d.token)),
  provider_profile_id: d.optional(d.nullable(d.token)),
  // free-text: the provider profile's name ("Santiago (Demo) S-band downlink")
  provider_profile_name: d.optional(d.nullable(d.string)),
  /** listener_in_use only: the pass still holding the station connection. */
  holder: d.optional(d.nullable(holderReader)),
  /** listen_endpoint_claimed only (U81 §3): the port, and OUR transport that uses it. */
  listen_port: d.optional(d.nullable(d.integer)),
  transport_id: d.optional(d.nullable(d.token)),
  // free-text: that transport's display name ("INU S-band")
  transport_name: d.optional(d.nullable(d.string)),
  /** ingress_backpressure (U47): the downlink transport, its buffer, and what it dropped. */
  // free-text: the contact's pass name when it has one (api-ops)
  contact_label: d.optional(d.nullable(d.string)),
  transport: d.optional(
    d.nullable(
      d.object({
        provider_binding_id: d.token,
        kind: d.knownText(["tcp"] as const),
      }),
    ),
  ),
  journal_usage: d.optional(
    d.nullable(
      d.object({
        used_bytes: d.integer,
        capacity_bytes: d.integer,
        ratio: d.number,
        threshold: d.number,
        backlog_bytes: d.integer,
        observed_at: d.timestamp,
        /** The ratio grew between the last two samples. */
        rising: d.boolean,
      }),
    ),
  ),
  drops: d.optional(
    d.nullable(
      d.object({
        count: d.integer,
        bytes: d.integer,
        first_at: d.timestamp,
        last_at: d.timestamp,
        buffer: d.knownText(["journal", "executor"] as const),
      }),
    ),
  ),
  /** Raw, for Technical details only. */
  diagnostics: d.optional(
    d.nullable(
      d.object({
        // free-text: a transport stream id
        stream_id: d.nullable(d.string),
        // free-text: the raw error, never in visible text
        last_error: d.nullable(d.string),
      }),
    ),
  ),
  /** archive_quarantine (U49, #88): what the archive couldn't take, and what was stored anyway. */
  counts: d.optional(d.nullable(d.object({ frames: d.integer, packets: d.integer }))),
  stored_without_archive: d.optional(
    d.nullable(d.object({ frames: d.integer, packets: d.integer })),
  ),
  /** The records' receipt span (the meta), and the last one seen (bumped while more arrive). */
  first_received_at: d.optional(d.nullable(d.timestamp)),
  last_received_at: d.optional(d.nullable(d.timestamp)),
  last_seen_at: d.optional(d.nullable(d.timestamp)),
  actions: d.optional(d.nullable(d.array(d.knownText(["retry", "discard", "close"] as const), 10))),
  /** `indexed` asked of domain 11-14: how many that retry archived. */
  last_retry: d.optional(
    d.nullable(d.object({ by: who, at: d.timestamp, indexed: d.optional(d.nullable(d.integer)) })),
  ),
  /** listener_refusal (U50, #87): counted live in memory, so a restart starts them again. */
  refused_count: d.optional(d.nullable(d.integer)),
  last_refused_at: d.optional(d.nullable(d.timestamp)),
  last_refusal: d.optional(
    d.nullable(
      d.object({
        // free-text: the connection's address, Technical details only (U50)
        peer: d.nullable(d.string),
        reason: d.knownText(listenerRefusals),
        scid: d.nullable(d.integer),
      }),
    ),
  ),
  /** Whether this contact has its own connection now. */
  connected: d.optional(d.nullable(d.boolean)),
  /** U50: its own connection has sent nothing since then (a half-open one may block a reconnect). */
  own_quiet_since: d.optional(d.nullable(d.timestamp)),
  /** The other open contacts on the same listener. */
  shared_with: d.optional(d.nullable(d.array(d.token, 1_000))),
  // free-text: the provider's ground station reference
  ground_station_ref: d.optional(d.nullable(d.string)),
  /** job_outcome_unknown (U54, api-ops): the cut-off run, and its type's words from the server. */
  job: d.optional(
    d.nullable(
      d.object({
        id: d.token,
        type_key: d.token,
        run_id: d.nullable(d.token),
        attempt: d.nullable(d.integer),
        // free-text: a node name
        node: d.nullable(d.string),
        // free-text: the worker module, Technical details only
        worker: d.optional(d.nullable(d.string)),
      }),
    ),
  ),
  words: d.optional(
    d.nullable(
      d.object({
        // free-text: the job's noun ("Booking at Northlight"), from api-ops' table
        noun: d.string,
        // free-text: where to check ("with Northlight", "in Setup › Catalog")
        check_place: d.string,
        // free-text: what a second run could do ("book the pass twice")
        consequence: d.string,
      }),
    ),
  ),
  started_at: d.optional(d.nullable(d.timestamp)),
  /** When the restart found it; Cadence doesn't record when it stopped (U54). */
  found_at: d.optional(d.nullable(d.timestamp)),
  /** plan_coverage (U61): the day, its first window, and its newest plan. */
  ...planCoverageFields,
  /** expired_group (U75): the request, its targets and how much went out. */
  ...expiredGroupFields,
  /** ingress_backpressure / journal_disk (U66): the shared buffer disk. */
  ...journalDiskFields,
  resolution: d.nullable(
    d.object({
      /** How it closed: a known key (archive 'discarded', a job 'closed'…), else the raw word. */
      action: d.knownText(resolutionActions),
      actor: who,
      at: d.timestamp,
      note: d.nullable(d.string),
      provider_reference: d.nullable(d.string),
    }),
  ),
});
export type Attention = Decoded<typeof attentionReader>;

/** Attention items resolved in the last 60 s; `id` is the row's item id (fafe581a). */
export const resolvedReader = d.object({
  id: d.token,
  resolved_by: who,
  // free-text: the decision's reason (provider_change, asked of api for U44)
  note: d.optional(d.nullable(d.string)),
  /** A key the console words (U32…U61), else the server's own phrase ("uplink recovered"). */
  action: d.optional(d.nullable(d.knownText(resolutionActions))),
  resolved_at: d.timestamp,
  /** api (U50): false for a hand-started contact; absent from older reads and other sources. */
  booked: d.optional(d.nullable(d.boolean)),
  /** U66 journal_disk only: when telemetry was refused before it cleared. */
  refused: d.optional(d.nullable(d.object({ from: d.timestamp, to: d.timestamp }))),
  /** U61 plan_coverage (domain 702223355): the plan state it resolved from, R…, booking reached. */
  from_state: d.optional(d.nullable(d.knownText(coveragePlanStates))),
  plan_revision: d.optional(d.nullable(d.integer)),
  booking: d.optional(d.nullable(d.object({ reserved: d.integer, total: d.integer }))),
});

const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;
/** §4 short: `18:49Z`, with the date when it isn't today. */
export const short = (iso: string, now: Date) =>
  `${iso.slice(0, 10) === now.toISOString().slice(0, 10) ? "" : `${iso.slice(5, 10)} `}${hhmm(iso)}`;

/**
 * U37 evidence by failure_kind: what's on disk and why it isn't stored. Never "TSDB", "journal" or
 * "settlement"; the storage outage's own message stays out of the line (Technical details).
 */
export function settlementEvidence(f: SettlementFacts, now: Date = new Date()): string {
  if (f.lost) return lostEvidence(f.queued);
  const one = f.backlog.entries === 1;
  const disk = `${f.backlog.entries.toLocaleString("en-US")} ${one ? "entry" : "entries"} (${formatBytes(f.backlog.bytes)}) ${one ? "is" : "are"} on disk`;
  const them = one ? "it" : "them";
  if (f.retry === "manual") {
    // ux 294e67c6: replay stopped after MAX_TRIES; the reason is the last try's.
    const why =
      f.failureKind === "telemetry_storage_unavailable"
        ? `telemetry storage was unavailable at the last try${f.lastAttemptAt ? `, ${short(f.lastAttemptAt, now)}` : ""}`
        : f.failureMessage
          ? noStop(f.failureMessage)
          : null;
    return `${disk}. Cadence stopped after ${f.attempts ?? MAX_TRIES} failed tries${why ? `: ${why}` : ""}.`;
  }
  const failed = f.attempts ? `${f.attempts} of ${MAX_TRIES} tries failed.` : null;
  const next = f.nextAttemptAt
    ? Date.parse(f.nextAttemptAt) <= now.getTime()
      ? "Trying now."
      : `Next try at ${short(f.nextAttemptAt, now)}.`
    : null;
  const tail = [failed, next].filter(Boolean).join(" ");
  const end = tail ? ` ${tail}` : "";
  if (f.failureKind === null)
    return `${disk}, past the ${f.deadline ? `${f.deadline} ` : ""}deadline for storing ${them}.${end}`;
  if (f.failureKind === "telemetry_storage_unavailable")
    return next
      ? `${disk}. Telemetry storage is unavailable.${end}`
      : `${disk}. Telemetry storage is unavailable; Cadence stores ${them} when it's back.${end}`;
  return `${disk}. Cadence couldn't store ${them}${f.failureMessage ? `: ${noStop(f.failureMessage)}` : ""}.${end}`;
}

/**
 * U37 journal off (ux 4f8b796c): never "on disk", never Retry. `queued` null: the count is unknown.
 */
export function lostEvidence(queued: number | null): string {
  if (queued === null)
    return "Telemetry in memory when the runtime stopped wasn't stored. This mission doesn't keep a disk copy, so it can't be recovered.";
  const one = queued === 1;
  return `${queued.toLocaleString("en-US")} telemetry ${one ? "batch was" : "batches were"} in memory when the runtime stopped and ${one ? "wasn't" : "weren't"} stored. This mission doesn't keep a disk copy, so ${one ? "it" : "they"} can't be recovered.`;
}

/** Replay stops after this many failed tries and hands to an operator (director, #71). */
export const MAX_TRIES = 6;

export type SettlementFacts = Readonly<{
  backlog: Readonly<{ entries: number; bytes: number }>;
  /** Journal off: the batches are gone (U37); `queued` counts them. */
  lost: boolean;
  queued: number | null;
  failureKind: NonNullable<Attention["failure_kind"]> | null;
  failureMessage: string | null;
  /** `00:57Z`; null on a folded line (ux 3f61ef71). */
  deadline: string | null;
  retry: NonNullable<Attention["retry"]> | null;
  attempts: number | null;
  nextAttemptAt: string | null;
  lastAttemptAt: string | null;
}>;

/** One item's facts for the evidence line. */
export const settlementFacts = (a: Attention & { backlog: NonNullable<Attention["backlog"]> }) =>
  ({
    backlog: a.backlog,
    lost: a.backlog.lost === true,
    queued: a.backlog.queued ?? null,
    failureKind: a.failure_kind ?? null,
    failureMessage: a.failure_message ?? null,
    deadline: a.deadline_at ? hhmm(a.deadline_at) : null,
    retry: a.retry ?? null,
    attempts: a.attempts ?? null,
    nextAttemptAt: a.next_attempt_at ?? null,
    lastAttemptAt: a.last_attempt_at ?? null,
  }) satisfies SettlementFacts;

const noStop = (s: string) => s.trim().replace(/[.!?]+$/, "");

/** Title tail and evidence sentence (U31 copy). Unknown conflicts still say who and where. */
export function attentionWords(
  a: Attention,
  now: Date = new Date(),
): Readonly<{ what: string; evidence: string }> {
  const provider = a.provider?.name ?? "The provider";
  if (a.release) {
    // A Release whose cancel the provider refused or didn't answer: the booking may still stand.
    const what =
      a.release.outcome === "refused"
        ? `${provider} refused the cancel`
        : a.release.outcome === "not_sent"
          ? "the cancel wasn't sent"
          : `no answer from ${provider} to the cancel`;
    const why = a.release.reason ?? a.provider_message;
    return {
      what: `Release not confirmed: ${what}.`,
      evidence: `${why ? `${noStop(why)}. ` : ""}The pass may still be booked and billed.`,
    };
  }
  if (a.backlog) {
    // U37 (#71 contact_settlement): system-closed, no person action, no Acknowledge.
    const station = a.station?.code ?? a.station?.name;
    return {
      what: `Telemetry from the ${station ? `${station} ` : ""}${a.starts_at ? `${short(a.starts_at, now)} ` : ""}pass ${a.backlog.lost ? "was lost" : "isn't stored yet"}.`,
      evidence: settlementEvidence(settlementFacts({ ...a, backlog: a.backlog }), now),
    };
  }
  if (a.uplink) {
    // U33: "EARENDIL-001 · Can't command on the SVB-1 pass." / "<reason>. 2 command groups are queued for it."
    const n = a.uplink.command_group_ids.length;
    const station = a.station?.code ?? a.station?.name ?? "this";
    return {
      what: `Can't command on the ${station} pass.`,
      evidence: `${reasonSentence(a.uplink.reason, { provider: a.provider?.name ?? null })}.${n ? ` ${plural(n, "command group")} ${n === 1 ? "is" : "are"} queued for it.` : ""}`,
    };
  }
  const r = a.resolution;
  const by = r ? ` by ${r.actor.name ?? "an operator"} ${hhmm(r.at)}` : "";
  switch (a.conflict) {
    case "contradicts_attestation":
      return {
        what: `${provider} says a pass marked booked isn't.`,
        evidence: `Marked booked${by}${r?.provider_reference ? ` with ref ${r.provider_reference}` : ""}. Don't count on this contact.`,
      };
    case "late_confirmation":
      return {
        what: `${provider} confirmed a pass marked not booked.`,
        evidence: `Marked not booked${by}. It may be booked and billed.`,
      };
    case "cancel_failed":
      return {
        what: `${provider} didn't accept the cancel.`,
        evidence: `${a.provider_message ? `${noStop(a.provider_message)}. ` : ""}The pass may still be booked and billed.`,
      };
    // Worded by their own rows (U37, U38, U41), never through here.
    case "unsettled":
    case "generation_not_applied":
    case "apply_failed":
    case "apply_stalled":
    case "approval_required":
    case "acknowledgment_required":
    case "configuration_failure":
    case "not_started":
    case "missed":
    case "journal_near_full":
    case "frames_dropped":
    case "journal_disk":
    case "quarantined":
    case "listener_refusal":
    case "outcome_unknown":
    case null:
    default:
      // A source this console doesn't know yet says only that the contact needs a look.
      return a.source === "pass_resolution"
        ? {
            what: `${provider} disagrees with this pass's booking.`,
            evidence: "Review the contact before counting on it.",
          }
        : { what: "This contact needs attention.", evidence: "Review the contact." };
  }
}

/** Meta before the live AOS countdown: station code, and who acknowledged (U21). */
export function attentionMeta(a: Attention, now: Date = new Date()): string | null {
  // U37: `SVA · Northlight · 18:49Z–18:57Z`, dropping any null part (U20).
  if (a.backlog) {
    const window = a.starts_at
      ? `${short(a.starts_at, now)}${a.ends_at ? `–${short(a.ends_at, now)}` : ""}`
      : null;
    return [a.station?.code ?? a.station?.name, a.provider?.name, window]
      .filter((p): p is string => Boolean(p))
      .join(" · ")
      .toUpperCase();
  }
  const parts = [
    a.station?.code ?? a.station?.name,
    a.state === "acknowledged" ? `Ack ${a.acknowledged_by?.name ?? ""}`.trim() : null,
  ].filter((p): p is string => Boolean(p));
  return parts.length ? parts.join(" · ").toUpperCase() : null;
}

export type Resolved = Decoded<typeof resolvedReader>;
/** What the words read of a resolved entry; `booked` and `refused` are only on newer reads. */
export type ResolvedEntry = Omit<
  Resolved,
  "booked" | "refused" | "from_state" | "plan_revision" | "booking"
> &
  Readonly<{
    booked?: boolean | null | undefined;
    refused?: Resolved["refused"];
    from_state?: Resolved["from_state"];
    plan_revision?: Resolved["plan_revision"];
    booking?: Resolved["booking"];
  }>;

/** Server actions that read better in words: U37's system 'replayed' = the telemetry got stored. */
const ACTION_WORDS: Readonly<Partial<Record<ResolutionAction, string>>> = {
  replayed: "telemetry stored",
  // U38: the runtime caught up with the active configuration.
  applied: "configuration applied",
};

/**
 * What closed it (ops.md §resolved, U32): a person reads "Resolved by Mira K."; a provider
 * "Resolved: Northlight confirmed"; the system its action alone ("Resolved: cancel confirmed").
 * Never "by Cadence".
 */
const CHANGE_DECIDED: Readonly<Partial<Record<ResolutionAction, string>>> = {
  approved: "Approved",
  rejected: "Rejected",
  acknowledged: "Acknowledged",
};

export function resolvedWords(r: ResolvedEntry, now: Date = new Date()): string {
  // §4 short form: a row resolved before midnight keeps its date after it (ux).
  const at = short(r.resolved_at, now);
  // U41: a stuck activation closes by applying, or by a newer activation replacing it.
  // U44: a provider change says who decided, when and why; a newer change replaces it.
  if (r.id.startsWith("attention:provider_change:")) {
    const decided = r.action && isKnown(r.action) ? CHANGE_DECIDED[r.action] : undefined;
    if (r.action === "superseded") return "Replaced by a newer change.";
    if (decided) {
      const who = r.resolved_by.name ?? "an operator";
      const why = r.note ? `: ${noStop(r.note)}` : "";
      return `${decided} by ${who} at ${at}${why}.`;
    }
  }
  if (r.id.startsWith("attention:contact_start:")) {
    // U45: it started, or an operator marked the missed pass as seen.
    if (r.action === "started") return `Started at ${at}.`;
    if (r.action === "acknowledged")
      return `Marked as seen by ${r.resolved_by.name ?? "an operator"} at ${at}.`;
  }
  // compared-as-text: an item id (an open set); this is the one journal_disk item's fixed id (U66)
  if (r.id === "attention:ingress_backpressure:journal_disk")
    return diskResolvedWords(at, r.refused);
  if (r.id.startsWith("attention:ingress_backpressure:")) {
    // U47: the buffer caught up, or an operator acknowledged the lost frames.
    if (r.action === "drained") return `Caught up at ${at}.`;
    if (r.action === "acknowledged")
      return `Acknowledged by ${r.resolved_by.name ?? "an operator"} at ${at}.`;
  }
  if (r.id.startsWith("attention:archive_quarantine:")) {
    // U49: archived on retry, or discarded by an operator with a reason.
    if (r.action === "retried") return `Archived on retry at ${at}.`;
    if (r.action === "discarded")
      return `Discarded by ${r.resolved_by.name ?? "an operator"} at ${at}${r.note ? `: ${noStop(r.note)}` : ""}.`;
  }
  if (r.id.startsWith("attention:listener_refusal:")) {
    // U50: the pass got its own connection, or its window closed.
    if (r.action === "accepted") return `Connected at ${at}.`;
    // ux: without the booked flag, "Ended at" is true of a pass and a hand-started contact.
    if (r.action === "ended")
      return r.booked === true
        ? `The pass ended at LOS ${at}.`
        : r.booked === false
          ? `The contact ended at ${at}.`
          : `Ended at ${at}.`;
  }
  if (r.id.startsWith("attention:plan_coverage:")) {
    // U61: approved, nothing left to plan, or the day ended unplanned (crit, kept in the list).
    const day = r.id.slice("attention:plan_coverage:".length).slice(5, 10);
    if (r.action === "approved")
      return `Approved by ${r.resolved_by.name ?? "an org admin"} at ${at}.`;
    if (r.action === "nothing_left") return `Nothing is left to plan for ${day}.`;
    // ux 11fe550bf: booking began (from approved) or resumed (from interrupted).
    if (r.action === "booking_started")
      return r.from_state === "interrupted"
        ? `Booking continued at ${at}.`
        : `Booking started at ${at}.`;
    if (r.action === "day_ended") {
      const rv = r.plan_revision != null ? `R${r.plan_revision}` : "its plan";
      if (r.from_state === "approved" && !r.booking)
        return `${day} ended with ${rv} approved but not booked.`;
      if (r.from_state === "interrupted" && r.booking)
        return `${day} ended with ${r.booking.reserved} of ${r.booking.total} passes booked.`;
      return `${day} ended with no approved plan.`;
    }
  }
  if (r.id.startsWith("attention:job_outcome_unknown:")) {
    // U54: retried (queued again) or closed with what the operator found.
    const who = r.resolved_by.name ?? "an operator";
    if (r.action === "retried") return `Retried by ${who} at ${at}; it's queued.`;
    if (r.action === "closed")
      return r.note
        ? `Closed without retry by ${who} at ${at}: “${r.note.trim()}”`
        : `Closed without retry by ${who} at ${at}.`;
  }
  if (r.id.startsWith("attention:activation_apply:")) {
    if (r.action === "superseded") return "Replaced by a newer request.";
    if (r.action === "applied") return `Applied at ${at}.`;
  }
  const said = !r.action
    ? null
    : isKnown(r.action)
      ? (ACTION_WORDS[r.action] ?? r.action.replaceAll("_", " "))
      : r.action.unrecognized.replaceAll("_", " ");
  const action = said ? noStop(said) : null;
  const name = r.resolved_by.name ? noStop(r.resolved_by.name) : null;
  if (r.resolved_by.kind === "user") return `Resolved by ${name ?? "an operator"}.`;
  if (r.resolved_by.kind === "provider")
    return `Resolved: ${[name ?? "the provider", action].filter(Boolean).join(" ")}.`;
  return action ? `Resolved: ${action}.` : "Resolved.";
}

/** How long a resolved row stays, faded, before it leaves (U31). */
export const RESOLVED_FADE_MS = 5_000;

export type Fading = Readonly<{ item: QueueItem; index: number; until: number }>;

/**
 * Rows to fade after a read: a row seen last time, now gone, and listed in `resolved` reads
 * "Resolved by Mira K." for 5 s at its old place. It never takes the primary action.
 */
export function newlyResolved(
  previous: readonly QueueItem[],
  current: readonly QueueItem[],
  resolved: readonly ResolvedEntry[],
  already: readonly Fading[],
  now: number,
): Fading[] {
  const live = new Set(current.flatMap((r) => [r.key, ...(r.memberKeys ?? [])]));
  const seen = new Set(already.map((f) => f.item.key));
  return resolved.flatMap((r) => {
    // A folded row (U37) fades only once none of its members is still on screen.
    const index = previous.findIndex((p) => p.key === r.id || p.memberKeys?.includes(r.id));
    const prev = previous[index];
    if (!prev) return [];
    const key = `${prev.key}|resolved`;
    const members = prev.memberKeys ?? [prev.key];
    if (live.has(prev.key) || members.some((k) => live.has(k)) || seen.has(key)) return [];
    seen.add(key);
    const { list: _list, memberKeys: _members, ...rest } = prev;
    const item: QueueItem = {
      ...rest,
      key,
      state: "off",
      sentence: resolvedWords(r, new Date(now)),
      meta: null,
      acknowledged: true,
    };
    return [{ item, index, until: now + RESOLVED_FADE_MS }];
  });
}

/** Current rows with the fading ones put back where they were. */
export function withFading(rows: readonly QueueItem[], fading: readonly Fading[]): QueueItem[] {
  const out = [...rows];
  for (const f of [...fading].sort((a, b) => a.index - b.index))
    out.splice(Math.min(f.index, out.length), 0, f.item);
  return out;
}
