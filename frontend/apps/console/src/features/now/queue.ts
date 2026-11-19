import type { SpacecraftTab } from "@/shell";
import type { RouteLocationRaw } from "vue-router";
import { plural, type OpState } from "@/ui";
import type { Fleet, FleetSpacecraft, RawLimitState } from "@/features/fleet/index.ts";
import type { Attention } from "./attention.ts";

/**
 * Interim action queue for Now (A2), derived from the fleet read until api's ranked
 * `GET …/action-queue` (ops plan M6) lands. Ranking follows ux U11: P1 critical, P2 caution /
 * stale groups / a GO waiting on you, P3 setup gaps; identical causes are grouped. Every row is
 * a fact from the snapshot; nothing here is estimated.
 */

export type QueueAction = Readonly<{ label: string; to: RouteLocationRaw }>;
/** A sentence piece: text, a link (U66's holders), or text kept on one line (U84's craft names). */
export type SentencePart =
  | string
  | Readonly<{ text: string; to: RouteLocationRaw }>
  | Readonly<{ text: string; nowrap: true }>;

/**
 * ux U84: `text` with each of `names` kept whole when the line wraps ("EARENDIL-004" never breaks
 * at its hyphen). Longer names first, so one name inside another stays whole.
 */
export function keepWhole(text: string, names: readonly string[]): SentencePart[] {
  const wanted = [...new Set(names.filter(Boolean))].sort((a, b) => b.length - a.length);
  const parts: SentencePart[] = [];
  let rest = text;
  while (rest) {
    let at = -1;
    let hit = "";
    for (const n of wanted) {
      const i = rest.indexOf(n);
      if (i >= 0 && (at < 0 || i < at)) [at, hit] = [i, n];
    }
    if (at < 0) {
      parts.push(rest);
      break;
    }
    if (at > 0) parts.push(rest.slice(0, at));
    parts.push({ text: hit, nowrap: true });
    rest = rest.slice(at + hit.length);
  }
  return parts;
}

export type QueueItem = Readonly<{
  key: string;
  priority: 1 | 2 | 3;
  state: OpState;
  title: string;
  /** Route for the title link; null for group rows without one target. */
  titleTo: RouteLocationRaw | null;
  sentence: string;
  /** The sentence with links in it; `sentence` is its plain text. */
  sentenceParts?: readonly SentencePart[];
  meta: string | null;
  action: QueueAction;
  /** The action is primary whatever the row's place (U38: a configuration that needs a fix). */
  primary?: boolean;
  /** Every alarm behind the row is acknowledged (U21): keeps its priority, action 'Open', never primary. */
  acknowledged?: boolean;
  /** A consequence time the row counts down to live, after the meta (`AOS T−01:12:00`). */
  due?: Readonly<{ label: string; at: string }>;
  /** Spacecraft this row is about (for the "N spacecraft need you" headline). */
  spacecraftIds: readonly string[];
  /** A folded row's item ids (U37): it fades when the last of them resolves. */
  memberKeys?: readonly string[];
  /**
   * A write in place of the route action (U37 Retry storing): POST per target. The panel shows it
   * only with operate access, else "Operators can retry storing."
   */
  command?: Readonly<{
    label: string;
    /** U61: 'book' is Start / Continue booking (POST …/contact-plans/:id/execute). */
    kind: "retry" | "seen" | "book";
    targets: readonly Attention[];
  }>;
  /** U49: a second write beside Retry, `Discard…`, which opens a sheet for its required reason. */
  discard?: Attention;
  /** U54: `Retry…` and `Close without retry…`, each a sheet (operators only). */
  job?: Attention;
  /** U84: the stuck-processing item; its action opens the Stuck processing sheet. */
  stuck?: Attention;
  /** The row has nothing to open (a job with no pass): no route button. */
  noAction?: boolean;
  /** A folded row's members: its action opens them in a sheet (U30 pattern) instead of routing. */
  list?: Readonly<{ title: string; rows: readonly QueueListRow[] }>;
}>;

export type QueueListRow = Readonly<{
  key: string;
  text: string;
  detail: string | null;
  to: RouteLocationRaw;
}>;

/** Groups at or above this size collapse into one row (U11: group identical causes). */
export const GROUP_AT = 3;

/** green and blue have no words: the row falls back to the limit state. */
const LIMIT_WORDS: Readonly<Partial<Record<RawLimitState, string>>> = {
  red_low: "below red limit",
  red_high: "above red limit",
  yellow_low: "below yellow limit",
  yellow_high: "above yellow limit",
};

const spacecraftRoute = (
  sc: FleetSpacecraft,
  tab: SpacecraftTab = "investigate",
): RouteLocationRaw => ({
  name: "ops.spacecraft",
  params: { scId: sc.scid, tab },
});

function cause(sc: FleetSpacecraft): string {
  const point = sc.worst_point;
  if (!point) return sc.state === "critical" ? "out of limits" : "near limits";
  const raw = point.raw_limit_state;
  const words = raw !== null && raw !== "unrecognized" ? LIMIT_WORDS[raw] : undefined;
  return `${point.point_name} ${words ?? point.limit_state}`;
}

function evidence(sc: FleetSpacecraft): string {
  const point = sc.worst_point;
  const extra =
    sc.violating_points > 1 ? ` · ${plural(sc.violating_points, "point")} out of limits` : "";
  if (!point || point.value === null) return `Last limit evaluation is out of limits${extra}.`;
  return `${point.point_name} reads ${String(point.value)}${extra}.`;
}

function names(members: readonly FleetSpacecraft[], max = 4): string {
  const shown = members.slice(0, max).map((sc) => sc.name);
  const more = members.length - shown.length;
  return more > 0 ? `${shown.join(", ")} and ${more} more` : shown.join(", ");
}

