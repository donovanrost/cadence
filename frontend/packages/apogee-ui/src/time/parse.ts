/**
 * Typed times for ApTimePicker / ApTimeRange. Accepts:
 *   now · now+2h · now-15m · T+38m · T−90s (U+2212 too) · 2026-10-24 06:00[:SS][Z] · 2026-10-24T06:00Z
 *   · 2026-10-24 (midnight UTC)
 * All absolute times are UTC. Returns epoch ms, or null when the text can't be read.
 */
const UNIT_MS = { h: 3_600_000, m: 60_000, s: 1_000, d: 86_400_000 } as const;

const isUnit = (u: string): u is keyof typeof UNIT_MS => Object.hasOwn(UNIT_MS, u);

export function parseTime(text: string, now: number): number | null {
  const q = text.trim().toLowerCase().replaceAll("−", "-");
  if (q === "") return null;
  if (q === "now") return now;
  const relative = /^(?:now|t)\s*([+-])\s*(\d+(?:\.\d+)?)\s*([dhms])$/.exec(q);
  if (relative) {
    const [, sign, amount, unit] = relative;
    if (!sign || !amount || !unit || !isUnit(unit)) return null;
    const ms = Number(amount) * UNIT_MS[unit];
    return Math.round(now + (sign === "+" ? ms : -ms));
  }
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(q);
  if (dateOnly) {
    const [y, mo, d] = dateOnly.slice(1).map(Number);
    if (y === undefined || mo === undefined || d === undefined) return null;
    const at = Date.UTC(y, mo - 1, d);
    const check = new Date(at);
    return check.getUTCMonth() === mo - 1 && check.getUTCDate() === d ? at : null;
  }
  const absolute = /^(\d{4})-(\d{2})-(\d{2})[ t](\d{2}):(\d{2})(?::(\d{2}))?z?$/.exec(q);
  if (absolute) {
    const [y, mo, d, h, mi, s] = absolute.slice(1).map((part) => Number(part ?? 0));
    if (
      y === undefined ||
      mo === undefined ||
      d === undefined ||
      h === undefined ||
      mi === undefined
    )
      return null;
    const at = Date.UTC(y, mo - 1, d, h, mi, s ?? 0);
    const check = new Date(at);
    // Reject rollovers such as 2026-02-31 or 25:00.
    if (check.getUTCMonth() !== mo - 1 || check.getUTCDate() !== d || check.getUTCHours() !== h)
      return null;
    return at;
  }
  return null;
}
