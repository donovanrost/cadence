/** Month grid math for the picker calendar. Weeks start on Monday; always 6 rows × 7 days. */
export type CalendarDay = Readonly<{
  /** `2026-10-23` */
  key: string;
  year: number;
  /** 0-based month */
  month: number;
  day: number;
  inMonth: boolean;
}>;

const pad = (n: number) => String(n).padStart(2, "0");
export const dayKey = (year: number, month: number, day: number) =>
  `${year}-${pad(month + 1)}-${pad(day)}`;

export function monthGrid(year: number, month: number): CalendarDay[] {
  const first = Date.UTC(year, month, 1);
  const lead = (new Date(first).getUTCDay() + 6) % 7;
  const start = Date.UTC(year, month, 1 - lead);
  return Array.from({ length: 42 }, (_, i) => {
    const date = new Date(start + i * 86_400_000);
    const y = date.getUTCFullYear();
    const m = date.getUTCMonth();
    const d = date.getUTCDate();
    return { key: dayKey(y, m, d), year: y, month: m, day: d, inMonth: m === month };
  });
}

/** Same UTC time of day on another date. */
export function withDate(at: number, year: number, month: number, day: number): number {
  const t = new Date(at);
  return Date.UTC(year, month, day, t.getUTCHours(), t.getUTCMinutes(), t.getUTCSeconds());
}

export const MONTHS = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
] as const;
