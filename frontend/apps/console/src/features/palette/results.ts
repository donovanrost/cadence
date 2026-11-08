import type { RouteLocationRaw } from "vue-router";
import type { OpState } from "@/ui";
import { fleetOpState, fleetStateWord, type FleetSpacecraft } from "@/features/fleet/index.ts";

/**
 * ⌘K results (Palette.md). v1 searches client-side over what the console already has: the fleet
 * read (spacecraft, profiles, per-spacecraft actions) and the router (pages). Telemetry,
 * Commands and Stations groups appear when their search reads exist (ops plan M23/M17/M21).
 */

export const GROUPS = ["Spacecraft", "Actions", "Profiles", "Pages"] as const;
export type Group = (typeof GROUPS)[number];
export const PER_GROUP = 5;

export type PaletteItem = Readonly<{
  key: string;
  group: Group;
  title: string;
  subtitle: string;
  hint: string;
  state: OpState | null;
  to: RouteLocationRaw;
  /** ⌘↵ target ("command it"), when the row supports it. */
  commandTo: RouteLocationRaw | null;
  /** Lower ranks first within a group. */
  rank: number;
}>;

export type PageEntry = Readonly<{ name: string; title: string; mode: string }>;

/** `#` spacecraft only, `>` commands only (not searchable yet), `@` stations only (not yet). */
export function parseQuery(raw: string): {
  text: string;
  only: "spacecraft" | "commands" | "stations" | null;
} {
  const trimmed = raw.trim();
  const prefix = trimmed[0];
  const text = trimmed
    .slice(prefix === "#" || prefix === ">" || prefix === "@" ? 1 : 0)
    .trim()
    .toLowerCase();
  const only =
    prefix === "#"
      ? "spacecraft"
      : prefix === ">"
        ? "commands"
        : prefix === "@"
          ? "stations"
          : null;
  return { text, only };
}

function spacecraftItem(sc: FleetSpacecraft, rank: number): PaletteItem {
  const parts = [
    sc.worst_point
      ? `${fleetStateWord(sc.state)} · ${sc.worst_point.point_name}`
      : fleetStateWord(sc.state),
    sc.plane === null ? null : `plane ${String(sc.plane).padStart(2, "0")}`,
    sc.profile?.name ?? null,
  ].filter((p): p is string => p !== null);
  return {
    key: `sc-${sc.id}`,
    group: "Spacecraft",
    title: sc.name,
    subtitle: parts.join(" · "),
    hint: `SCID ${sc.scid}`,
    state: fleetOpState(sc.state),
    to: { name: "ops.spacecraft", params: { scId: String(sc.scid) } },
    commandTo: { name: "ops.commands.new", query: { targets: `sc:${sc.id}` } },
    rank,
  };
}

/** SCID matches rank first (numeric queries), then name prefix, then name substring. */
function spacecraftRank(sc: FleetSpacecraft, text: string): number | null {
  if (text === "") return null;
  const scid = String(sc.scid);
  const name = sc.name.toLowerCase();
  if (scid === text) return 0;
  if (/^\d+$/.test(text) && scid.startsWith(text)) return 1 + scid.length;
  if (name.startsWith(text)) return 10;
  if (name.includes(text)) return 20;
  return null;
}

export function search(
  raw: string,
  fleet: readonly FleetSpacecraft[],
  pages: readonly PageEntry[],
): PaletteItem[] {
  const { text, only } = parseQuery(raw);
  if (only === "commands" || only === "stations") return [];
  const items: PaletteItem[] = [];

  const matched = fleet
    .map((sc) => ({ sc, rank: spacecraftRank(sc, text) }))
    .filter((m): m is { sc: FleetSpacecraft; rank: number } => m.rank !== null)
    .sort((a, b) => a.rank - b.rank || a.sc.scid - b.sc.scid);
  items.push(...matched.map((m) => spacecraftItem(m.sc, m.rank)));
  if (only === "spacecraft") return items;

  const top = matched[0]?.sc;
  if (top && matched.length <= 3) {
    items.push({
      key: `cmd-${top.id}`,
      group: "Actions",
      title: `Command ${top.name}…`,
      subtitle: "Open a new command request with this target",
      hint: "⌘↵",
      state: null,
      to: { name: "ops.commands.new", query: { targets: `sc:${top.id}` } },
      commandTo: null,
      rank: 0,
    });
  }

  const profiles = new Map<string, { name: string; version: number | null; count: number }>();
  for (const sc of fleet) {
    if (!sc.profile?.name) continue;
    const entry = profiles.get(sc.profile.id) ?? {
      name: sc.profile.name,
      version: sc.profile.version,
      count: 0,
    };
    entry.count += 1;
    profiles.set(sc.profile.id, entry);
  }
  for (const [id, p] of profiles) {
    if (text === "" || !p.name.toLowerCase().includes(text)) continue;
    items.push({
      key: `profile-${id}`,
      group: "Profiles",
      title: p.name,
      subtitle: `${p.count} spacecraft${p.version === null ? "" : ` · v${p.version}`}`,
      hint: "PROFILE",
      state: null,
      to: { name: "setup.profile", params: { profileId: id } },
      commandTo: null,
      rank: 0,
    });
  }

  for (const page of pages) {
    if (text !== "" && !page.title.toLowerCase().includes(text)) continue;
    items.push({
      key: `page-${page.name}`,
      group: "Pages",
      title: page.title,
      subtitle: page.mode === "setup" ? "Setup" : "Ops",
      hint: page.name === "ops.now" ? "G N" : page.name === "ops.contacts" ? "G C" : "PAGE",
      state: null,
      to: { name: page.name },
      commandTo: null,
      rank: 0,
    });
  }
  return items;
}

export type GroupView = Readonly<{ group: Group; items: readonly PaletteItem[]; more: number }>;

/** Groups in spec order, max PER_GROUP rows each unless the group is expanded. */
export function grouped(items: readonly PaletteItem[], expanded: ReadonlySet<Group>): GroupView[] {
  return GROUPS.flatMap((group) => {
    const all = items.filter((item) => item.group === group);
    if (all.length === 0) return [];
    const shown = expanded.has(group) ? all : all.slice(0, PER_GROUP);
    return [{ group, items: shown, more: all.length - shown.length }];
  });
}
