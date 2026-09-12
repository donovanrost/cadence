import { definitionLink, id, integer, name, nullable, record, stamp, text } from "./contracts";
export type State = {
  id: string;
  point_id: string;
  point_name: string;
  spacecraft_id: string | null;
  limit_set_name: string;
  definition_id: string;
  definition_version: number;
  sample_id: string;
  source_sample_type: "telemetry_sample" | "derived_telemetry_sample";
  value: string;
  state: string;
  severity: "red" | "yellow" | "blue" | "green";
  violation: boolean;
  generation_time: string | null;
  receipt_time: string;
  definition_href: string;
  evidence_href: string;
};
function evidence(v: Record<string, unknown>, mission: string) {
  const prefix = `/missions/${mission}/ops/explore?`;
  if (
    !text(v.evidence_href, 4096) ||
    !v.evidence_href.startsWith(prefix) ||
    /[\\#]/.test(v.evidence_href) ||
    v.evidence_href.split("").some((c) => c.charCodeAt(0) <= 32)
  )
    return false;
  const q = new URLSearchParams(v.evidence_href.slice(prefix.length));
  return (
    new Set(q.keys()).size === [...q.keys()].length &&
    [...q.keys()].every((k) =>
      ["point_id", "spacecraft_id", "sample_id", "selected_time"].includes(k),
    ) &&
    q.get("point_id") === v.point_id &&
    q.get("sample_id") === v.sample_id &&
    q.get("selected_time") === v.receipt_time &&
    q.get("spacecraft_id") === (v.spacecraft_id ?? null)
  );
}
export function counts(v: unknown): v is Record<State["severity"], number> {
  return (
    record(v) &&
    Object.keys(v).length === 4 &&
    ["red", "yellow", "blue", "green"].every((k) => integer(v[k]))
  );
}
export function state(x: unknown, definitionBase: string, mission: string): x is State {
  const normalized = {
    red_low: "red",
    red_high: "red",
    yellow_low: "yellow",
    yellow_high: "yellow",
    green: "green",
    blue: "blue",
  } as const;
  return (
    record(x) &&
    id(x.id) &&
    name(x.point_id) &&
    text(x.point_name) &&
    nullable(x.spacecraft_id, id) &&
    name(x.limit_set_name) &&
    id(x.definition_id) &&
    integer(x.definition_version) &&
    x.definition_version > 0 &&
    id(x.sample_id) &&
    ["telemetry_sample", "derived_telemetry_sample"].includes(x.source_sample_type as string) &&
    text(x.value, 4096) &&
    name(x.state) &&
    Object.hasOwn(normalized, x.state) &&
    normalized[x.state as keyof typeof normalized] === x.severity &&
    x.violation === !["green", "blue"].includes(x.state) &&
    nullable(x.generation_time, stamp) &&
    stamp(x.receipt_time) &&
    definitionLink(x.definition_href, definitionBase, x.definition_id, x.definition_version) &&
    evidence(x, mission)
  );
}
