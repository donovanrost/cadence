import type { RouteLocationRaw } from "vue-router";
import { decoders as d, request, type ApiResult, type Decoded } from "@/api/index.ts";
import { plural, type OpState } from "@/ui";
import {
  conditionWords,
  engineeringValue,
  formatValue,
  withUnit,
} from "@/features/alarms/index.ts";
import { attentionMeta, attentionReader, attentionWords, resolvedReader } from "./attention.ts";
import { GROUP_AT, type QueueItem } from "./queue.ts";

/** Contract: docs/apogee/api/ops.md, `GET /missions/:mission_id/action-queue` (M6). Server-ranked. */

const priority: d.Reader<1 | 2 | 3> = (value, path = "") => {
  if (value === 1 || value === 2 || value === 3) return value;
  throw new d.DecodeError(path, "1 | 2 | 3");
};

const member = d.object({
  id: d.token,
  name: d.string,
  scid: d.integer,
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
  acknowledged_by: d.nullable(
    d.object({ kind: d.token, id: d.nullable(d.token), name: d.nullable(d.string) }),
  ),
});
type Member = Decoded<typeof member>;

const commandRequest = d.object({
  id: d.token,
  command_name: d.string,
  target: d.nullable(d.object({ id: d.token, name: d.string })),
  requested_by: d.nullable(d.string),
  status: d.token,
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
  kind: d.oneOf([
    "alarm",
    "command_failed",
    "approval",
    "stale",
    "setup",
    "limits_not_configured",
    "never_heard",
    "attention",
  ] as const),
  state: d.oneOf(["critical", "caution", "stale", "off"] as const),
  source: d.nullable(
    d.oneOf(["catalog_monitoring", "ground_limit", "pass_resolution", "uplink_blocked"] as const),
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
  condition: d.nullable(d.token),
  plane: d.nullable(d.integer),
  command: d.nullable(d.object({ id: d.token, name: d.string })),
  outcome: d.nullable(d.oneOf(["failed", "indeterminate"] as const)),
  command_requests: d.array(commandRequest, 1_000),
  /** Approval items: command groups awaiting the viewer's GO (one each). */
  command_groups: d.optional(d.array(commandGroup, 1_000)),
  finding: d.nullable(d.object({ id: d.token, title: d.string, body: d.nullable(d.string) })),
  // U31 (fafe581a): null on other kinds; optional until api ships it.
  attention: d.optional(d.nullable(attentionReader)),
});
type ServerItem = Decoded<typeof itemReader>;

export const actionQueueReader = d.object({
  observed_at: d.timestamp,
  counts: d.object({ p1: d.integer, p2: d.integer, p3: d.integer, spacecraft_p1: d.integer }),
  items: d.array(itemReader, 1_000),
  resolved: d.optional(d.array(resolvedReader, 1_000)),
});
export type ActionQueue = Decoded<typeof actionQueueReader>;

export function fetchActionQueue(
  missionId: string,
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
  params: { scId: String(sc.scid), tab: "investigate" },
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
  const why = `${point} ${conditionWords(item.condition) ?? "out of limits"}`;
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

function rowFor(item: ServerItem): QueueItem[] {
  switch (item.kind) {
    case "alarm":
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
    case "attention": {
      const a = item.attention;
      if (!a) return [];
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
          due: { label: "AOS", at: a.starts_at },
          action: { label: "Review", to },
        },
      ];
    }
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

/** Server order is kept (contract: don't re-sort); small alarm groups expand in place. */
export const presentQueue = (queue: ActionQueue): QueueItem[] => queue.items.flatMap(rowFor);
