import type { RouteLocationRaw } from "vue-router";
import { plural, type OpState } from "@/ui";
import { conditionWords, formatValue, withUnit } from "@/features/alarms/index.ts";
import {
  actionQueueReader,
  fetchActionQueue,
  type ActionQueue,
  type Member,
  type ServerItem,
} from "./actionQueueReader.ts";
import { attentionMeta, attentionWords } from "./attention.ts";
import { activationRow } from "./activation.ts";
import { archiveRow } from "./archive.ts";
import { changeSetRow } from "./changeSet.ts";
import { contactStartRow } from "./contactStart.ts";
import { coverageRow } from "./coverage.ts";
import { expiredRow } from "./expiredGroup.ts";
import { ingressRow } from "./ingress.ts";
import { jobRow } from "./jobs.ts";
import { diskRow } from "./journalDisk.ts";
import { listenerRow } from "./listener.ts";
import { changeEvidence, changeTitle, pastDeadline } from "./providerChange.ts";
import { GROUP_AT, type QueueItem } from "./queue.ts";
import { runtimeRow } from "./runtime.ts";
import { scidMismatchRow } from "./scidMismatch.ts";
import { stuckRow, tagStuck } from "./stuckRow.ts";
import { FOLD_AT, foldedSettlementRow, foldKey, type Settlement } from "./settlement.ts";
import { missedPassRows, stationRow, type MissedItem } from "./sources.ts";
import { ephemerisRow } from "./providerEphemeris.ts";
import { withdrawnRow } from "./withdrawnComposition.ts";

/** Now's action queue as rows (M6): the server's ranked items, worded per source. */
export { actionQueueReader, fetchActionQueue, type ActionQueue };

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
      if (a.source === "replay_conflict") return [stuckRow(base(item), item.id, a, now)];
      if (a.source === "model_approval_withdrawn") {
        const row = withdrawnRow(base(item), item.id, a, item.spacecraft[0] ?? null);
        return row ? [row] : [];
      }
      if (a.source === "provider_ephemeris")
        return [ephemerisRow(base(item), item.id, a, item.since, now)];
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
      return [
        tagStuck(
          foldedSettlementRow(fold, now),
          fold.map((m) => m.attention),
        ),
      ];
    }
    if (item.kind !== "missed_pass") {
      const rows = rowFor(item, missionName, now, viewerId);
      // U84: settlement, buffer and runtime items caused by stuck processing say so.
      const a = item.attention;
      return a ? rows.map((r) => tagStuck(r, [a])) : rows;
    }
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
