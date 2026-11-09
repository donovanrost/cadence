/** Reads a typed number against catalog bounds. Text stays the source of truth (exact digits). */
export type NumberReading =
  | Readonly<{ kind: "empty" }>
  | Readonly<{ kind: "invalid" }>
  | Readonly<{ kind: "out_of_range"; value: number }>
  | Readonly<{ kind: "ok"; value: number }>;

export function readNumber(
  text: string,
  bounds: Readonly<{
    min?: number | undefined;
    max?: number | undefined;
    integer?: boolean | undefined;
  }>,
): NumberReading {
  const t = text.trim().replaceAll("−", "-");
  if (t === "") return { kind: "empty" };
  if (!/^-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?$/i.test(t)) return { kind: "invalid" };
  const value = Number(t);
  if (!Number.isFinite(value) || (bounds.integer && !Number.isInteger(value)))
    return { kind: "invalid" };
  if (
    (bounds.min !== undefined && value < bounds.min) ||
    (bounds.max !== undefined && value > bounds.max)
  )
    return { kind: "out_of_range", value };
  return { kind: "ok", value };
}
