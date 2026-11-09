import type { OpState } from "@/ui";
import type { Density, EventKind, EventSeverity, MissionEvent } from "./api.ts";

/** Timeline (OpsLists §Timeline): pure helpers. */

export function severityState(severity: EventSeverity): OpState {
  switch (severity) {
    case "critical":
      return "crit";
    case "caution":
      return "caution";
    case "nominal":
      return "nominal";
    case "info":
      return "neutral";
  }
}

export const KIND_WORDS: Readonly<Record<EventKind, string>> = {
  limit: "Limits",
  flight_event: "Flight events",
  contact: "Contacts",
  command: "Commands",
  config: "Configuration",
  operator: "Operators",
};

export type HourGroup = Readonly<{ hour: string; events: readonly MissionEvent[] }>;

/** Newest first, grouped under UTC hour headers ("2026-11-08 02:00Z"). */
export function byHour(events: readonly MissionEvent[]): HourGroup[] {
  const sorted = [...events].sort((a, b) => Date.parse(b.at) - Date.parse(a.at));
  const groups: { hour: string; events: MissionEvent[] }[] = [];
  for (const event of sorted) {
    const hour = `${event.at.slice(0, 10)} ${event.at.slice(11, 13)}:00Z`;
    const last = groups.at(-1);
    if (last && last.hour === hour) last.events.push(event);
    else groups.push({ hour, events: [event] });
  }
  return groups;
}

/** Bucket size giving at most ~96 bars over the window (15 min over 24 h). */
export function densityBucketS(windowMs: number): number {
  const steps = [60, 300, 900, 1800, 3600];
  return steps.find((s) => windowMs / (s * 1000) <= 96) ?? 3600;
}

export type Bar = Readonly<{
  t: number;
  /** Stacked from the bottom: critical, caution, nominal, info (heights as fractions of max). */
  stack: readonly { severity: EventSeverity; from: number; to: number }[];
  total: number;
}>;

export function densityBars(density: Density): { bars: Bar[]; max: number } {
  const order = ["critical", "caution", "nominal", "info"] as const;
  const totals = density.buckets.map((b) => b.critical + b.caution + b.nominal + b.info);
  const max = Math.max(1, ...totals);
  const bars = density.buckets.map((b, i) => {
    let at = 0;
    const stack = order.map((severity) => {
      const from = at;
      at += b[severity] / max;
      return { severity, from, to: at };
    });
    return { t: Date.parse(b.t), stack: stack.filter((s) => s.to > s.from), total: totals[i] ?? 0 };
  });
  return { bars, max };
}
