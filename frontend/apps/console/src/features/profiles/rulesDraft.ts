import type { ProfileRule } from "./detail.ts";

/**
 * Editable profile routing rules (domain P2: staged as one change at path `routing_rules`).
 * Values mirror the stored document: stations by ground_station_id, legs by direction + role.
 */
export const directions = ["downlink", "uplink"] as const;
export const roles = ["primary", "candidate", "contributing"] as const;
export type Direction = (typeof directions)[number];
export type Role = (typeof roles)[number];

export type RuleDraft = {
  id: string;
  label: string;
  nameTemplate: string;
  enabled: boolean;
  stationIds: string[];
  legs: { direction: Direction; role: Role }[];
};

const asDirection = (d: string): Direction => (d === "uplink" ? "uplink" : "downlink");
const asRole = (r: string): Role => roles.find((known) => known === r) ?? "primary";

export function toDrafts(rules: readonly ProfileRule[]): RuleDraft[] {
  return rules.map((r) => ({
    id: r.id,
    label: r.label,
    nameTemplate: r.name_template,
    enabled: r.enabled,
    stationIds: r.stations.map((s) => s.id),
    legs: r.legs.map((l) => ({ direction: asDirection(l.direction), role: asRole(l.role) })),
  }));
}

/** A new rule with a slug id that doesn't clash with the others. */
export function newRule(existing: readonly RuleDraft[]): RuleDraft {
  let n = existing.length + 1;
  while (existing.some((r) => r.id === `rule-${n}`)) n += 1;
  return {
    id: `rule-${n}`,
    label: `Rule ${n}`,
    nameTemplate: "{station} · {spacecraft}",
    enabled: true,
    stationIds: [],
    legs: [{ direction: "downlink", role: "primary" }],
  };
}

/** The stored document shape (transport_id left to the server: a station's single transport). */
export function toDocument(drafts: readonly RuleDraft[]) {
  return drafts.map((d) => ({
    id: d.id,
    label: d.label.trim(),
    name_template: d.nameTemplate.trim(),
    enabled: d.enabled,
    stations: d.stationIds.map((id) => ({ ground_station_id: id, transport_id: null })),
    legs: d.legs.map((l) => ({ direction: l.direction, role: l.role })),
  }));
}

export const tokens = [
  "{station}",
  "{station_name}",
  "{spacecraft}",
  "{scid}",
  "{direction}",
] as const;

/** The name template's tokens the server won't know, in the order typed. */
export function unknownTokens(nameTemplate: string): string[] {
  return (nameTemplate.match(/\{[^}]*\}/g) ?? []).filter((t) => !tokens.some((k) => k === t));
}

/** #307: "token {plane}" / "tokens {a} and {b}" / "tokens {a}, {b} and {c}"; every token named. */
export function unknownTokenWords(unknown: readonly string[]): string {
  if (unknown.length <= 1) return `token ${unknown.join("")}`;
  return `tokens ${unknown.slice(0, -1).join(", ")} and ${unknown[unknown.length - 1]}`;
}

/** Profile.md P2 (#307): the Route name field's error, naming each unknown token; null when none. */
export function unknownTokenError(nameTemplate: string): string | null {
  const unknown = unknownTokens(nameTemplate);
  return unknown.length > 0 ? `Unknown ${unknownTokenWords(unknown)}.` : null;
}

/** Browser checks only (the server's dry run decides): label, a station, a leg, known tokens. */
export function draftProblems(drafts: readonly RuleDraft[]): string[] {
  const problems: string[] = [];
  drafts.forEach((d, i) => {
    const name = d.label.trim() || `Rule ${i + 1}`;
    if (!d.label.trim()) problems.push(`Rule ${i + 1}: give it a label.`);
    if (d.stationIds.length === 0) problems.push(`${name}: pick at least one station.`);
    if (d.legs.length === 0) problems.push(`${name}: add a downlink or uplink leg.`);
    const unknown = unknownTokens(d.nameTemplate);
    if (unknown.length > 0) problems.push(`${name}: unknown ${unknownTokenWords(unknown)}.`);
  });
  return problems;
}

/** The keys of a stored rule (`toDocument`), the fields a server error path can name. */
const ruleFields = ["label", "name_template", "enabled", "stations", "legs"] as const;
type RuleField = (typeof ruleFields)[number];

/** A rule document field as the form labels it (RuleForm, RuleStations, RuleLegs). */
const ruleFieldWords: Readonly<Record<RuleField, string>> = {
  label: "Label",
  name_template: "Route name",
  enabled: "Enabled",
  stations: "Stations",
  legs: "Legs",
};

/** The path segment as a rule field, or null for one this console doesn't know. */
const ruleField = (segment: string | undefined): RuleField | null =>
  ruleFields.find((f) => f === segment) ?? null;

/**
 * #307 (Profile.md P2: labels, never paths): a server error path such as
 * `routing_rules.0.stations.1.transport_id` read as "Uplink pair · Stations", by the rule's own
 * label (else "Rule 1") and the form's field label. A path this console doesn't know reads
 * "Routing rules", never the raw path.
 */
export function rulePathWords(path: string, drafts: readonly RuleDraft[]): string {
  const m = /^routing_rules\.(\d+)(?:\.([a-z_]+))?/.exec(path);
  if (!m) return "Routing rules";
  const i = Number(m[1]);
  const rule = drafts[i]?.label.trim() || `Rule ${i + 1}`;
  const field = ruleField(m[2]);
  return field ? `${rule} · ${ruleFieldWords[field]}` : rule;
}
