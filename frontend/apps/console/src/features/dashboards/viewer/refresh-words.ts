import { refreshChoices, type RefreshChoice } from "./useDashboardView.ts";

/** A refresh interval in words (ux Dashboards.md §Phone): `every 30 s`, `every 1 min`, `off`. */
export function refreshWords(choice: RefreshChoice): string {
  const ms = refreshChoices.find((c) => c.value === choice)?.ms ?? null;
  if (ms === null) return "off";
  return ms < 60_000 ? `every ${ms / 1000} s` : `every ${ms / 60_000} min`;
}
