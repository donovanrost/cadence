import type { GroupRow, GroupState } from "../groups/api.ts";

/**
 * Commands (IA rail 04): requests grouped by state. `?awaiting=me` is the GO-poll entry from Now
 * and Mobile; it filters on the server's `awaiting_me`, never on a local guess.
 */
export const COMMAND_TABS = ["awaiting", "pending", "queued", "closed"] as const;
export type CommandTab = (typeof COMMAND_TABS)[number];

export const TAB_LABELS: Readonly<Record<CommandTab, string>> = {
  awaiting: "Awaiting your GO",
  pending: "Waiting for a GO",
  queued: "Released",
  closed: "Closed",
};

const CLOSED: readonly GroupState[] = ["rejected", "sent_back", "aborted"];

export function inTab(row: GroupRow, tab: CommandTab): boolean {
  switch (tab) {
    case "awaiting":
      return row.awaiting_me;
    case "pending":
      return row.state === "approval_pending";
    case "queued":
      return row.state === "queued";
    case "closed":
      return CLOSED.includes(row.state);
  }
}

/** Newest first, except the GO queue: oldest first, so nobody waits longest. */
export function tabRows(rows: readonly GroupRow[], tab: CommandTab): GroupRow[] {
  const sign = tab === "awaiting" ? 1 : -1;
  return rows
    .filter((r) => inTab(r, tab))
    .sort((a, b) => sign * (Date.parse(a.requested_at) - Date.parse(b.requested_at)));
}

export function tabCounts(rows: readonly GroupRow[]): Record<CommandTab, number> {
  return {
    awaiting: rows.filter((r) => inTab(r, "awaiting")).length,
    pending: rows.filter((r) => inTab(r, "pending")).length,
    queued: rows.filter((r) => inTab(r, "queued")).length,
    closed: rows.filter((r) => inTab(r, "closed")).length,
  };
}

/** `?awaiting=me` maps to the first tab; `?tab=` picks the others. */
export function tabFromQuery(query: Readonly<Record<string, unknown>>): CommandTab {
  if (query.awaiting === "me") return "awaiting";
  const t = query.tab;
  return typeof t === "string" &&
    (COMMAND_TABS as readonly string[]).includes(t) &&
    t !== "awaiting"
    ? (t as CommandTab)
    : "pending";
}
