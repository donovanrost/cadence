import type { MissionId } from "@/api/index.ts";
import { expiredRow } from "./expiredGroup.ts";
import { scidMismatchRow } from "./scidMismatch.ts";
import type { RouteLocationRaw } from "vue-router";
import {
  spacecraftId as spacecraftIdReader,
  scid as scidReader,
  actor,
  decoders as d,
  request,
  type ApiResult,
  type Decoded,
} from "@/api/index.ts";
import { plural, type OpState } from "@/ui";
import {
  conditionWords,
  engineeringValue,
  formatValue,
  sourceStates,
  withUnit,
} from "@/features/alarms/index.ts";
import { attentionMeta, attentionReader, attentionWords, resolvedReader } from "./attention.ts";
import {
  missedPassReader,
  missedPassRows,
  nextContactReader,
  stationIssueReader,
  stationRow,
  type MissedItem,
} from "./sources.ts";
import { GROUP_AT, type QueueItem } from "./queue.ts";
import { FOLD_AT, foldedSettlementRow, foldKey, type Settlement } from "./settlement.ts";
import { runtimeRow } from "./runtime.ts";
import { activationRow } from "./activation.ts";
import { contactStartRow } from "./contactStart.ts";
import { archiveRow } from "./archive.ts";
import { coverageRow } from "./coverage.ts";
import { ingressRow } from "./ingress.ts";
import { diskRow } from "./journalDisk.ts";
import { jobRow } from "./jobs.ts";
import { listenerRow } from "./listener.ts";
import { changeEvidence, changeTitle, pastDeadline } from "./providerChange.ts";
import { changeSetReader, changeSetRow } from "./changeSet.ts";

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
type Member = Decoded<typeof member>;

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
type ServerItem = Decoded<typeof itemReader>;

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

const STATE: Readonly<Record<ServerItem["state"], OpState>> = {
  critical: "crit",
  caution: "caution",
  stale: "stale",
  off: "off",
};

const investigate = (sc: Member): RouteLocationRaw => ({
  name: "ops.spacecraft",
  params: { scId: sc.scid, tab: "investigate" },
});

function names(members: readonly { name: string }[], max = 4): string {
  const shown = members.slice(0, max).map((m) => m.name);
  const more = members.length - shown.length;
  return more > 0 ? `${shown.join(", ")} and ${more} more` : shown.join(", ");
}

const base = (item: ServerItem) => ({
  priority: item.priority,
  state: STATE[item.state],
  meta: null,
  spacecraftIds: item.spacecraft.map((m) => m.id),
});

/** "ACKNOWLEDGED · MIRA K." / "ASSIGNED TO …" / stale, for one spacecraft's alarm row. */
function memberMeta(sc: Member): string | null {
  const parts = [
    sc.status === "acknowledged" ? `Ack ${sc.acknowledged_by?.name ?? ""}`.trim() : null,
    sc.assignee ? `→ ${sc.assignee.name ?? "someone"}` : null,
    sc.stale ? "last known · telemetry stale" : null,
  ].filter((p): p is string => p !== null);
  return parts.length ? parts.join(" · ").toUpperCase() : null;
}

/** Alarm groups under GROUP_AT members become one row per spacecraft (contract: UI's call). */
function alarmRows(item: ServerItem): QueueItem[] {
  const point = item.point?.name ?? "Point";
  // flight_event: a catalog state rule matched ("MODE is SAFE"), not a limit crossing.
  const state = item.event ? flightValue(item.event.value_json) : null;
  const why = state
    ? `${point} is ${state}`
    : `${point} ${conditionWords(item.condition) ?? "out of limits"}`;
  if (item.spacecraft.length >= GROUP_AT)
    return [
      {
        ...base(item),
        key: item.id,
        title: `${plural(item.spacecraft.length, "spacecraft", "spacecraft")} · ${why}`,
        titleTo: null,
        sentence: names(item.spacecraft),
        meta: item.acknowledged
          ? `${item.acknowledged} OF ${item.spacecraft.length} ACKNOWLEDGED`
          : null,
        action: {
          label: "Alarms",
          to: { name: "ops.alarms", query: item.point ? { point: item.point.id } : {} },
        },
      },
    ];
  return item.spacecraft.map((sc) => ({
    ...base(item),
    key: `${item.id}|${sc.id}`,
    title: `${sc.name} · ${why}`,
    titleTo: investigate(sc),
    sentence: `${point} reads ${withUnit(formatValue(sc.value), item.point?.unit ?? null) ?? "—"}.`,
    meta: memberMeta(sc),
    acknowledged: sc.status === "acknowledged",
    action: { label: sc.status === "acknowledged" ? "Open" : "Engage", to: investigate(sc) },
    spacecraftIds: [sc.id],
  }));
}

