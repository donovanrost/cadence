import { definitionLink, id, integer, name, nullable, record, stamp, text } from "./contracts";
import { evidence } from "./evidence";
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
export function state(x: unknown, definitionBase: string): x is State {
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
    evidence(x)
  );
}
