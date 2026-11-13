import { linkByName, type ParamlessRouteName } from "@/shell";
import type { RouteLocationRaw } from "vue-router";
import type { OpState } from "@/ui";
import { fleetOpState, fleetStateWord, type FleetSpacecraft } from "@/features/fleet/index.ts";

/**
 * ⌘K results (Palette.md). v1 searches client-side over what the console already has: the fleet
 * read (spacecraft, profiles, per-spacecraft actions) and the router (pages). Alarms and
 * Requests are phone-only groups (mobile.ts). Telemetry comes
 * from the M23 point search (telemetry.ts); Commands (M17 catalog) and Stations from sources.ts.
 */

export const GROUPS = [
  "Recent",
  "Alarms",
  "Requests",
  "Spacecraft",
  "Telemetry",
  "Actions",
  "Commands",
  "Stations",
  "Profiles",
  "Pages",
] as const;
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

export type PageEntry = Readonly<{ name: ParamlessRouteName; title: string; mode: string }>;

/** `#` spacecraft only, `>` commands only, `@` stations only. */
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

function spacecraftItem(sc: FleetSpacecraft, rank: number, canCommand: boolean): PaletteItem {
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
    to: { name: "ops.spacecraft", params: { scId: sc.scid } },
    commandTo: canCommand ? { name: "ops.commands.new", query: { targets: `sc:${sc.id}` } } : null,
    rank,
  };
}

/** SCID matches rank first (numeric queries), then name prefix, then name substring. */
export function spacecraftRank(sc: FleetSpacecraft, text: string): number | null {
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
  /** Command entries only for viewers the server lets request commands (DECISIONS #38). */
  canCommand: boolean,
): PaletteItem[] {
  const { text, only } = parseQuery(raw);
  if (only === "commands" || only === "stations") return [];
  const items: PaletteItem[] = [];

  const matched = fleet
    .map((sc) => ({ sc, rank: spacecraftRank(sc, text) }))
    .filter((m): m is { sc: FleetSpacecraft; rank: number } => m.rank !== null)
    .sort((a, b) => a.rank - b.rank || a.sc.scid - b.sc.scid);
  items.push(...matched.map((m) => spacecraftItem(m.sc, m.rank, canCommand)));
  if (only === "spacecraft") return items;

  const top = matched[0]?.sc;
  if (canCommand && top && matched.length <= 3) {
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
      to: linkByName(page.name),
      commandTo: null,
      rank: 0,
    });
  }
  return items;
}

export type GroupView = Readonly<{ group: Group; items: readonly PaletteItem[]; more: number }>;

/** Setup mode ranks Profiles, Stations, Pages first (Palette.md; there's no Catalog group yet). */
export const SETUP_GROUPS: readonly Group[] = [
  "Recent",
  "Profiles",
  "Stations",
  "Pages",
  "Spacecraft",
  "Telemetry",
  "Actions",
  "Commands",
];

/** Groups in spec order (or `order`), max PER_GROUP rows each unless the group is expanded. */
export function grouped(
  items: readonly PaletteItem[],
  expanded: ReadonlySet<Group>,
  order: readonly Group[] = GROUPS,
): GroupView[] {
  return order.flatMap((group) => {
    const all = items.filter((item) => item.group === group);
    if (all.length === 0) return [];
    const shown = expanded.has(group) ? all : all.slice(0, PER_GROUP);
    return [{ group, items: shown, more: all.length - shown.length }];
  });
}

/** A navigable listbox row: a result, or a group's "Show all" option (qa #12: options only). */
export type Row =
  | Readonly<{ kind: "item"; key: string; group: Group; item: PaletteItem }>
  | Readonly<{ kind: "more"; key: string; group: Group; total: number }>;

export function rowsOf(groups: readonly GroupView[]): Row[] {
  return groups.flatMap((g) => [
    ...g.items.map((item): Row => ({ kind: "item", key: item.key, group: g.group, item })),
    ...(g.more > 0
      ? [
          {
            kind: "more",
            key: `more-${g.group}`,
            group: g.group,
            total: g.items.length + g.more,
          } as const,
        ]
      : []),
  ]);
}

/** Tab / Shift+Tab: first row of the next / previous group (wraps), per Palette.md. */
export function groupJump(rows: readonly Row[], active: number, backwards: boolean): number {
  const starts = rows.flatMap((row, i) => (i === 0 || rows[i - 1]?.group !== row.group ? [i] : []));
  if (starts.length === 0) return 0;
  const current = starts.filter((s) => s <= active).length - 1;
  const next = (current + (backwards ? -1 : 1) + starts.length) % starts.length;
  return starts[next] ?? 0;
}
