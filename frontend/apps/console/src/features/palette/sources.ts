import type { RouteLocationRaw } from "vue-router";
import { formatHourMinute, type OpState } from "@/ui";
import type { CommandSummary } from "@/features/commands/index.ts";
import type { Station } from "@/features/stations/index.ts";
import type { PaletteItem } from "./results.ts";

/**
 * ⌘K Commands (`>`) and Stations (`@`) groups (Palette.md). Commands come from the M17 catalog
 * search (`q` matches id, name, display name, description, subsystem); stations are the
 * mission's list, matched here on code and name.
 */

/** Null when the catalog isn't worth asking: no prefix needs 2 characters; `>` alone lists. */
export function catalogQuery(text: string, only: string | null): string | null {
  if (only === "commands") return text;
  if (only !== null) return null;
  return text.length >= 2 ? text : null;
}

/** Routine has no word: it isn't a risk. */
const SIGNIFICANCE: Readonly<Partial<Record<NonNullable<CommandSummary["significance"]>, string>>> =
  {
    critical: "Critical",
    hazardous: "Hazardous",
    warning: "Warning",
  };

function commandSubtitle(c: CommandSummary): string {
  const args =
    c.argument_count === 0
      ? "no arguments"
      : c.argument_count === 1
        ? "1 argument"
        : `${c.argument_count} arguments`;
  const risk = c.hazardous ? "Hazardous" : c.critical ? "Critical" : null;
  return [
    risk ?? (c.significance ? (SIGNIFICANCE[c.significance] ?? null) : null),
    c.display_name && c.display_name !== c.name ? c.display_name : (c.description ?? null),
    c.subsystem ?? c.group,
    args,
  ]
    .filter((p): p is string => Boolean(p))
    .join(" · ");
}

/** Rank: exact name, name prefix, then the server's order. */
function commandRank(c: CommandSummary, text: string, index: number): number {
  const name = c.name.toLowerCase();
  if (text && name === text) return 0;
  if (text && name.startsWith(text)) return 1 + index / 1000;
  return 2 + index / 1000;
}

/** ↵ and ⌘↵ both start a new request with this command (targets empty). */
export function commandItems(commands: readonly CommandSummary[], text: string): PaletteItem[] {
  return commands
    .map((c, index) => {
      const to: RouteLocationRaw = { name: "ops.commands.new", query: { command: c.id } };
      return {
        key: `command-${c.id}`,
        group: "Commands" as const,
        title: c.name,
        subtitle: commandSubtitle(c),
        hint: "CATALOG",
        state: c.hazardous || c.critical ? ("caution" as const) : null,
        to,
        commandTo: to,
        rank: commandRank(c, text, index),
      };
    })
    .sort((a, b) => a.rank - b.rank);
}

const HEALTH: Readonly<
  Record<NonNullable<Station["health"]>["status"], { word: string; state: OpState }>
> = {
  nominal: { word: "Nominal", state: "nominal" },
  degraded: { word: "Degraded", state: "caution" },
  down: { word: "Down", state: "crit" },
};

function stationRank(s: Station, text: string): number | null {
  if (text === "") return 3;
  const code = (s.code ?? "").toLowerCase();
  const name = s.display_name.toLowerCase();
  if (code === text) return 0;
  if (code.startsWith(text)) return 1;
  if (name.startsWith(text)) return 2;
  if (name.includes(text) || (s.region ?? "").toLowerCase().includes(text)) return 3;
  return null;
}

/** Active stations matching `text` (all of them when empty), code matches first. */
export function stationItems(stations: readonly Station[], text: string): PaletteItem[] {
  return stations
    .filter((s) => s.lifecycle_state === "active")
    .map((s) => ({ s, rank: stationRank(s, text) }))
    .filter((m): m is { s: Station; rank: number } => m.rank !== null)
    .sort((a, b) => a.rank - b.rank || a.s.display_name.localeCompare(b.s.display_name))
    .map(({ s, rank }) => {
      const health = s.health ? HEALTH[s.health.status] : undefined;
      const since =
        health && s.health?.since && s.health.status !== "nominal"
          ? ` since ${formatHourMinute(new Date(s.health.since))}`
          : "";
      return {
        key: `station-${s.id}`,
        group: "Stations" as const,
        title: s.code ? `${s.code} · ${s.display_name}` : s.display_name,
        subtitle: [health ? `${health.word}${since}` : null, s.provider, s.region]
          .filter((p): p is string => Boolean(p))
          .join(" · "),
        hint: "STATION",
        state: health?.state ?? null,
        to: { name: "ops.contacts", query: { view: "station", station: s.id } },
        commandTo: null,
        rank,
      };
    });
}
