import { MAX_TARGETS } from "./bounds.ts";
import { decoders as d, isKnown, type Decoded } from "@/api/index.ts";

/**
 * U68 R1 (api d33d48f11): where the server's value differs from what was entered, per command.
 * The server fills a blank argument with the catalog default or fixed value, and a float encoded
 * as 32-bit radiates the nearest single-precision value (`sent_value_json`). Rows only where they
 * differ; `spacecraft_ids: null` = every validated target of the command.
 */
const sources = ["entered", "default", "fixed", "catalog"] as const;
export const resolvedArgumentReader = d.object({
  name: d.string,
  entered_value_json: d.nullable(d.string),
  resolved_value_json: d.string,
  sent_value_json: d.nullable(d.string),
  unit: d.nullable(d.string),
  source: d.knownText(sources),
  spacecraft_ids: d.nullable(d.array(d.token, MAX_TARGETS)),
});
export type ResolvedArgument = Decoded<typeof resolvedArgumentReader>;
/** Optional until the server ships R1 everywhere. */
export const resolvedArgumentsReader = d.optional(d.array(resolvedArgumentReader, 1_000));

/** A value as an operator reads it: strings unquoted, numbers and the rest as sent (64-bit safe). */
export function shownValue(raw: string): string {
  if (!raw.startsWith('"')) return raw;
  try {
    const v: unknown = JSON.parse(raw);
    return typeof v === "string" ? v : raw;
  } catch {
    return raw;
  }
}
const withUnit = (raw: string, unit: string | null) =>
  unit ? `${shownValue(raw)} ${unit}` : shownValue(raw);

/** How a blank argument was filled; an unknown source keeps the server's word. */
function filledWord(source: ResolvedArgument["source"]): string {
  if (!isKnown(source)) return `${source.unrecognized} value used`;
  if (source === "fixed") return "fixed value used";
  if (source === "catalog") return "catalog value used";
  return "default used";
}

/** What changed, without the target names: `TIMEOUT: default used, 30 s` / `V: sent as … (entered 2.5)`. */
export function resolvedWords(r: ResolvedArgument): string {
  const sent = r.sent_value_json === null ? null : withUnit(r.sent_value_json, r.unit);
  if (r.entered_value_json === null) {
    const filled = `${r.name}: ${filledWord(r.source)}, ${withUnit(r.resolved_value_json, r.unit)}`;
    return sent ? `${filled}; sent as ${sent}` : filled;
  }
  return `${r.name}: sent as ${sent ?? withUnit(r.resolved_value_json, r.unit)} (entered ${shownValue(r.entered_value_json)})`;
}

const PLAIN = /^-?\d+(?:\.(\d+))?$/;
/**
 * ux U68 (a150a527a): 'sent as' shows only when the sent value, rounded to the reference's decimal
 * places, differs from it. 0.1 sent as 0.100000001 stays silent (single-precision noise would
 * teach approvers to skip these lines); 16777217 sent as 16777216 shows. Non-plain numbers and
 * other values compare as text.
 */
export function sentDiffers(reference: string, sent: string): boolean {
  const m = PLAIN.exec(reference);
  if (!m || !PLAIN.test(sent)) return reference !== sent;
  const places = m[1]?.length ?? 0;
  return Number(sent).toFixed(places) !== Number(reference).toFixed(places);
}

/** The rows worth a line: noise-only sent values dropped, and rows left with nothing to say. */
export function shownRows(rows: readonly ResolvedArgument[] | undefined): ResolvedArgument[] {
  return (rows ?? []).flatMap((r) => {
    const reference = r.entered_value_json ?? r.resolved_value_json;
    const sent =
      r.sent_value_json !== null && sentDiffers(reference, r.sent_value_json)
        ? r.sent_value_json
        : null;
    if (r.entered_value_json !== null && sent === null) return [];
    return [{ ...r, sent_value_json: sent }];
  });
}

/** Names for a target list: up to 3, then `and N more`. */
function targetsText(ids: readonly string[], nameOf: (id: string) => string): string {
  const shown = ids.slice(0, 3).map(nameOf).join(", ");
  return ids.length > 3 ? `${shown} and ${ids.length - 3} more` : shown;
}

/** One line per differing argument (ux U68); a row for some targets names them first. */
export function resolvedLines(
  rows: readonly ResolvedArgument[] | undefined,
  nameOf: (id: string) => string,
): string[] {
  return shownRows(rows).map((r) =>
    r.spacecraft_ids === null
      ? resolvedWords(r)
      : `${targetsText(r.spacecraft_ids, nameOf)} · ${resolvedWords(r)}`,
  );
}

/**
 * The own-values cell (ux U68): the value sent with `entered 2.5` under it; a default cell reads
 * `default · 30 s`. Null when nothing differs for that target and argument.
 */
export function resolvedCell(
  rows: readonly ResolvedArgument[] | undefined,
  argName: string,
  spacecraftId: string,
): { text: string; entered: string | null } | null {
  const r = shownRows(rows).find(
    (x) =>
      x.name === argName && (x.spacecraft_ids === null || x.spacecraft_ids.includes(spacecraftId)),
  );
  if (!r) return null;
  if (r.entered_value_json === null)
    return {
      text: `default · ${withUnit(r.sent_value_json ?? r.resolved_value_json, r.unit)}`,
      entered: null,
    };
  return {
    text: shownValue(r.sent_value_json ?? r.resolved_value_json),
    entered: `entered ${shownValue(r.entered_value_json)}`,
  };
}

export type ResolvedCommand = Readonly<{ position: number; label: string; lines: string[] }>;
/** Arm's summary (ux U68): the lines under each command that has any, in stack order. */
export function resolvedByCommand(
  commands:
    | readonly Readonly<{
        position: number;
        resolved_arguments?: readonly ResolvedArgument[] | undefined;
      }>[]
    | undefined,
  nameOf: (id: string) => string,
  labelOf: (position: number) => string,
): ResolvedCommand[] {
  return [...(commands ?? [])]
    .sort((a, b) => a.position - b.position)
    .map((c) => ({
      position: c.position,
      label: `${c.position + 1} · ${labelOf(c.position)}`,
      lines: resolvedLines(c.resolved_arguments, nameOf),
    }))
    .filter((c) => c.lines.length > 0);
}
