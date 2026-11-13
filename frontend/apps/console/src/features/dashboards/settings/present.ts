import type { ApiError } from "@/api";
import { formatShort, type OpState } from "@/ui";
import type { ActivityEvent, Share, Snapshot, WidgetDiagnostics } from "./api.ts";

/** ux Dashboards.md § Settings: the words each tab shows (no codes in the main text). */

const day = (iso: string) => formatShort(new Date(iso)).slice(0, 5);

export const visibilityWord = (v: Share["data_visibility"]) =>
  v === "with_data" ? "With data" : "Definition only";

/** `Expires 11-20` / `No expiry` / `Expired 11-12` / `Revoked`. */
export function shareStateText(s: Pick<Share, "state" | "expires_at">): string {
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

const activityWords: Readonly<Record<string, string>> = {
  saved: "Saved",
  restored: "Restored",
  published: "Published",
  archived: "Archived",
  unarchived: "Restored from the archive",
  share_created: "Created a share link",
  share_revoked: "Revoked a share link",
  snapshot_taken: "Took a snapshot",
  exported: "Exported",
};

/** `Saved v8 · Updated dashboard settings`; an unknown kind reads as words, never dropped. */
export function activityText(e: Pick<ActivityEvent, "kind" | "version" | "detail">): string {
  const word =
    activityWords[e.kind] ?? e.kind.replaceAll("_", " ").replace(/^\w/, (c) => c.toUpperCase());
  const version =
    e.version !== null && ["saved", "restored", "published"].includes(e.kind)
      ? ` v${e.version}`
      : "";
  return `${word}${version}${e.detail ? ` · ${e.detail}` : ""}`;
}

const statusRank: Readonly<Record<WidgetDiagnostics["status"], number>> = {
  failed: 0,
  degraded: 1,
  planned: 2,
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
  planned: { state: "neutral", word: "NOT RUN YET" },
  ok: { state: "nominal", word: "OK" },
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
  if (e.kind !== "conflict" || e.code !== "version_conflict") return null;
  const det: unknown = e.details;
  const get = (k: string): unknown =>
    det !== null && typeof det === "object" && k in det ? Reflect.get(det, k) : null;
  const v = get("current_version");
  const by = get("saved_by");
  const at = get("saved_at");
  const who =
    by !== null && typeof by === "object" && "name" in by && typeof by.name === "string"
      ? by.name
      : "Someone";
  const when = typeof at === "string" ? ` at ${formatShort(new Date(at)).slice(6)}` : "";
  return `${who} saved ${typeof v === "number" ? `v${v}` : "a newer version"}${when}. Reload to see it, then save again.`;
}

/** D3 409 in_use: the playlists' names, or null for any other error. */
export function usedByPlaylists(e: ApiError): readonly string[] | null {
  if (e.kind !== "conflict" || e.code !== "in_use") return null;
  const det: unknown = e.details;
  const used = det !== null && typeof det === "object" && "used_by" in det ? det.used_by : null;
  const lists =
    used !== null && typeof used === "object" && "playlists" in used ? used.playlists : null;
  if (!Array.isArray(lists)) return [];
  return lists.flatMap((p: unknown) =>
    p !== null && typeof p === "object" && "name" in p && typeof p.name === "string"
      ? [p.name]
      : [],
  );
}

/** The server's `/console/…` url as a router path (the router's base is `/console/`). */
export const routerPath = (url: string) => url.replace(/^\/console(?=\/)/, "");
