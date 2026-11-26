import type { MissionId } from "@/api/index.ts";
import {
  actor as sharedActor,
  decoders,
  detailsOf,
  isError,
  isRecord,
  getAt,
  jsonObject,
  orNull,
  request,
  spacecraftRef,
  type ApiError,
  type ApiResult,
  type Decoded,
  type Reader,
  type JsonObject,
} from "@/api";
import { displayValue } from "@/features/changes/index.ts";
import { planStates } from "@/features/scheduling/index.ts";
import { formatCount, formatShort } from "@/ui";
import { templateStates } from "./api.ts";
import { templateSchemaReader, type TemplateSchema } from "./templates.ts";

/** Contract: docs/apogee/api/scheduling.md "Requirements (one-off; BACKLOG §8 8g)", api fb7510be. */
const { array, integer, nullable, object, optional, string, timestamp, token } = decoders;
const doc: Reader<JsonObject> = jsonObject;

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
  spacecraft: spacecraftRef,
  template_id: nullable(token),
  /** ux U48: the template version that generated it (api); null for one-offs, absent until api ships. */
  template_version: optional(nullable(integer)),
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
  /**
   * api f2dcc94bd: the plan past draft that holds it (the most recently changed if several), or
   * null; absent until it ships. `day` is the plan's UTC day (its first pass), null when the plan
   * has no passes yet.
   */
  held_by: optional(
    nullable(
      object({
        plan_id: token,
        revision: integer,
        state: decoders.known(planStates),
        day: optional(nullable(string)),
      }),
    ),
  ),
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

/**
 * ux P4 "Planning it" (director 11-14: whole-day planning): the UTC day an active requirement is
 * drafted with, or null when there's nothing to plan: not active, no readable window, or the
 * window has ended. api: a draft takes every window that overlaps its day, so it's the later of the
 * window's start day and today (ux: never a day that's over); `from` is clamped to now the same way.
 */
export function planningDay(
  r: Pick<RequirementRow, "state" | "content">,
  now: number,
): Readonly<{ iso: string; md: string; from: string; to: string }> | null {
  const from = r.content["earliest_start"];
  const to = r.content["latest_end"];
  if (r.state !== "active" || typeof from !== "string" || typeof to !== "string") return null;
  const start = Date.parse(from);
  const end = Date.parse(to);
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= now) return null;
  const begins = Math.max(start, now);
  const iso = new Date(begins).toISOString().slice(0, 10);
  return { iso, md: iso.slice(5), from: start < now ? new Date(now).toISOString() : from, to };
}

/**
 * ux P4: the requirement page's planning button. A plan past draft holding it is opened as
 * 'Open plan R41' (on the plan's day when api sends it, else the planning day); otherwise
 * 'Plan 11-14'. Null when there's nothing to plan (see planningDay).
 */
export function planningButton(
  r: Pick<RequirementDetail, "state" | "content" | "held_by">,
  now: number,
): Readonly<{ label: string; day: string }> | null {
  const day = planningDay(r, now);
  if (!day) return null;
  const held = r.held_by;
  return held
    ? { label: `Open plan R${held.revision}`, day: held.day ?? day.iso }
    : { label: `Plan ${day.md}`, day: day.iso };
}

/** A template occurrence's day, `11-15` (UTC, from its window's start); null when it has none. */
export function occurrenceDay(content: JsonObject): string | null {
  const v = content["earliest_start"];
  if (typeof v !== "string") return null;
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) return null;
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

/**
 * ux (ContactPlanning.md): closing or canceling ONE template occurrence leads with its scope and
 * ends with what domain confirmed (a0ca3fd5c): no template version, the current or a later edit,
 * regenerates that day; a one-off requirement is the way back.
 */
export function occurrenceScope(
  action: EndAction,
  o: Readonly<{ day: string; template: string }>,
): Readonly<{ lead: string; final: string }> {
  const verb = action === "close" ? "closes" : "cancels";
  return {
    lead: `This ${verb} only the ${o.day} occurrence of “${o.template}”. The template's other days aren't affected.`,
    // ux U48 + domain a0ca3fd5c: an edit no longer regenerates closed or canceled days.
    final: `This is final for this day: the template won't bring it back, even when the template is edited. To plan ${o.day} again, add a one-off requirement for it.`,
  };
}

/** `11-14 00:00Z → 11-15 00:00Z` (ContactPlanning.md P4, §4). */
export function windowText(content: JsonObject): string {
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
      // compared-as-text: a schema field path, an open set the server's schema defines
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
    { key: "spacecraft", label: "Spacecraft", value: r.spacecraft.name ?? "Unknown spacecraft" },
    { key: "window", label: "Window", value: windowText(r.content), mono: true },
  ];
  for (const f of s.fields) {
    if (["spacecraft_id", "earliest_start", "latest_end"].includes(f.path)) continue;
    const v = getAt(r.content, f.path);
    const label = f.enum?.find((o) => JSON.stringify(o.value) === JSON.stringify(v))?.label;
    const value =
      v === null || v === undefined
        ? // compared-as-text: a schema field path, an open set the server's schema defines
          f.path === "max_gap_seconds"
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
export function withoutBlankConstraints(document: JsonObject): Record<string, unknown> {
  const blank = (v: unknown) =>
    isRecord(v) &&
    Object.keys(v).every((k) => k === "allowed" || k === "excluded") &&
    v["allowed"] == null &&
    v["excluded"] == null;
  return Object.fromEntries(
    Object.entries(document).filter(([k, v]) => !(k.endsWith("_constraints_document") && blank(v))),
  );
}
