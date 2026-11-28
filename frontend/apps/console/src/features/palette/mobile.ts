import type { OpState } from "@/ui";
import type { Alarm } from "@/features/alarms/index.ts";
import type { GroupRow } from "@/features/commands/index.ts";
import { fleetOpState, fleetStateWord, type FleetSpacecraft } from "@/features/fleet/index.ts";
import { spacecraftRank, type Group, type PaletteItem } from "./results.ts";

/**
 * Phone search (Mobile.md › Search, ux 68d12603): Alarms → Requests → Spacecraft, matched here
 * over what the on-call tabs read. No prefixes and no "command it" on a phone.
 */
export const MOBILE_GROUPS: readonly Group[] = ["Recent", "Alarms", "Requests", "Spacecraft"];

/** `T+3m`, `T+2h`, `T+1d`: how long ago, in the largest whole unit. */
export function ago(iso: string | null, now: number): string | null {
  if (iso === null) return null;
  const s = Math.max(0, Math.round((now - Date.parse(iso)) / 1000));
  if (s < 3600) return `T+${Math.max(1, Math.floor(s / 60))}m`;
  if (s < 86_400) return `T+${Math.floor(s / 3600)}h`;
  return `T+${Math.floor(s / 86_400)}d`;
}

const SEVERITY: Readonly<Record<Alarm["severity"], OpState>> = {
  critical: "crit",
  caution: "caution",
  nominal: "nominal",
};

/** Active alarms whose spacecraft (name or SCID) or point matches; critical first, newest first. */
export function alarmItems(
  alarms: readonly Alarm[],
  fleet: ReadonlyMap<string, FleetSpacecraft>,
  text: string,
  now: number,
): PaletteItem[] {
  if (text === "") return [];
  return alarms
    .filter((a) => a.active)
    .flatMap((a) => {
      const sc = a.spacecraft_id ? fleet.get(a.spacecraft_id) : undefined;
      const scHit = sc ? spacecraftRank(sc, text) : null;
      const pointHit = a.point.name.toLowerCase().includes(text) ? 30 : null;
      const rank = scHit ?? pointHit;
      return rank === null || !sc ? [] : [{ a, sc, rank }];
    })
    .sort(
      (x, y) =>
        (x.a.severity === "critical" ? 0 : 1) - (y.a.severity === "critical" ? 0 : 1) ||
        x.rank - y.rank ||
        Date.parse(y.a.first_crossed_at ?? "0") - Date.parse(x.a.first_crossed_at ?? "0"),
    )
    .map(({ a, sc, rank }) => {
      // #1117: an alarm row carries no value, condition or limits; it says only since when.
      const since = ago(a.first_crossed_at, now);
      return {
        key: `alarm-${a.id}`,
        group: "Alarms" as const,
        title: `${sc.name} · ${a.point.name}`,
        subtitle: since === null ? "Out of limits" : `Out of limits since ${since}`,
        hint: "",
        state: SEVERITY[a.severity],
        to: {
          name: "ops.spacecraft",
          params: { scId: sc.scid, tab: "investigate" },
          query: { point: a.point.id },
        },
        commandTo: null,
        rank,
      };
    });
}

/** Open requests: awaiting this viewer's GO, waiting for approval, or released and not finished. */
const isOpen = (r: GroupRow) =>
  r.awaiting_me || r.state === "approval_pending" || (r.state === "queued" && r.finished !== true);

/** Awaiting your GO first (oldest first: nobody waits longest), then other open ones, newest first. */
export function requestItems(
  rows: readonly GroupRow[],
  text: string,
  nameOf: (userId: string | null) => string,
  now: number,
): PaletteItem[] {
  if (text === "") return [];
  return rows
    .filter(
      (r) =>
        isOpen(r) && (r.title.toLowerCase().includes(text) || r.id.toLowerCase().startsWith(text)),
    )
    .sort(
      (x, y) =>
        Number(y.awaiting_me) - Number(x.awaiting_me) ||
        (x.awaiting_me
          ? Date.parse(x.requested_at) - Date.parse(y.requested_at)
          : Date.parse(y.requested_at) - Date.parse(x.requested_at)),
    )
    .map((r, rank) => {
      const status = r.awaiting_me
        ? "Your GO"
        : r.state === "approval_pending"
          ? "Waiting for approval"
          : "Released";
      return {
        key: `request-${r.id}`,
        group: "Requests" as const,
        title: `${r.title} · ${r.target_count} SC`,
        subtitle: [status, nameOf(r.requested_by.user_id), ago(r.requested_at, now)]
          .filter((p): p is string => p !== null)
          .join(" · "),
        hint: "",
        state: r.awaiting_me ? ("caution" as const) : null,
        // Your GO → mobile Approve; anything else → its status, read-only.
        to: {
          name: "ops.commands.request",
          params: { requestId: r.id, view: r.awaiting_me ? "review" : "uplink" },
        },
        commandTo: null,
        rank,
      };
    });
}

/** Spacecraft by name or SCID; ↵ opens Investigate. */
export function phoneSpacecraftItems(
  fleet: readonly FleetSpacecraft[],
  text: string,
): PaletteItem[] {
  if (text === "") return [];
  return fleet
    .map((sc) => ({ sc, rank: spacecraftRank(sc, text) }))
    .filter((m): m is { sc: FleetSpacecraft; rank: number } => m.rank !== null)
    .sort((a, b) => a.rank - b.rank || a.sc.scid - b.sc.scid)
    .map(({ sc, rank }) => ({
      key: `sc-${sc.id}`,
      group: "Spacecraft" as const,
      title: sc.name,
      subtitle: [
        `SCID ${sc.scid}`,
        sc.plane === null ? null : `P${String(sc.plane).padStart(2, "0")}`,
        fleetStateWord(sc.state).toLowerCase(),
      ]
        .filter((p): p is string => p !== null)
        .join(" · "),
      hint: "",
      state: fleetOpState(sc.state),
      to: { name: "ops.spacecraft", params: { scId: sc.scid, tab: "investigate" } },
      commandTo: null,
      rank,
    }));
}