function rowFor(
  item: ServerItem,
  missionName: string | null,
  now: Date,
  viewerId: string | null = null,
): QueueItem[] {
  switch (item.kind) {
    case null:
      // A kind this console doesn't know yet: no row rather than a wrong one.
      return [];
    case "alarm":
    case "flight_event":
      return alarmRows(item);
    case "command_failed":
      return [
        {
          ...base(item),
          key: item.id,
          title: `${item.command?.name ?? "Command"} ${item.outcome === "indeterminate" ? "outcome unknown" : "failed"} · ${plural(item.spacecraft.length, "spacecraft", "spacecraft")}`,
          titleTo: null,
          sentence: item.spacecraft.length ? names(item.spacecraft) : "No resolved targets.",
          action: { label: "Review", to: { name: "ops.commands" } },
        },
      ];
    case "approval": {
      // A single request opens its review; several go to the GO queue (backlog §2 Now).
      const groups = item.command_groups ?? [];
      const n = item.command_requests.length + groups.length;
      const group = groups[0];
      const first = item.command_requests[0];
      const one = n === 1 && group !== undefined;
      return [
        {
          ...base(item),
          key: item.id,
          title: `${plural(n, "command request")} ${n === 1 ? "awaits" : "await"} your GO`,
          titleTo: null,
          sentence: group
            ? `${group.title} · ${plural(group.target_count, "target")}${group.requested_by ? ` · by ${group.requested_by}` : ""}${n > 1 ? " and more" : ""}`
            : first
              ? `${first.command_name}${first.target ? ` · ${first.target.name}` : ""}${first.requested_by ? ` · by ${first.requested_by}` : ""}${n > 1 ? " and more" : ""}`
              : "Requested by another operator.",
          action: {
            label: "Review",
            to: one
              ? { name: "ops.commands.request", params: { requestId: group.id, view: "review" } }
              : { name: "ops.commands", query: { awaiting: "me" } },
          },
        },
      ];
    }
    case "stale":
      return [
        {
          ...base(item),
          key: item.id,
          title:
            item.plane === null
              ? `${plural(item.spacecraft.length, "spacecraft", "spacecraft")} stale`
              : `${item.spacecraft.length} in plane ${item.plane} stale`,
          titleTo: null,
          sentence: `No fresh telemetry: ${names(item.spacecraft)}.`,
          action: {
            label: "Fleet",
            to: {
              name: "ops.fleet",
              query:
                item.plane === null
                  ? { state: "stale" }
                  : { state: "stale", plane: String(item.plane) },
            },
          },
        },
      ];
    case "setup":
      return [
        {
          ...base(item),
          key: item.id,
          title: item.finding?.title ?? "Setup needs attention",
          titleTo: null,
          sentence: item.finding?.body ?? "See Setup readiness.",
          action: { label: "Setup", to: { name: "setup.readiness" } },
        },
      ];
    case "limits_not_configured":
      return [
        {
          ...base(item),
          key: item.id,
          title: "Ground limits not configured",
          titleTo: null,
          sentence:
            "No point is checked against limits on this mission, so nothing here can be critical or caution.",
          action: { label: "Set up", to: { name: "setup.apps" } },
        },
      ];
    case "change_set_stale":
      return item.change_set ? [changeSetRow(base(item), item.id, item.change_set, now)] : [];
    case "attention": {
      const a = item.attention;
      if (!a) return [];
      if (a.source === "mission_runtime")
        return [runtimeRow(base(item), item.id, a, missionName, now)];
      if (a.source === "activation_apply") return [activationRow(base(item), item.id, a, now)];
      if (a.source === "contact_start")
        return [contactStartRow(base(item), item.id, a, item.spacecraft[0]?.name ?? null, now)];
      if (a.source === "ingress_backpressure" && a.conflict === "journal_disk" && a.journal_disk)
        return [diskRow(base(item), item.id, a.journal_disk)];
      if (a.source === "ingress_backpressure")
        return [ingressRow(base(item), item.id, a, item.spacecraft[0]?.name ?? null, now)];
      if (a.source === "archive_quarantine")
        return [archiveRow(base(item), item.id, a, item.spacecraft[0]?.name ?? null, now)];
      if (a.source === "listener_refusal")
        return [listenerRow(base(item), item.id, a, item.spacecraft[0]?.name ?? null, now)];
      if (a.source === "plan_coverage") return [coverageRow(base(item), item.id, a, viewerId, now)];
      if (a.source === "expired_group")
        return [expiredRow(base(item), item.id, a, item.spacecraft[0]?.name ?? null, now)];
      if (a.source === "contact_scid_mismatch")
        return [scidMismatchRow(base(item), item.id, a, item.spacecraft[0]?.name ?? null, now)];
      if (a.source === "job_outcome_unknown")
        return [jobRow(base(item), item.id, a, item.spacecraft[0]?.name ?? null, now)];
      if (a.source === "provider_change") {
        // U44: the pass in Contacts holds the decision; an approval counts down to its deadline.
        const pass = a.reservation_id ?? a.contact_id;
        const to: RouteLocationRaw = pass
          ? { name: "ops.contacts", query: { contact: pass } }
          : { name: "ops.contacts" };
        const deadline = a.deadline_at ?? a.provider_change?.deadline_at ?? null;
        return [
          {
            ...base(item),
            key: item.id,
            title: `${item.spacecraft[0]?.name ?? "Spacecraft"} · ${changeTitle(a, now)}`,
            titleTo: to,
            sentence: changeEvidence(a, now),
            meta: attentionMeta(a),
            ...(a.conflict === "approval_required" && deadline && !pastDeadline(a, now)
              ? { due: { label: "Decide", at: deadline } }
              : {}),
            action: { label: "Review", to },
          },
        ];
      }
      const w = attentionWords(a);
      const pass = a.reservation_id ?? a.contact_id;
      const to: RouteLocationRaw = pass
        ? { name: "ops.contacts", query: { contact: pass } }
        : { name: "ops.contacts" };
      return [
        {
          ...base(item),
          key: item.id,
          title: `${item.spacecraft[0]?.name ?? "Spacecraft"} · ${w.what}`,
          titleTo: to,
          sentence: w.evidence,
          meta: attentionMeta(a),
          acknowledged: a.state === "acknowledged",
          // A settlement is about a past pass: no AOS countdown.
          ...(a.backlog || !a.starts_at ? {} : { due: { label: "AOS", at: a.starts_at } }),
          // U37: Retry storing once replay stopped; Mark as seen closes lost telemetry (bda6f91d).
          ...(a.backlog?.lost
            ? { command: { label: "Mark as seen", kind: "seen" as const, targets: [a] } }
            : a.backlog && a.retry === "manual"
              ? { command: { label: "Retry storing", kind: "retry" as const, targets: [a] } }
              : {}),
          action: { label: "Review", to },
        },
      ];
    }
    case "station":
      return item.station_issue ? [stationRow(item.id, item.station_issue, base(item))] : [];
    case "missed_pass":
      // Grouped across items in presentQueue (U35).
      return [];
    case "never_heard":
      return [
        {
          ...base(item),
          key: item.id,
          title: `${plural(item.spacecraft.length, "spacecraft", "spacecraft")} not heard from yet`,
          titleTo: null,
          sentence: "No telemetry has been received from these spacecraft.",
          action: { label: "Fleet", to: { name: "ops.fleet", query: { state: "never_heard" } } },
        },
      ];
  }
}