function limitItems(fleet: Fleet, state: "critical" | "caution"): QueueItem[] {
  const members = fleet.spacecraft.filter((sc) => sc.state === state);
  const groups = new Map<string, FleetSpacecraft[]>();
  for (const sc of members) {
    const key = cause(sc);
    groups.set(key, [...(groups.get(key) ?? []), sc]);
  }
  const priority = state === "critical" ? 1 : 2;
  const opState: OpState = state === "critical" ? "crit" : "caution";
  return [...groups.entries()].flatMap(([why, group]): QueueItem[] => {
    if (group.length >= GROUP_AT)
      return [
        {
          key: `${state}-group-${why}`,
          priority,
          state: opState,
          title: `${plural(group.length, "spacecraft", "spacecraft")} · ${why}`,
          titleTo: null,
          sentence: names(group),
          meta: null,
          // ux U69 A6: Alarms filters by severity (?severity=), the group's own.
          action: { label: "Alarms", to: { name: "ops.alarms", query: { severity: state } } },
          spacecraftIds: group.map((sc) => sc.id),
        },
      ];
    return group.map((sc) => ({
      key: `${state}-${sc.id}`,
      priority,
      state: opState,
      title: `${sc.name} · ${why}`,
      titleTo: spacecraftRoute(sc),
      sentence: evidence(sc),
      meta: sc.stale ? "LAST KNOWN · TELEMETRY STALE" : null,
      action: { label: "Engage", to: spacecraftRoute(sc) },
      spacecraftIds: [sc.id],
    }));
  });
}

function staleItems(fleet: Fleet): QueueItem[] {
  const stale = fleet.spacecraft.filter((sc) => sc.state === "stale");
  const byPlane = new Map<number | null, FleetSpacecraft[]>();
  for (const sc of stale) byPlane.set(sc.plane, [...(byPlane.get(sc.plane) ?? []), sc]);
  const minutes = Math.round(fleet.stale_after_s / 60);
  return [...byPlane.entries()].map(([plane, group]) => ({
    key: `stale-${plane ?? "none"}`,
    priority: 2,
    state: "stale",
    title:
      plane === null
        ? `${plural(group.length, "spacecraft", "spacecraft")} stale`
        : `${group.length} in plane ${plane} stale`,
    titleTo: null,
    sentence: `No telemetry for over ${plural(minutes, "minute")}: ${names(group)}.`,
    meta: null,
    action: {
      label: "Fleet",
      to: {
        name: "ops.fleet",
        query: plane === null ? { state: "stale" } : { state: "stale", plane: String(plane) },
      },
    },
    spacecraftIds: group.map((sc) => sc.id),
  }));
}

function approvalItems(fleet: Fleet): QueueItem[] {
  const waiting = fleet.commands.awaiting_viewer;
  if (waiting === 0) return [];
  return [
    {
      key: "approvals",
      priority: 2,
      state: "caution",
      title: `${plural(waiting, "command request")} ${waiting === 1 ? "awaits" : "await"} your GO`,
      titleTo: null,
      sentence: "Requested by another operator. Nothing radiates until it has a GO.",
      meta: null,
      action: { label: "Review", to: { name: "ops.commands" } },
      spacecraftIds: [],
    },
  ];
}

function setupItems(fleet: Fleet): QueueItem[] {
  const items: QueueItem[] = [];
  if (!fleet.limits.configured)
    items.push({
      key: "limits-not-configured",
      priority: 3,
      state: "off",
      title: "Ground limits not configured",
      titleTo: null,
      sentence:
        "No point is checked against limits on this mission, so nothing here can be critical or caution.",
      meta: null,
      action: { label: "Set up", to: { name: "setup.apps" } },
      spacecraftIds: [],
    });
  const never = fleet.spacecraft.filter((sc) => sc.state === "never_heard");
  if (never.length > 0)
    items.push({
      key: "never-heard",
      priority: 3,
      state: "off",
      title: `${plural(never.length, "spacecraft", "spacecraft")} not heard from yet`,
      titleTo: null,
      sentence: "No telemetry has been received from these spacecraft.",
      meta: null,
      action: { label: "Fleet", to: { name: "ops.fleet", query: { state: "never_heard" } } },
      spacecraftIds: never.map((sc) => sc.id),
    });
  return items;
}

/** Ranked queue: priority first, then the order the sections are listed in (stable). */
export function deriveQueue(fleet: Fleet): QueueItem[] {
  return [
    ...limitItems(fleet, "critical"),
    ...approvalItems(fleet),
    ...limitItems(fleet, "caution"),
    ...staleItems(fleet),
    ...setupItems(fleet),
  ].sort((a, b) => a.priority - b.priority);
}

/** The page h1 (Now spec, Header). */
export function nowHeadline(fleet: Fleet, queue: readonly QueueItem[]): string {
  const c = fleet.counts;
  if (c.total === 0) return "No spacecraft yet";
  const needYou = new Set(
    queue.filter((item) => item.priority === 1).flatMap((item) => item.spacecraftIds),
  );
  // ux §7: "1 spacecraft needs you", "3 spacecraft need you".
  if (needYou.size > 0)
    return `${plural(needYou.size, "spacecraft", "spacecraft")} ${needYou.size === 1 ? "needs" : "need"} you`;
  const watch = c.caution + c.stale;
  if (watch > 0) return `${plural(watch, "spacecraft", "spacecraft")} to watch`;
  if (c.never_heard === c.total) return "No telemetry yet";
  if (c.nominal === c.total) return `All ${c.total} nominal`;
  return `${c.nominal} nominal · ${c.never_heard} not heard yet`;
}
