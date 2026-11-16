import type { RouteLocationRaw } from "vue-router";
import { plural, type OpState } from "@/ui";
import type { Fleet, FleetSpacecraft } from "./api.ts";

/** Fleet stat strip, shared by Now and Fleet (Now spec + ux U10/U13). A count is a number only when it could be non-zero. */

export type StatTile = Readonly<{
  label: string;
  value: number | null;
  denominator?: number;
  caption: string;
  state: OpState;
  /** Tints only the caption: the call to action under an un-accented value. */
  captionState?: OpState;
  /** The list behind the number (Now links its tiles; Fleet's own strip doesn't). */
  to: RouteLocationRaw;
}>;

const NOT_TRACKED = "not tracked yet";
const NO_TLM = "no telemetry yet";
const NO_FRESH = "no fresh telemetry";
const NO_LIMITS = "limits not configured";

const accent = (n: number | null, state: OpState): OpState =>
  n !== null && n > 0 ? state : "neutral";

/**
 * U13: a zero we couldn't have observed is unknown. Positive counts always show (e.g. criticals
 * from flight events while ground limits are off).
 */
function knowable(value: number, unknownBecause: string | null, caption: string) {
  return value === 0 && unknownBecause !== null
    ? { value: null, caption: unknownBecause }
    : { value, caption };
}

export function statTiles(fleet: Fleet): StatTile[] {
  const c = fleet.counts;
  const cmd = fleet.commands;
  // U13 refined: nothing ever heard → "no telemetry yet"; heard but none fresh → "no fresh
  // telemetry"; for limit counts, "limits not configured" wins over both.
  const neverHeard = c.total > 0 && c.never_heard === c.total;
  const noTlm = neverHeard ? NO_TLM : c.fresh === 0 ? NO_FRESH : null;
  const limitsUnknown = fleet.limits.configured ? noTlm : NO_LIMITS;
  const minutes = Math.round(fleet.stale_after_s / 60);
  const delta = c.critical_delta_1h;
  const critCaption =
    delta === null
      ? "out of limits"
      : `${delta >= 0 ? "+" : "−"}${Math.abs(delta)} in the last hour`;

  return [
    {
      label: "Nominal",
      value: c.nominal,
      denominator: c.total,
      caption:
        c.never_heard > 0 ? `+${c.never_heard} awaiting first contact` : "fresh and in limits",
      state: "neutral",
      to: { name: "ops.fleet", query: { state: "nominal" } },
    },
    {
      label: "Caution",
      ...knowable(c.caution, limitsUnknown, "near a limit"),
      state: accent(c.caution, "caution"),
      to: { name: "ops.alarms", query: { severity: "caution" } },
    },
    {
      label: "Critical",
      ...knowable(c.critical, limitsUnknown, critCaption),
      state: accent(c.critical, "crit"),
      to: { name: "ops.alarms", query: { severity: "critical" } },
    },
    {
      label: "Stale",
      ...knowable(
        c.stale,
        neverHeard ? NO_TLM : null,
        `no TLM over ${plural(minutes, "min", "min")}`,
      ),
      state: accent(c.stale, "stale"),
      to: { name: "ops.fleet", query: { state: "stale" } },
    },
    {
      label: "In contact",
      value: c.in_contact,
      caption:
        c.passes_next_2h === null
          ? NOT_TRACKED
          : `${plural(c.passes_next_2h, "pass", "passes")} next 2 h`,
      state: accent(c.in_contact, "live"),
      to: { name: "ops.contacts" },
    },
    {
      label: "Uplinks queued",
      value: cmd.queued,
      caption: `${cmd.awaiting_viewer} await your GO`,
      state: "neutral",
      to:
        cmd.awaiting_viewer > 0
          ? { name: "ops.commands", query: { awaiting: "me" } }
          : { name: "ops.commands" },
      ...(cmd.awaiting_viewer > 0 ? { captionState: "caution" as const } : {}),
    },
  ];
}

/**
 * A fleet snapshot narrowed to `rows`, with the per-spacecraft counts recomputed so the stat strip
 * describes the filtered set. Mission-wide figures (commands, limits, contact totals) are kept.
 */
export function fleetSubset(fleet: Fleet, rows: readonly FleetSpacecraft[]): Fleet {
  const n = (state: FleetSpacecraft["state"]) => rows.filter((sc) => sc.state === state).length;
  return {
    ...fleet,
    counts: {
      ...fleet.counts,
      total: rows.length,
      critical: n("critical"),
      caution: n("caution"),
      stale: n("stale"),
      nominal: n("nominal"),
      never_heard: n("never_heard"),
      fresh: rows.filter((sc) => !sc.stale && sc.state !== "never_heard").length,
    },
    spacecraft: rows,
  };
}
