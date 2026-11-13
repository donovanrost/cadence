import type { MissionId } from "@/api/index.ts";
import {
  actor as sharedActor,
  decoders,
  detailsOf,
  isError,
  isRecord,
  jsonObject,
  orNull,
  request,
  type ApiError,
  type ApiResult,
  type Decoded,
  type Reader,
} from "@/api";
import { displayValue } from "@/features/changes/index.ts";
import { formatCount, formatShort } from "@/ui";
import { templateStates } from "./api.ts";
import { readPath, templateSchemaReader, type TemplateSchema } from "./templates.ts";

/** Contract: docs/apogee/api/scheduling.md "Requirements (one-off; BACKLOG §8 8g)", api fb7510be. */
const { array, integer, nullable, object, string, timestamp, token } = decoders;
const doc: Reader<Readonly<Record<string, unknown>>> = jsonObject;

/** The shared entity (typing §12 A5). */
const actor = orNull(sharedActor);
const stateChanged = nullable(
  object({
    at: timestamp,
    by: actor,
    // free-text: the reason a person typed when closing or canceling.
    reason: nullable(string),
  }),
);

export const requirementStates = ["active", "closed", "canceled"] as const;
const requirementRowShape = {
  id: token,
  state: decoders.known(requirementStates),
  version: integer,
  spacecraft: object({ id: token, name: nullable(string) }),
  template_id: nullable(token),
  content: doc,
  updated_at: timestamp,
  state_changed: stateChanged,
  /** Asked of api: the templates' server sentence; absent until then. */
  rule_summary: (value: unknown, path?: string) =>
    value === undefined ? null : nullable(string)(value, path),
};
const requirementRow = object(requirementRowShape);
export type RequirementRow = Decoded<typeof requirementRow>;

const listReader = object({
  requirements: array(requirementRow, 200),
  page: integer,
  next_page: nullable(integer),
});
export type RequirementPage = Decoded<typeof listReader>;

const detailReader = object({
  ...requirementRowShape,
  versions: array(object({ version: integer, created_at: timestamp, actor }), 500),
});
export type RequirementDetail = Decoded<typeof detailReader>;

const base = (missionId: MissionId) =>
  `/missions/${encodeURIComponent(missionId)}/contact-planning/requirements`;

export function fetchRequirementSchema(
  missionId: MissionId,
  signal: AbortSignal,
): Promise<ApiResult<TemplateSchema>> {
  return request(`${base(missionId)}/schema`, templateSchemaReader, { signal });
}

export type RequirementQuery = Readonly<{
  missionId: MissionId;
  source: "one_off" | "template" | null;
  page: number;
}>;

export function fetchRequirements(
  q: RequirementQuery,
  signal: AbortSignal,
): Promise<ApiResult<RequirementPage>> {
  const params = new URLSearchParams({ page: String(q.page), limit: "50" });
  if (q.source) params.set("source", q.source);
  return request(`${base(q.missionId)}?${params.toString()}`, listReader, { signal });
}

export function fetchRequirement(
  key: Readonly<{ missionId: MissionId; requirementId: string }>,
  signal: AbortSignal,
): Promise<ApiResult<RequirementDetail>> {
  return request(`${base(key.missionId)}/${encodeURIComponent(key.requirementId)}`, detailReader, {
    signal,
  });
}

/** Create (id null) or a new version: an omitted key carries over, explicit null clears. */
export function saveRequirement(
  missionId: MissionId,
  id: string | null,
  body: Readonly<{
    content: Record<string, unknown>;
    expected_version?: number;
    /** Creates only: one per form open, reused on retry (api 66875fb39, qa P4). */
    operation_id?: string;
  }>,
) {
  return request(
    id ? `${base(missionId)}/${encodeURIComponent(id)}` : base(missionId),
    object({ id: token, version: integer }),
    { method: "POST", body },
  );
}

/** A replayed create (409 duplicate_operation): the id of the row the first attempt made. */
export function alreadyCreated(
  error: ApiError,
  key: "requirement_id" | "template_id",
): string | null {
  if (!isError(error, "duplicate_operation")) return null;
  return detailsOf(error, object({ [key]: token }))?.[key] ?? null;
}

export type EndAction = "close" | "cancel";

/** Close (the need is over) or cancel (withdrawn): final, with a required reason. */
export function endRequirement(
  missionId: MissionId,
  id: string,
  action: EndAction,
  body: Readonly<{ expected_version: number; reason: string }>,
) {
  return request(
    `${base(missionId)}/${encodeURIComponent(id)}/${action}`,
    object({ id: token, state: decoders.known(["closed", "canceled"] as const), version: integer }),
    { method: "POST", body },
  );
}

/** `11-14 00:00Z → 11-15 00:00Z` (ContactPlanning.md P4, §4). */
export function windowText(content: Readonly<Record<string, unknown>>): string {
  const at = (v: unknown) => (typeof v === "string" ? formatShort(new Date(v)) : "—");
  return `${at(content["earliest_start"])} → ${at(content["latest_end"])}`;
}

const endedWord: Readonly<Record<"closed" | "canceled" | "unrecognized", string>> = {
  closed: "Closed",
  canceled: "Canceled",
  unrecognized: "Ended",
};

/** `Closed by Mira K. on 11-12: <reason>` (ux P4); null while active. */
export function endedLine(r: Pick<RequirementRow, "state" | "state_changed">): string | null {
  if (r.state === "active") return null;
  const c = r.state_changed;
  const by = c?.by?.name ? ` by ${c.by.name}` : "";
  const on = c ? ` on ${c.at.slice(5, 10)}` : "";
  return `${endedWord[r.state]}${by}${on}${c?.reason ? `: ${c.reason}` : ""}`;
}

