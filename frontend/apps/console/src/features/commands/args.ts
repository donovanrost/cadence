import type { CommandArgument } from "./api.ts";

/**
 * Catalog-driven argument forms (CommandFlow R03: the catalog writes the form). Values travel as
 * JSON text so 64-bit integers stay exact; integer ranges compare with BigInt.
 */

export type ArgInput =
  | Readonly<{ kind: "fixed"; text: string }>
  | Readonly<{ kind: "choice"; options: readonly { value: string; label: string }[] }>
  | Readonly<{ kind: "boolean" }>
  | Readonly<{ kind: "number"; integer: boolean; min?: number; max?: number }>
  | Readonly<{ kind: "text"; hex: boolean }>
  /** An argument type this console doesn't know: read-only, and its command can't be staged. */
  | Readonly<{ kind: "unsupported" }>;

export const UNSUPPORTED_ARG = "This argument type isn't supported here.";

/** JSON text → display text: strings unquoted, everything else as written. */
function display(json: string): string {
  try {
    const value: unknown = JSON.parse(json);
    return typeof value === "string" ? value : json;
  } catch {
    return json;
  }
}

/** A bound as a JS number only when it's exactly representable (the range bar is visual). */
function safeNumber(json: string | null | undefined): number | undefined {
  if (json === null || json === undefined) return undefined;
  const n = Number(json);
  return Number.isFinite(n) && (!/^-?\d+$/.test(json) || Number.isSafeInteger(n)) ? n : undefined;
}

export function argInput(arg: CommandArgument): ArgInput {
  if (arg.fixed_value_json !== null) return { kind: "fixed", text: display(arg.fixed_value_json) };
  switch (arg.type) {
    case "enumerated":
      return {
        kind: "choice",
        options: arg.choices.map((c) => ({ value: c.value_json, label: c.label })),
      };
    case "boolean":
      return { kind: "boolean" };
    case "integer":
    case "float": {
      const min = safeNumber(arg.valid_range?.minimum_json);
      const max = safeNumber(arg.valid_range?.maximum_json);
      return {
        kind: "number",
        integer: arg.type === "integer",
        ...(min === undefined ? {} : { min }),
        ...(max === undefined ? {} : { max }),
      };
    }
    case "string":
      return { kind: "text", hex: false };
    case "binary":
      return { kind: "text", hex: true };
    case "unrecognized":
      return { kind: "unsupported" };
  }
}

/** Form text for a JSON value: enums keep their JSON (choice keys), strings unwrap, numbers stay exact. */
export function textFromJson(arg: CommandArgument, json: string): string {
  return arg.type === "enumerated" ? json : display(json);
}

/** The form's starting text: fixed value, else the catalog default, else empty. */
export function initialText(arg: CommandArgument): string {
  const json = arg.fixed_value_json ?? arg.default_value_json;
  return json === null ? "" : textFromJson(arg, json);
}

export type ArgCheck =
  | { ok: true; json: string; hazardous: boolean }
  | { ok: false; reason: string };

function inRange(arg: CommandArgument, text: string): string | null {
  const r = arg.valid_range;
  if (!r) return null;
  const big = arg.type === "integer";
  const cmp = (a: string, b: string) =>
    big
      ? BigInt(a) < BigInt(b)
        ? -1
        : BigInt(a) > BigInt(b)
          ? 1
          : 0
      : Math.sign(Number(a) - Number(b));
  if (r.minimum_json !== null && cmp(text, r.minimum_json) < 0)
    return `At least ${r.minimum_json}${arg.unit ? ` ${arg.unit}` : ""}.`;
  if (r.maximum_json !== null && cmp(text, r.maximum_json) > 0)
    return `At most ${r.maximum_json}${arg.unit ? ` ${arg.unit}` : ""}.`;
  return null;
}

/** Validates form text into the JSON value to stage; invalid values can't be staged. */
export function checkArg(arg: CommandArgument, raw: string): ArgCheck {
  if (arg.fixed_value_json !== null)
    return { ok: true, json: arg.fixed_value_json, hazardous: false };
  const text = raw.trim();
  if (arg.type === "unrecognized") return { ok: false, reason: UNSUPPORTED_ARG };
  if (text === "")
    return arg.required
      ? { ok: false, reason: "Required." }
      : { ok: true, json: "null", hazardous: false };
  let json: string;
  switch (arg.type) {
    case "integer":
      if (!/^-?\d+$/.test(text)) return { ok: false, reason: "Enter a whole number." };
      json = text;
      break;
    case "float":
      if (!Number.isFinite(Number(text)) || !/^-?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$/.test(text))
        return { ok: false, reason: "Enter a number." };
      json = text;
      break;
    case "boolean":
      if (text !== "true" && text !== "false")
        return { ok: false, reason: "Choose true or false." };
      json = text;
      break;
    case "enumerated":
      if (!arg.choices.some((c) => c.value_json === text))
        return { ok: false, reason: "Choose one of the listed values." };
      json = text;
      break;
    case "string":
      json = JSON.stringify(text);
      break;
    case "binary":
      if (!/^([0-9a-fA-F]{2})+$/.test(text))
        return { ok: false, reason: "Enter hex bytes (pairs of 0-9, A-F)." };
      json = JSON.stringify(text.toUpperCase());
      break;
  }
  const range = arg.type === "integer" || arg.type === "float" ? inRange(arg, text) : null;
  if (range) return { ok: false, reason: range };
  return { ok: true, json, hazardous: arg.hazardous_values_json.includes(json) };
}
