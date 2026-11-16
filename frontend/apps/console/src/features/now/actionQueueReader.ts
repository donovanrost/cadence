import type { MissionId } from "@/api/index.ts";
import {
  spacecraftId as spacecraftIdReader,
  scid as scidReader,
  actor,
  decoders as d,
  request,
  type ApiResult,
  type Decoded,
} from "@/api/index.ts";
import { engineeringValue, sourceStates } from "@/features/alarms/index.ts";
import { attentionReader, resolvedReader } from "./attention.ts";
import { changeSetReader } from "./changeSet.ts";
import { missedPassReader, nextContactReader, stationIssueReader } from "./sources.ts";

/** Contract: docs/apogee/api/ops.md, `GET /missions/:mission_id/action-queue` (M6). Server-ranked. */

const priority: d.Reader<1 | 2 | 3> = (value, path = "") => {
  if (value === 1 || value === 2 || value === 3) return value;
  throw new d.DecodeError(path, "1 | 2 | 3");
};

/**
 * An enum that may grow server-side (lead, #71): an unknown value reads as null so one new kind or
 * source drops its own row instead of failing the whole Now read.
 */
const tolerantOneOf =
  <const T extends readonly string[]>(values: T): d.Reader<T[number] | null> =>
  (value, path = "") => {
    const v = d.token(value, path);
    return values.find((candidate) => candidate === v) ?? null;
  };

/** Reads with `read`, or null (logged) when the value doesn't fit: for per-row objects. */
const lenient =
  <T>(read: d.Reader<T>): d.Reader<T | null> =>
  (value, path = "") => {
    try {
      return read(value, path);
    } catch (e) {
      if (!(e instanceof d.DecodeError)) throw e;
      console.warn("Dropped an unreadable queue row", e.message);
      return null;
    }
  };

const member = d.object({
  id: spacecraftIdReader,
  name: d.string,
  scid: scidReader,
  plane: d.nullable(d.integer),
  stale: d.boolean,
  last_received_at: d.nullable(d.timestamp),
  violating_points: d.nullable(d.integer),
  value: d.nullable(engineeringValue),
  first_crossed_at: d.nullable(d.timestamp),
  // Alarm items only (episodes, bc3d602c); null elsewhere.
  episode_id: d.nullable(d.token),
  status: d.nullable(d.oneOf(["new", "acknowledged"] as const)),
  assignee: d.nullable(d.object({ id: d.token, name: d.nullable(d.string) })),
  acknowledged_by: d.nullable(actor),
});
export type Member = Decoded<typeof member>;

const commandRequest = d.object({
  id: d.token,
  command_name: d.string,
  target: d.nullable(d.object({ id: d.token, name: d.string })),
  requested_by: d.nullable(d.string),
  // The command-status vocabulary (ops.md §command_requests; Commanding.CommandRequest).
  status: d.knownText([
    "draft",
    "validated",
    "approval_pending",
    "approved",
    "rejected",
    "queued",
    "released",
    "canceled",
    "failed",
    "indeterminate",
  ] as const),
});

/** requested_by: a display label, or an actor with a name; read either (ops.md §approval). */
const requester: d.Reader<string | null> = (value) => {
  if (typeof value === "string") return value;
  if (
    typeof value === "object" &&
    value !== null &&
    "name" in value &&
    typeof value.name === "string"
  )
    return value.name;
  return null;
};
const commandGroup = d.object({
  id: d.token,
  title: d.string,
  member_count: d.integer,
  target_count: d.integer,
  requested_by: d.optional(requester),
  requested_at: d.timestamp,
});

const itemReader = d.object({
  id: d.token,
  priority,
  kind: tolerantOneOf([
    "alarm",
    "command_failed",
    "approval",
    "stale",
    "setup",
    "limits_not_configured",
    "never_heard",
    "attention",
    "missed_pass",
    "station",
    "flight_event",
    "change_set_stale",
  ] as const),
  state: d.oneOf(["critical", "caution", "stale", "off"] as const),
  source: d.nullable(
    tolerantOneOf([
      "catalog_monitoring",
      "ground_limit",
      "pass_resolution",
      "uplink_blocked",
      "pass_release",
      "contact_settlement",
    ] as const),
  ),
  /** Alarm items: how many members are acknowledged. */
  acknowledged: d.nullable(d.integer),
  since: d.nullable(d.timestamp),
  count: d.integer,
  spacecraft: d.array(member, 1_000),
  point: d.nullable(
    d.object({
      id: d.token,
      name: d.string,
      subsystem: d.nullable(d.string),
      unit: d.nullable(d.string),
    }),
  ),
  // The worst episode's source_state (ops.md §alarm): a limit condition or monitoring level.
  condition: d.nullable(d.known(sourceStates)),
  plane: d.nullable(d.integer),
  command: d.nullable(d.object({ id: d.token, name: d.string })),
  outcome: d.nullable(d.oneOf(["failed", "indeterminate"] as const)),
  command_requests: d.array(commandRequest, 1_000),
  /** Approval items: command groups awaiting the viewer's GO (one each). */
  command_groups: d.optional(d.array(commandGroup, 1_000)),
  finding: d.nullable(d.object({ id: d.token, title: d.string, body: d.nullable(d.string) })),
  // U31 (fafe581a): null on other kinds; optional until api ships it.
  // An attention object this console can't read drops its own row, never the whole queue.
  attention: d.optional(d.nullable(lenient(attentionReader))),
  // Queue sources (ops.md b7008dd6): null on other kinds; optional until api-ops ships them.
  missed_passes: d.optional(d.nullable(d.array(missedPassReader, 100))),
  next_contact: d.optional(d.nullable(nextContactReader)),
  station_issue: d.optional(d.nullable(stationIssueReader)),
  /** flight_event (02cdde37): the state the spacecraft entered, and when (spacecraft time). */
  event: d.optional(d.nullable(d.object({ value_json: d.string, entered_at: d.timestamp }))),
  /** U39 change_set_stale (api 8d): null on other kinds; unreadable drops its own row. */
  change_set: d.optional(d.nullable(lenient(changeSetReader))),
});
export type ServerItem = Decoded<typeof itemReader>;

export const actionQueueReader = d.object({
  observed_at: d.timestamp,
  counts: d.object({ p1: d.integer, p2: d.integer, p3: d.integer, spacecraft_p1: d.integer }),
  items: d.array(itemReader, 1_000),
  resolved: d.optional(d.array(resolvedReader, 1_000)),
  /** U35: a missed pass is P1 with no booked contact within this horizon (6 h). */
  missed_pass_horizon_s: d.optional(d.integer),
});
export type ActionQueue = Decoded<typeof actionQueueReader>;

export function fetchActionQueue(
  missionId: MissionId,
  signal?: AbortSignal,
): Promise<ApiResult<ActionQueue>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/action-queue`,
    actionQueueReader,
    signal ? { signal } : {},
  );
}
