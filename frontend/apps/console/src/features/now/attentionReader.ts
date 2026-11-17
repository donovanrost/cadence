import {
  actorKinds,
  decoders as d,
  orNull,
  spacecraftRef,
  stationRef,
  spacecraftId as spacecraftIdReader,
  type Decoded,
} from "@/api/index.ts";
import { attentionUplinkReader } from "@/features/contacts/readiness.ts";
import {
  attentionConflicts,
  attentionSources,
  listenerRefusals,
  resolutionActions,
  runtimeReasons,
  settlementFailures,
  startReasons,
} from "./attentionVocab.ts";
import { coveragePlanStates, planCoverageFields } from "./coverageFields.ts";
import { expiredGroupFields } from "./expiredGroup.ts";
import { journalDiskFields } from "./journalDisk.ts";
import { providerChangeReader } from "./providerChangeReader.ts";
import { replayConflictFields, replayConflictPaths } from "./replayConflictFields.ts";
import { scidMismatchFields } from "./scidMismatch.ts";

/**
 * Attention items in Now's queue (U31, DECISIONS #54; ops.md §action-queue `attention`): mission
 * "needs acknowledgment" items, for now pass-resolution conflicts. One row each, never grouped;
 * the pass's contact drawer holds the detail and the actions.
 */

/**
 * U32: who closed or acknowledged it. The shared actor's shape (§12 A5) with one more kind:
 * `provider`, the station provider resolving a booking (lead 11-16; not a Cadence service).
 */
const who = d.object({
  kind: orNull(d.knownText([...actorKinds, "provider"] as const)),
  id: orNull(d.string),
  name: orNull(d.string),
});

/** §12 A5: the shared station reference. */
const stationReader = stationRef;

/** U45: the pass holding the station connection, served like the item's own pass fields. */
const holderReader = d.object({
  realized_contact_id: d.nullable(d.token),
  contact_id: d.nullable(d.token),
  reservation_id: d.optional(d.nullable(d.token)),
  spacecraft: d.optional(d.nullable(spacecraftRef)),
  station: d.optional(d.nullable(stationReader)),
  starts_at: d.optional(d.nullable(d.timestamp)),
  ends_at: d.nullable(d.timestamp),
});

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
  /** contact_scid_mismatch (U81 §2): the pass's craft and its refused frames. */
  ...scidMismatchFields,
  /** replay_conflict (U84): the stuck unit, who it affects, its buffer and its ack note. */
  ...replayConflictFields,
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
  /** U45 contact_start: null when it failed before its run existed ('Set up at', ux). */
  realized_contact_id: d.optional(d.nullable(d.token)),
  /** U84 replay_conflict only: which part resumed, for the per-path resolved line. */
  path: d.optional(d.nullable(d.knownText(replayConflictPaths))),
});
