import { decoders as d, spacecraftRef } from "@/api/index.ts";

/**
 * replay_conflict (ux U84 "Stuck processing", api 11-17, after #99): a part of the mission's
 * processing hit a fault in Cadence and keeps retrying the same input. One item per stuck unit,
 * acknowledge-only, closed by the system when the fix lands. `state` stays open | acknowledged;
 * the mark is critical while `dropping`, else caution. Its own fields, spread into the attention
 * reader, all optional (readers first: api ships the source only after this lands).
 */

/** U84's three variants: a pass's telemetry storage, incoming data, timed actions. */
export const replayConflictPaths = ["storage", "processing", "timer"] as const;

export const replayConflictFields = {
  path: d.optional(d.nullable(d.knownText(replayConflictPaths))),
  effect_kind: d.optional(
    d.nullable(d.knownText(["alarm_effect", "managed_action_request"] as const)),
  ),
  effect_id: d.optional(d.nullable(d.token)),
  /** How many stuck effects share this unit. */
  effect_count: d.optional(d.nullable(d.integer)),
  /** Present on timer only; storage and processing stall on a stream, not a partition. */
  partition_id: d.optional(d.nullable(d.token)),
  /** timer only: the partition failed to start and stays down (U84 'STOPPED', no retry counts). */
  partition_stopped: d.optional(d.nullable(d.boolean)),
  path_id: d.optional(d.nullable(d.token)),
  // free-text: the stream's key, Technical details only (null on timer)
  stream_key: d.optional(d.nullable(d.string)),
  /** The pass, for storage's title (U47's `SVA 18:49Z pass`); null on timer or when unknown. */
  contact: d.optional(
    d.nullable(
      d.object({
        id: d.token,
        // free-text: the station's short code ("SVA")
        station_code: d.nullable(d.string),
        starts_at: d.nullable(d.timestamp),
      }),
    ),
  ),
  /**
   * The craft known to be affected (U25: a null name is counted, never shown by id). For
   * processing and timer the list can be short, so the words say "at least" / "may affect others".
   */
  affected_spacecraft: d.optional(d.nullable(d.array(spacecraftRef, 10_000))),
  /** The MM_REPLAY_ID_CONFLICT log line's times, so support can find it; `occurrences` = retries. */
  first_seen_at: d.optional(d.nullable(d.timestamp)),
  occurrences: d.optional(d.nullable(d.integer)),
  /** Cadence's buffer for this stream (U47 "buffer"); null on timer. */
  buffer: d.optional(d.nullable(d.object({ used_bytes: d.integer, max_bytes: d.integer }))),
  /** The buffer is full and new telemetry is being lost (the critical state). */
  dropping: d.optional(d.nullable(d.boolean)),
  dropping_since: d.optional(d.nullable(d.timestamp)),
  acknowledged_at: d.optional(d.nullable(d.timestamp)),
  // free-text: the operator's note, who they told (500 characters at most)
  acknowledged_note: d.optional(d.nullable(d.string)),
  /** Dropping started after the ack: open again, the ack fields kept, acknowledgeable again. */
  reraised: d.optional(d.nullable(d.boolean)),
  /**
   * On contact_settlement, ingress_backpressure and mission_runtime: the stuck-processing item
   * that is this item's own cause (U84 cause tag; absent or null otherwise).
   */
  stuck_processing_id: d.optional(d.nullable(d.token)),
} as const;