/** 409 requirement_not_active: who ended it, from details, without a refetch (api's ask (a)). */
export function notActiveLine(error: ApiError): string | null {
  if (!isError(error, "requirement_not_active")) return null;
  const details = detailsOf(
    error,
    object({ state: decoders.known(["closed", "canceled"] as const), state_changed: stateChanged }),
  );
  if (!details) return "It already ended.";
  return `Already ${endedLine(details)?.replace(/^\w/, (c) => c.toLowerCase()) ?? "ended"}.`;
}

/** The schema's groups in order (Window, then Requirement), advanced fields apart (ux P4). */
export function schemaGroups(s: TemplateSchema) {
  const keys = [...new Set(s.meta.map((m) => m.group))];
  return keys.map((key) => ({
    key,
    fields: s.fields.filter((_, i) => s.meta[i]?.group === key && !s.meta[i]?.advanced),
    advanced: s.fields.filter((_, i) => s.meta[i]?.group === key && s.meta[i]?.advanced),
  }));
}

/** `spacecraft_id` is a bare reference in the schema; offer the mission's spacecraft by name. */
export function withSpacecraftChoices(
  s: TemplateSchema,
  spacecraft: readonly Readonly<{ id: string; name: string }>[],
): TemplateSchema {
  const choices = spacecraft.map((sc) => ({ value: sc.id, label: sc.name }));
  return {
    ...s,
    fields: s.fields.map((f) =>
      f.path === "spacecraft_id" && choices.length > 0 ? { ...f, enum: choices } : f,
    ),
  };
}

/** 422 details keyed by field path → inline errors (api: `details.max_gap_seconds` etc.). */
export function fieldErrors(error: ApiError): Record<string, string> {
  if (error.kind !== "invalid" || error.details === null || typeof error.details !== "object")
    return {};
  const out: Record<string, string> = {};
  for (const [k, raw] of Object.entries(error.details)) {
    const v: unknown = raw;
    const text = Array.isArray(v) ? v.filter((x) => typeof x === "string").join(" ") : v;
    if (typeof text === "string" && text) out[k.replace(/^content\./, "")] = text;
  }
  return out;
}

/** The read view's facts: each schema field in words; an empty gap limit reads "No limit" (ux P4). */
export function requirementFacts(
  s: TemplateSchema,
  r: Pick<RequirementDetail, "content" | "spacecraft">,
): { key: string; label: string; value: string; mono?: boolean }[] {
  const facts = [
    { key: "spacecraft", label: "Spacecraft", value: r.spacecraft.name ?? r.spacecraft.id },
    { key: "window", label: "Window", value: windowText(r.content), mono: true },
  ];
  for (const f of s.fields) {
    if (["spacecraft_id", "earliest_start", "latest_end"].includes(f.path)) continue;
    const v = readPath(r.content, f.path);
    const label = f.enum?.find((o) => JSON.stringify(o.value) === JSON.stringify(v))?.label;
    const value =
      v === null || v === undefined
        ? f.path === "max_gap_seconds"
          ? "No limit"
          : "—"
        : (label ?? displayValue(f, v));
    facts.push({
      key: f.path,
      label: f.label,
      value,
      mono: label === undefined && typeof v === "number",
    });
  }
  return facts;
}

const templateStateWord: Readonly<
  Record<(typeof templateStates)[number] | "unrecognized", string>
> = {
  active: "",
  paused: " · paused",
  closed: " · closed",
  unrecognized: " · state not known",
};
const byTemplateReader = object({
  day: string,
  templates: array(
    object({
      template: object({ id: token, name: string, state: decoders.known(templateStates) }),
      count: integer,
      active_count: integer,
    }),
    1000,
  ),
});
export type TemplateDayCounts = Decoded<typeof byTemplateReader>;

/** P4 "From templates" (api df98dcd3): per template, the requirements whose window opens that UTC day. */
export function fetchByTemplate(
  key: Readonly<{ missionId: MissionId; day: string }>,
  signal: AbortSignal,
): Promise<ApiResult<TemplateDayCounts>> {
  return request(
    `${base(key.missionId)}/by-template?day=${encodeURIComponent(key.day)}`,
    byTemplateReader,
    {
      signal,
    },
  );
}

/** ux P4: `Block 1 daily · 1,500 for 11-14 · 1,480 active` (+ `· paused` / `· closed` for a template no longer active). */
export function templateCountLine(
  row: TemplateDayCounts["templates"][number],
  day: string,
): string {
  const active = row.active_count === row.count ? "" : ` · ${formatCount(row.active_count)} active`;
  const retired = templateStateWord[row.template.state];
  return `${formatCount(row.count)} for ${day.slice(5)}${active}${retired}`;
}

/**
 * qa (P4): a constraints document left untouched in Advanced is `{allowed: null, excluded: null}`,
 * which older servers refuse (422 constraints). Untouched means no constraint, so it's left out.
 */
export function withoutBlankConstraints(
  document: Readonly<Record<string, unknown>>,
): Record<string, unknown> {
  const blank = (v: unknown) =>
    isRecord(v) &&
    Object.keys(v).every((k) => k === "allowed" || k === "excluded") &&
    v["allowed"] == null &&
    v["excluded"] == null;
  return Object.fromEntries(
    Object.entries(document).filter(([k, v]) => !(k.endsWith("_constraints_document") && blank(v))),
  );
}
