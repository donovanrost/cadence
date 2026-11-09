import { formatCount } from "@/ui";

/** Engineering values: integers with grouping, decimals to 3 significant places, text as sent. */
export function formatValue(value: number | string | boolean | null): string | null {
  if (value === null) return null;
  if (typeof value !== "number") return String(value);
  if (Number.isInteger(value)) return formatCount(value);
  // Number(…) drops the trailing zeros toPrecision pads with (−0.400 → −0.4).
  const text = Math.abs(value) >= 100 ? value.toFixed(1) : String(Number(value.toPrecision(3)));
  return text.replace("-", "−");
}

const decimalsOf = (text: string) => text.split(".")[1]?.length ?? 0;

/**
 * A limit shown beside a value uses at least the value's precision (`24.0` beside `23.1`), so
 * both read as the same kind of number (ux review 11).
 */
export function formatLimitLike(
  limit: number | null,
  value: number | string | boolean | null,
): string | null {
  const plain = formatValue(limit);
  const reference = typeof value === "number" ? formatValue(value) : null;
  if (limit === null || plain === null || reference === null) return plain;
  const decimals = decimalsOf(reference);
  if (decimals <= decimalsOf(plain)) return plain;
  const [int = "0", frac = ""] = Math.abs(limit).toFixed(decimals).split(".");
  return `${limit < 0 ? "−" : ""}${formatCount(Number(int))}.${frac}`;
}

/** `23.1 V`; the value alone when the unit is unknown (null) or the value is missing. */
export function withUnit(text: string | null, unit: string | null): string | null {
  return text === null || unit === null || unit === "" ? text : `${text} ${unit}`;
}
