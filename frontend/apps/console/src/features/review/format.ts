import { isKeyOf } from "@/api";
import type { OpState } from "@/ui";
import type {
  Owner,
  Outcome,
  ReviewDay,
  ReviewStation,
  ReviewSummary,
  StationLine,
} from "./api.ts";
import { owners } from "./api.ts";

/** 0.985 → "98.5%"; null → "—". */
export function percent(ratio: number | null): string {
  if (ratio === null) return "—";
  const p = Math.round(ratio * 1000) / 10;
  return `${Number.isInteger(p) ? p.toFixed(0) : p.toFixed(1)}%`;
}

/** h1: the realized share and its verdict against the mission's target (ST1). */
export function headline(s: ReviewSummary): { text: string; tone: "nominal" | "caution" | "off" } {
  if (s.realized_ratio === null) return { text: "No passes to review", tone: "off" };
  return {
    text: `${percent(s.realized_ratio)} realized`,
    tone: s.realized_ratio >= s.target ? "nominal" : "caution",
  };
}

/** Why the % is provisional, in words (never a final % while a report is missing). */
export function provisionalText(s: ReviewSummary): string | null {
  if (!s.provisional) return null;
  // provider and cursor_healthy can be null (api drift sweep 11-13): unknown isn't broken.
  const who = (f: ReviewSummary["freshness"][number]) => f.provider?.name ?? "a provider";
  const waiting = s.freshness.filter((f) => f.pending_reports > 0).map(who);
  const broken = s.freshness.filter((f) => f.cursor_healthy === false).map(who);
  const parts = [
    s.pending_count > 0
      ? `${s.pending_count} ${s.pending_count === 1 ? "pass awaits" : "passes await"} a provider report${waiting.length > 0 ? ` (${waiting.join(", ")})` : ""}`
      : null,
    broken.length > 0 ? `${broken.join(", ")} isn't sending results right now` : null,
  ].filter(Boolean);
  return `Provisional: ${parts.join("; ") || "a provider report is missing"}.`;
}

/** h1 meta: REPORTS IN FROM ALL 3 PROVIDERS · LAST AT 01:12Z · 0 PENDING */
export function freshnessMeta(s: ReviewSummary): string {
  const n = s.freshness.length;
  if (n === 0) return "No provider reports in this span";
  const last = s.freshness
    .map((f) => f.last_report_at)
    .filter((t): t is string => t !== null)
    .sort()
    .at(-1);
  const reported = s.freshness.filter((f) => f.pending_reports === 0 && f.cursor_healthy).length;
  const who =
    reported === n
      ? `Reports in from ${n === 1 ? "the provider" : `all ${n} providers`}`
      : `Reports in from ${reported} of ${n} providers`;
  return [
    who,
    last ? `last at ${last.slice(11, 16)}Z` : "none yet",
    `${s.pending_count} pending`,
  ].join(" · ");
}

export const ownerWord: Readonly<Record<Owner, string>> = {
  provider: "Provider",
  us: "Us",
  weather: "Weather",
  unknown: "Unknown",
};

/** Strip caption: "5 provider · 3 on our side" (zeros left out; ux §7 #5). */
export function ownerCaption(counts: Readonly<Record<Owner, number>>): string | undefined {
  const parts = owners
    .filter((o) => counts[o] > 0)
    .map((o) => `${counts[o]} ${o === "us" ? "on our side" : ownerWord[o].toLowerCase()}`);
  return parts.length > 0 ? parts.join(" · ") : undefined;
}

/** Causes the console words (rule A); a provider's own cause reads as its key in words. */
const causeWords = {
  not_ingested: "Delivered, not ingested",
  provider_canceled: "Provider canceled",
  station_outage: "Station outage",
  no_aos: "No AOS",
  short_pass: "Short pass",
} as const;
export function causeText(cause: string | null): string {
  if (cause === null) return "Not reported";
  if (isKeyOf(causeWords, cause)) return causeWords[cause];
  const words = cause.replace(/_/g, " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
}

export function outcomeTag(o: Outcome): { state: OpState; label: string } {
  switch (o) {
    case "realized":
      return { state: "nominal", label: "Realized" };
    case "partial":
      return { state: "caution", label: "Partial" };
    case "missed":
      return { state: "crit", label: "Missed" };
    case "failed":
      return { state: "crit", label: "Failed" };
    case "canceled":
      return { state: "off", label: "Canceled" };
    case "pending_report":
      return { state: "stale", label: "Awaiting report" };
  }
}

/** Confirmed code, else name, else the provider's ref (U25: never a suggestion). */
export function stationText(s: ReviewStation): string {
  return s.code ?? s.name ?? s.ref ?? "Unknown station";
}

/** realized / (planned − canceled), null when nothing counts. */
export function stationRatio(l: StationLine): number | null {
  const base = l.planned - l.canceled;
  return base > 0 ? l.realized / base : null;
}

/** R1 order: realization ascending, stations with nothing to count last. */
export function byRealization(lines: readonly StationLine[]): readonly StationLine[] {
  return [...lines].sort((a, b) => (stationRatio(a) ?? 2) - (stationRatio(b) ?? 2));
}

export function minutes(seconds: number): string {
  return `${Math.round(seconds / 60).toLocaleString("en-US")} min`;
}

/** 480 → "8m 00s" */
export function duration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  return `${m}m ${String(Math.round(seconds % 60)).padStart(2, "0")}s`;
}

export function bytes(n: number | null): string {
  if (n === null) return "—";
  if (n < 1000) return `${n} B`;
  const units = ["kB", "MB", "GB", "TB"];
  let v = n / 1000;
  let i = 0;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  return `${v.toFixed(v < 10 ? 1 : 0)} ${units[i]}`;
}

export const dayRatio = (d: ReviewDay): number | null => d.realized_ratio ?? d.ratio ?? null;

/** The 30 UTC days ending at `day`; a day the read didn't return had no passes (null). */
export function fillDays(
  days: readonly ReviewDay[],
  day: string,
  n = 30,
): readonly { day: string; entry: ReviewDay | null }[] {
  const end = Date.parse(`${day}T00:00:00Z`);
  const byDay = new Map(days.map((d) => [d.day, d]));
  return Array.from({ length: n }, (_, i) => {
    const key = new Date(end - (n - 1 - i) * 86_400_000).toISOString().slice(0, 10);
    return { day: key, entry: byDay.get(key) ?? null };
  });
}
