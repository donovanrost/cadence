import { count, object } from "../../shared/readers.ts";

export const readUsageSummary = object({ active_count: count, saved_count: count });
export type UsageSummary = ReturnType<typeof readUsageSummary>;

export function usageSummaryText(usage: UsageSummary): string {
  const labels: string[] = [];
  if (usage.active_count) labels.push(`Active on ${usage.active_count} spacecraft`);
  if (usage.saved_count) labels.push(`Saved configuration on ${usage.saved_count} spacecraft`);
  return labels.length ? labels.join(" · ") : "No active or saved spacecraft configurations";
}
