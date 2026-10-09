const relative = new Intl.RelativeTimeFormat("en", { numeric: "auto", style: "short" });

/** "2 hr. ago", "yesterday", "3 mo. ago"; empty when the time is unknown. */
export function ago(iso: string | null, now = Date.now()): string {
  if (iso === null) return "";
  const minutes = Math.round((Date.parse(iso) - now) / 60_000);
  if (Math.abs(minutes) < 1) return "just now";
  if (Math.abs(minutes) < 60) return relative.format(minutes, "minute");
  const hours = Math.round(minutes / 60);
  if (Math.abs(hours) < 24) return relative.format(hours, "hour");
  const days = Math.round(hours / 24);
  if (Math.abs(days) < 45) return relative.format(days, "day");
  const months = Math.round(days / 30);
  return Math.abs(months) < 18
    ? relative.format(months, "month")
    : relative.format(Math.round(days / 365), "year");
}
