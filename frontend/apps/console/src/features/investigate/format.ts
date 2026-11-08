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
