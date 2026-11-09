import { plural } from "@/ui";
import type { PlanDetail } from "./api.ts";

/** What the count needs of a plan and of a passes read (contacts' `Passes` fits). */
type BookedPlan = Pick<PlanDetail, "id" | "passes">;
type PassesRead = Readonly<{
  from: string;
  to: string;
  truncated: boolean;
  passes: readonly Readonly<{
    plan: Readonly<{ id: string }> | null;
    source: Readonly<{ provider_name: string | null }>;
  }>[];
}>;

/** K1/K2 interrupted execution: the callout and whether anything is left to continue. */
export type BookingStopped = Readonly<{
  text: string;
  tone: "info" | "stale";
  /** Requests not yet sent; null when the passes read can't tell. 0 = nothing to continue. */
  left: number | null;
}>;

/**
 * U20 + ux 1a906155 (ScheduleFlow K1 table). Counts only when the passes read covers every
 * request the plan sends (not truncated, every unlocked pass inside its window); otherwise it says
 * what is known. Nothing left to send reads as waiting on the provider, never "0 didn't".
 */
export function bookingStopped(plan: BookedPlan, read: PassesRead | null): BookingStopped {
  const unknown = {
    text: "Booking stopped before every request went out.",
    tone: "stale",
    left: null,
  } as const;
  const wanted = plan.passes.filter((p) => !p.locked);
  if (!read || read.truncated || wanted.length === 0) return unknown;
  const from = Date.parse(read.from);
  const to = Date.parse(read.to);
  const covered = wanted.every((p) => {
    const t = Date.parse(p.starts_at);
    return t >= from && t < to;
  });
  if (!covered) return unknown;
  const sent = read.passes.filter((p) => p.plan?.id === plan.id);
  const left = Math.max(wanted.length - sent.length, 0);
  if (left > 0)
    return {
      text: `Booking stopped. ${plural(sent.length, "request")} went out; ${left} didn't.`,
      tone: "stale",
      left,
    };
  const providers = [...new Set(sent.map((p) => p.source.provider_name).filter((n) => n !== null))];
  const who = providers.length === 1 ? (providers[0] ?? "the provider") : "the providers";
  const what = sent.length === 1 ? "The request went out" : `All ${sent.length} requests went out`;
  return { text: `${what} · waiting for ${who} to confirm.`, tone: "info", left: 0 };
}

/** The passes-read window covering every request the plan sends, or null when it sends none. */
export function bookingWindow(plan: BookedPlan): { from: string; to: string } | null {
  const wanted = plan.passes.filter((p) => !p.locked);
  if (wanted.length === 0) return null;
  const starts = wanted.map((p) => Date.parse(p.starts_at));
  return {
    from: new Date(Math.min(...starts)).toISOString(),
    to: new Date(Math.max(...starts) + 1).toISOString(),
  };
}
