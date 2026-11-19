import { actor, actorName, decoders, detailsOf, isError, orNull, type ApiError } from "@/api";
import { formatShort, type OpState } from "@/ui";
import type { ActivityEvent, ActivityKind, Share, Snapshot, WidgetDiagnostics } from "./api.ts";

/** ux Dashboards.md § Settings: the words each tab shows (no codes in the main text). */

const day = (iso: string) => formatShort(new Date(iso)).slice(0, 5);

export function visibilityWord(v: Share["data_visibility"]): string {
  switch (v) {
    case "with_data":
      return "With data";
    case "definition_only":
      return "Definition only";
    case "unrecognized":
      return "Not known";
  }
}

/** `Expires 11-20` / `No expiry` / `Expired 11-12` / `Revoked`. */
export function shareStateText(s: Pick<Share, "state" | "expires_at">): string {
  if (s.state === "unrecognized") return "Not known";
  if (s.state === "revoked") return "Revoked";
  if (s.state === "expired") return s.expires_at ? `Expired ${day(s.expires_at)}` : "Expired";
  return s.expires_at ? `Expires ${day(s.expires_at)}` : "No expiry";
}

/** `11-12 21:00Z–23:00Z` (the snapshot's frozen window), or `Current data` for an old unfrozen one. */
export function snapshotWindow(s: Pick<Snapshot, "window">): string {
  if (!s.window) return "Current data";
  const from = formatShort(new Date(s.window.from));
  const to = formatShort(new Date(s.window.to));
  return from.slice(0, 5) === to.slice(0, 5) ? `${from}–${to.slice(6)}` : `${from}–${to}`;
}

/** `Mira K. · 11-12 23:02Z` (who and when, for share and snapshot rows). */
export const byLine = (who: { name: string | null } | null, at: string) =>
  `${who?.name ?? "Not recorded"} · ${formatShort(new Date(at))}`;

const activityWords: Readonly<Record<ActivityKind | "unrecognized", string>> = {
  saved: "Saved",
  restored: "Restored",
  published: "Published",
  archived: "Archived",
  unarchived: "Restored from the archive",
  share_created: "Created a share link",
  share_revoked: "Revoked a share link",
  snapshot_taken: "Took a snapshot",
  exported: "Exported",
  unrecognized: "Changed it",
};

/** `Saved v8 · Updated dashboard settings`; an unknown kind reads as words, never dropped. */
export function activityText(e: Pick<ActivityEvent, "kind" | "version" | "detail">): string {
  const word = activityWords[e.kind];
  const version =
    e.version !== null && ["saved", "restored", "published"].includes(e.kind)
      ? ` v${e.version}`
      : "";
  return `${word}${version}${e.detail ? ` · ${e.detail}` : ""}`;
}

const statusRank: Readonly<Record<WidgetDiagnostics["status"], number>> = {
  failed: 0,
  unrecognized: 1,
  degraded: 1,
  not_run: 2,
  ok: 3,
};

/** ux: one row per widget, worst first. */
export const worstFirst = (rows: readonly WidgetDiagnostics[]) =>
  [...rows].sort((a, b) => statusRank[a.status] - statusRank[b.status]);

export const statusMark: Readonly<
  Record<WidgetDiagnostics["status"], { state: OpState; word: string }>
> = {
  failed: { state: "crit", word: "FAILED" },
  degraded: { state: "caution", word: "DEGRADED" },
  not_run: { state: "neutral", word: "NOT RUN YET" },
  ok: { state: "nominal", word: "OK" },
  unrecognized: { state: "stale", word: "NOT KNOWN" },
};

/** `Fresh` / `From cache` (asked of api as `cache: fresh | cached`); mixed shows both; unknown null. */
export function cacheText(w: WidgetDiagnostics): string | null {
  const words = new Set(
    w.sources.flatMap((s) =>
      s.cache === "cached" ? ["From cache"] : s.cache === "fresh" ? ["Fresh"] : [],
    ),
  );
  return words.size > 0 ? [...words].join(" · ") : null;
}

/** The operator actions the server wrote, as sentences (ux), deduplicated. */
export const actionText = (w: WidgetDiagnostics) => [
  ...new Set(w.sources.map((s) => s.operator_action).filter((a): a is string => !!a)),
];

/** Warnings in the server's words (asked of api); a bare code reads as words, never dropped. */
export const warningText = (w: Readonly<{ code: string; message: string | null }>) =>
  w.message ?? w.code.replaceAll("_", " ").replace(/^\w/, (c) => c.toUpperCase());

/** Tags typed as text: comma-separated, trimmed, unique, non-empty. */
export function parseTags(
  text: string,
  limits: Readonly<{ tags: number; tag: number }>,
): Readonly<{ ok: true; tags: string[] } | { ok: false; message: string }> {
  const tags = [
    ...new Set(
      text
        .split(",")
        .map((t) => t.trim())
        .filter((t) => t !== ""),
    ),
  ];
  if (tags.length > limits.tags) return { ok: false, message: `At most ${limits.tags} tags.` };
  const long = tags.find((t) => new TextEncoder().encode(t).length > limits.tag);
  if (long) return { ok: false, message: `“${long}” is longer than ${limits.tag} characters.` };
  return { ok: true, tags };
}

/** D15 409 version_conflict: `Mira K. saved v8 at 22:41Z. Reload to see it, then save again.` */
export function conflictText(e: ApiError): string | null {
  if (!isError(e, "version_conflict")) return null;
  const det = detailsOf(
    e,
    decoders.object({
      current_version: orNull(decoders.integer),
      saved_by: orNull(actor),
      saved_at: orNull(decoders.timestamp),
    }),
  );
  const who = actorName(det?.saved_by, "Someone");
  const when = det?.saved_at ? ` at ${formatShort(new Date(det.saved_at)).slice(6)}` : "";
  const v = det?.current_version;
  return `${who} saved ${v != null ? `v${v}` : "a newer version"}${when}. Reload to see it, then save again.`;
}

/** D3 409 dashboard_in_use (api-ops 3e2a6632): the playlists' names, or null for any other error. */
export function usedByPlaylists(e: ApiError): readonly string[] | null {
  if (!isError(e, "dashboard_in_use")) return null;
  const det = detailsOf(
    e,
    decoders.object({
      used_by: decoders.object({
        playlists: decoders.array(decoders.object({ name: decoders.string }), 500),
      }),
    }),
  );
  return det ? det.used_by.playlists.map((p) => p.name) : [];
}

/** The server's `/console/…` url as a router path (the router's base is `/console/`). */
export const routerPath = (url: string) => url.replace(/^\/console(?=\/)/, "");

const allTabs = ["general", "sharing", "activity", "diagnostics"] as const;
export type SettingsTab = (typeof allTabs)[number];
/**
 * ux § Settings: authors get all four tabs; everyone else reads Activity and Diagnostics (D17/D18
 * are operator reads), with General and Sharing hidden, not disabled.
 */
export const settingsTabs = (author: boolean): readonly SettingsTab[] =>
  author ? allTabs : ["activity", "diagnostics"];
