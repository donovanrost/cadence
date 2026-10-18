import type { ExplorationQuery, SampleInspection } from "./contracts";

function exact(value: unknown, keys: string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw Error("Invalid sample object");
  const object = value as Record<string, unknown>;
  if (Object.keys(object).length !== keys.length || keys.some((key) => !Object.hasOwn(object, key)))
    throw Error("Invalid sample fields");
  return object;
}
function text(value: unknown, max = 256): value is string {
  return (
    typeof value === "string" && value.length > 0 && new TextEncoder().encode(value).length <= max
  );
}
function optional(value: unknown) {
  return value === null || text(value);
}
function instant(value: unknown): bigint | null {
  if (!text(value, 40)) return null;
  const parts =
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|[+-]\d{2}:\d{2})$/.exec(
      value,
    );
  if (!parts) return null;
  const [, y, m, d, h, min, sec, fraction, zone] = parts;
  const year = Number(y),
    month = Number(m),
    day = Number(d);
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > (days[month - 1] ?? 0) ||
    Number(h) > 23 ||
    Number(min) > 59 ||
    Number(sec) > 59
  )
    return null;
  const milliseconds = Date.parse(`${y}-${m}-${d}T${h}:${min}:${sec}${zone}`);
  return Number.isFinite(milliseconds)
    ? BigInt(milliseconds) * 1000n + BigInt((fraction ?? "").padEnd(6, "0"))
    : null;
}
function timestamp(value: unknown): value is string {
  return instant(value) !== null;
}
export function sameInstant(left: unknown, right: unknown): boolean {
  const value = instant(left);
  return value !== null && value === instant(right);
}
function value(value: unknown) {
  const v = exact(value, ["state", "text", "format"]);
  if (v.state !== "ready") {
    if (
      !["not_recorded", "limited", "unsupported"].includes(String(v.state)) ||
      v.text !== null ||
      v.format !== null
    )
      throw Error("Invalid unavailable sample value");
    return;
  }
  if (!text(v.text, 4096)) throw Error("Invalid sample value text");
  if (v.format === "json") JSON.parse(v.text);
  else if (v.format !== "hex" || !/^(?:[a-f0-9]{2})+$/.test(v.text))
    throw Error("Invalid sample value format");
}
export function readInspection(input: unknown, query: ExplorationQuery): SampleInspection {
  const i = exact(input, ["status", "sample"]);
  if (!query.sample_id) {
    if (i.status !== "not_selected" || i.sample !== null)
      throw Error("Unrequested physical sample");
    return input as SampleInspection;
  }
  if (i.status !== "ready") {
    if (
      !["not_found", "ambiguous", "unsupported", "timeout", "unavailable"].includes(
        String(i.status),
      ) ||
      i.sample !== null
    )
      throw Error("Invalid sample inspection state");
    return input as SampleInspection;
  }
  const s = exact(i.sample, [
    "point_id",
    "point_name",
    "sample_id",
    "spacecraft_id",
    "receipt_time",
    "generation_time",
    "quality",
    "raw_value",
    "engineering_value",
    "source",
    "record",
  ]);
  const source = exact(s.source, [
    "data_source_id",
    "source_binding_id",
    "realm",
    "source_endpoint_id",
    "replay_run_id",
  ]);
  const record = exact(s.record, [
    "packet_id",
    "evidence_id",
    "packet_definition_id",
    "packet_definition_version",
    "validity_state",
  ]);
  if (
    !text(s.point_id) ||
    s.point_id !== query.point_id ||
    !text(s.sample_id) ||
    s.sample_id !== query.sample_id ||
    ![s.point_name, s.spacecraft_id].every(optional) ||
    !timestamp(s.receipt_time) ||
    !(s.generation_time === null || timestamp(s.generation_time)) ||
    !["good", "suspect", "bad"].includes(String(s.quality)) ||
    !text(source.data_source_id) ||
    !text(source.source_binding_id) ||
    !["flight", "rehearsal", "replay", "simulation"].includes(String(source.realm)) ||
    ![source.source_endpoint_id, source.replay_run_id].every(optional) ||
    (source.realm === "replay") !== (source.replay_run_id !== null) ||
    ![record.packet_id, record.evidence_id, record.packet_definition_id].every(optional) ||
    !(
      record.packet_definition_version === null ||
      (Number.isSafeInteger(record.packet_definition_version) &&
        Number(record.packet_definition_version) > 0)
    ) ||
    !(
      record.validity_state === null ||
      (typeof record.validity_state === "string" &&
        ["canonical", "duplicate", "conflict", "superseded", "advisory"].includes(
          record.validity_state,
        ))
    )
  )
    throw Error("Invalid physical sample");
  for (const [key, actual] of [
    ["data_source_id", source.data_source_id],
    ["source_binding_id", source.source_binding_id],
    ["selected_data_source_id", source.data_source_id],
    ["selected_source_binding_id", source.source_binding_id],
    ["realm", source.realm],
    ["replay_run_id", source.replay_run_id],
    ["spacecraft_id", s.spacecraft_id],
  ] as const)
    if (query[key] && query[key] !== actual) throw Error("Sample query context mismatch");
  if (
    source.realm !== (query.realm ?? (query.time_mode === "replay_run" ? "replay" : "flight")) ||
    source.replay_run_id !== (query.replay_run_id ?? null) ||
    (query.scope_kind === "source_endpoint" && query.scope_id !== source.source_endpoint_id) ||
    (query.scope_kind === "spacecraft" && query.scope_id !== s.spacecraft_id) ||
    (query.selected_time &&
      (instant(query.selected_time) === null ||
        instant(query.selected_time) !== instant(s.receipt_time)))
  )
    throw Error("Sample selection context mismatch");
  value(s.raw_value);
  value(s.engineering_value);
  return input as SampleInspection;
}