/** A flight event's state as text: JSON strings unquoted ("SAFE"), else as sent. */
function flightValue(json: string): string {
  try {
    const v: unknown = JSON.parse(json);
    return typeof v === "string" ? v : json;
  } catch {
    return json;
  }
}

const missedOf = (item: ServerItem): MissedItem | null => {
  const sc = item.spacecraft[0];
  return sc
    ? {
        id: item.id,
        priority: item.priority,
        state: STATE[item.state],
        scName: sc.name,
        spacecraftId: sc.id,
        scid: sc.scid,
        missed: item.missed_passes ?? [],
        next: item.next_contact ?? null,
      }
    : null;
};

/**
 * Server order is kept (contract: don't re-sort); small alarm groups expand in place. Missed-pass
 * rows group across items (U35) and sit where the first of them was.
 */
export function presentQueue(
  queue: ActionQueue,
  now: Date = new Date(),
  /** U38's row title names the mission (it has no spacecraft). */
  missionName: string | null = null,
  /** U61: the signed-in user, so a plan's author reads "You can't approve your own plan." */
  viewerId: string | null = null,
): QueueItem[] {
  const missed = queue.items.flatMap((i) => {
    const m = i.kind === "missed_pass" ? missedOf(i) : null;
    return m ? [m] : [];
  });
  const missedRows = missedPassRows(missed, queue.missed_pass_horizon_s ?? 6 * 3600);
  // U37: settlements sharing a failure_kind fold into one row, where the first of them was.
  const folds = new Map<string, Settlement[]>();
  for (const i of queue.items) {
    const s = settlementOf(i);
    if (s) folds.set(foldKey(s), [...(folds.get(foldKey(s)) ?? []), s]);
  }
  const placedFolds = new Set<string>();
  let placed = false;
  return queue.items.flatMap((item) => {
    const s = settlementOf(item);
    const fold = s ? folds.get(foldKey(s)) : undefined;
    if (s && fold && fold.length >= FOLD_AT) {
      if (placedFolds.has(foldKey(s))) return [];
      placedFolds.add(foldKey(s));
      return [foldedSettlementRow(fold, now)];
    }
    if (item.kind !== "missed_pass") return rowFor(item, missionName, now, viewerId);
    if (placed) return [];
    placed = true;
    return missedRows;
  });
}

function settlementOf(item: ServerItem): Settlement | null {
  const a = item.attention;
  if (item.kind !== "attention" || !a?.backlog || !a.starts_at) return null;
  const sc = item.spacecraft[0];
  return {
    itemId: item.id,
    spacecraft: sc ? { id: sc.id, name: sc.name } : null,
    attention: { ...a, backlog: a.backlog, starts_at: a.starts_at },
  };
}
