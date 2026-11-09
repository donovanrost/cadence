import type { RouteLocationRaw } from "vue-router";
import { decoders as d, request, type ApiResult, type Decoded } from "@/api/index.ts";
import { plural, type OpState } from "@/ui";
import {
  conditionWords,
  engineeringValue,
  formatValue,
  withUnit,
} from "@/features/alarms/index.ts";
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
});
type Member = Decoded<typeof member>;

const commandRequest = d.object({
  id: d.token,
  command_name: d.string,
  target: d.nullable(d.object({ id: d.token, name: d.string })),
  requested_by: d.nullable(d.string),
  status: d.token,
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
  ] as const),
  state: d.oneOf(["critical", "caution", "stale", "off"] as const),
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
  finding: d.nullable(d.object({ id: d.token, title: d.string, body: d.nullable(d.string) })),
});
type ServerItem = Decoded<typeof itemReader>;

export const actionQueueReader = d.object({
  observed_at: d.timestamp,
  counts: d.object({ p1: d.integer, p2: d.integer, p3: d.integer, spacecraft_p1: d.integer }),
  items: d.array(itemReader, 1_000),
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
    meta: sc.stale ? "LAST KNOWN · TELEMETRY STALE" : null,
    action: { label: "Engage", to: investigate(sc) },
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
      const first = item.command_requests[0];
      return [
        {
          ...base(item),
          key: item.id,
          title: `${plural(item.command_requests.length, "command request")} ${item.command_requests.length === 1 ? "awaits" : "await"} your GO`,
          titleTo: null,
          sentence: first
            ? `${first.command_name}${first.target ? ` · ${first.target.name}` : ""}${first.requested_by ? ` · by ${first.requested_by}` : ""}${item.command_requests.length > 1 ? " and more" : ""}`
            : "Requested by another operator.",
          action: { label: "Review", to: { name: "ops.commands", query: { awaiting: "me" } } },
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
