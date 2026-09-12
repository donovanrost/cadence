import {
  natural,
  positive,
  record,
  safeId,
  safeText,
  validTime,
  requirementDataEqual as equal,
} from "./requirement-directory";
import {
  admitSpacecraftChoices,
  type SpacecraftChoices,
  type DeclarationContext,
} from "./declaration";
import type { TemplateValues } from "./OpsContactRequirementTemplate.contracts";
export type TemplateReference = {
  organization_id: string;
  mission_id: string;
  template_id: string;
  version: number;
  content_sha256: string;
  lifecycle_state: "active" | "paused" | "closed";
  lifecycle_changed_at: string;
  lifecycle_changed_by: string;
};
export type TemplateEntry = {
  reference: TemplateReference;
  spacecraft_id: string;
  contact_intent: string;
  schedule: {
    type: "daily" | "fixed_interval";
    anchor_at: string;
    ends_at: string | null;
    window_offset_seconds: number;
    window_duration_seconds: number;
    interval_seconds?: number;
    time_utc?: string;
  };
};
export type TemplateModel = {
  contract_version: 1;
  context: DeclarationContext;
  defaults: { anchor_at: string; time_utc: string };
  can_manage: boolean;
  templates: { page: number; more: boolean; entries: TemplateEntry[] };
  spacecraft: SpacecraftChoices;
};
export const templateActions = [
  "validate-template",
  "create-template",
  "pause-template",
  "activate-template",
  "close-template",
  "templates-page",
  "spacecraft-page",
] as const;
export type TemplateAction = (typeof templateActions)[number];
export type TemplateOperation = {
  sequence: number;
  action: TemplateAction;
  input: Record<string, any>;
  status: "completed" | "rejected" | "unconfirmed";
  feedback?: string[];
  receipt: null | { receiptId: string; completedAt: string; result: Record<string, any> };
};
export type TemplatePage = {
  model: TemplateModel;
  sequence: number;
  operation: TemplateOperation | null;
};
export const templateFields = [
  "spacecraft_id",
  "schedule_type",
  "anchor_at",
  "time_utc",
  "interval_minutes",
  "window_offset_minutes",
  "window_duration_minutes",
  "contact_intent",
  "success_measure",
  "minimum_duration_seconds",
  "preferred_duration_seconds",
  "minimum_data_volume_bytes",
  "contact_count",
  "minimum_separation_seconds",
  "priority",
  "approval_mode",
  "maximum_occurrences_per_run",
  "maximum_lookback_hours",
  "rationale",
] as const;
export const templateFeedback = {
  required_fields: "Complete the required spacecraft, contact intent and rationale fields.",
  forbidden: "Administrator authority is required to manage recurring needs.",
  stale_evidence: "This template changed. Refresh the ledger before acting on it.",
  spacecraft_unavailable: "Choose a spacecraft that still belongs to this mission.",
  invalid_time: "Enter a valid UTC start and daily time.",
  invalid_number: "Review the whole-number schedule, outcome and catch-up amounts.",
  invalid_schedule: "Choose a supported recurrence schedule.",
  invalid_input: "Review the template fields and try again.",
  invalid_template:
    "Review the recurrence, outcome, approval and catch-up constraints. The template could not be accepted.",
} as const;
export const templateFeedbackText = (codes: string[]) =>
  codes.map((c) => templateFeedback[c as keyof typeof templateFeedback]).join(" ");
const feedback = (v: any): v is string[] =>
  Array.isArray(v) &&
  v.length <= 8 &&
  v.every((c) => typeof c === "string" && Object.hasOwn(templateFeedback, c));
const time = (v: any): v is string =>
  typeof v === "string" && /^(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,6})?$/.test(v);
export const templatePure = (action: TemplateAction) =>
  action === "validate-template" || action.endsWith("-page");
export function admitTemplateValues(v: any): v is TemplateValues {
  return (
    record(v) && Object.keys(v).length === 19 && templateFields.every((k) => safeText(v[k], 4096))
  );
}
export function admitTemplateReference(
  v: any,
  c: Pick<DeclarationContext, "organization_id" | "mission_id">,
): v is TemplateReference {
  return (
    record(v) &&
    Object.keys(v).length === 8 &&
    v.organization_id === c.organization_id &&
    v.mission_id === c.mission_id &&
    safeId(v.template_id) &&
    positive(v.version) &&
    typeof v.content_sha256 === "string" &&
    /^[a-f0-9]{64}$/.test(v.content_sha256) &&
    ["active", "paused", "closed"].includes(v.lifecycle_state) &&
    validTime(v.lifecycle_changed_at) &&
    safeId(v.lifecycle_changed_by)
  );
}
function entry(v: any, c: DeclarationContext): v is TemplateEntry {
  if (
    !record(v) ||
    !admitTemplateReference(v.reference, c) ||
    !safeId(v.spacecraft_id) ||
    !safeText(v.contact_intent, 2000) ||
    !record(v.schedule)
  )
    return false;
  const s = v.schedule;
  return (
    validTime(s.anchor_at) &&
    (s.ends_at === null ||
      (validTime(s.ends_at) && Date.parse(s.ends_at) > Date.parse(s.anchor_at))) &&
    Number.isSafeInteger(s.window_offset_seconds) &&
    positive(s.window_duration_seconds) &&
    (s.type === "fixed_interval"
      ? positive(s.interval_seconds)
      : s.type === "daily" && time(s.time_utc))
  );
}
export function admitTemplateModel(
  v: any,
  context?: Partial<DeclarationContext>,
  defaults?: TemplateModel["defaults"],
): v is TemplateModel {
  return (
    record(v) &&
    v.contract_version === 1 &&
    record(v.context) &&
    ["organization_id", "mission_id", "actor_id"].every((k) => safeId(v.context[k])) &&
    (!context || Object.entries(context).every(([k, value]) => v.context[k] === value)) &&
    record(v.defaults) &&
    validTime(v.defaults.anchor_at) &&
    time(v.defaults.time_utc) &&
    (!defaults || equal(defaults, v.defaults)) &&
    typeof v.can_manage === "boolean" &&
    admitSpacecraftChoices(v.spacecraft) &&
    record(v.templates) &&
    positive(v.templates.page) &&
    v.templates.page <= 1000000 &&
    typeof v.templates.more === "boolean" &&
    Array.isArray(v.templates.entries) &&
    v.templates.entries.length <= 25 &&
    (!v.templates.more || v.templates.entries.length === 25) &&
    v.templates.entries.every((e: any) => entry(e, v.context)) &&
    new Set(v.templates.entries.map((e: any) => e.reference.template_id)).size ===
      v.templates.entries.length
  );
}
export function admitTemplateOperation(v: any, c: DeclarationContext): TemplateOperation | null {
  if (
    !record(v) ||
    !positive(v.sequence) ||
    v.sequence > 1000000 ||
    !templateActions.includes(v.action) ||
    !record(v.input) ||
    Object.keys(v.input).length !== 1 ||
    !["completed", "rejected", "unconfirmed"].includes(v.status)
  )
    return null;
  if (v.action.endsWith("-page")) {
    if (!positive(v.input.page) || v.input.page > 1000000) return null;
  } else if (v.action === "validate-template" || v.action === "create-template") {
    if (!admitTemplateValues(v.input.template)) return null;
  } else if (!admitTemplateReference(v.input.reference, c)) return null;
  if (v.status !== "completed")
    return v.receipt === null && (v.status !== "rejected" || feedback(v.feedback))
      ? (v as TemplateOperation)
      : null;
  const r = v.receipt;
  if (!record(r) || !safeId(r.receiptId) || !validTime(r.completedAt) || !record(r.result))
    return null;
  const result = r.result;
  if (v.action.endsWith("-page"))
    return result.page === v.input.page ? (v as TemplateOperation) : null;
  if (v.action === "validate-template")
    return typeof result.valid === "boolean" &&
      feedback(result.feedback) &&
      (result.valid ? result.feedback.length === 0 : result.feedback.length > 0)
      ? (v as TemplateOperation)
      : null;
  if (
    result.contract_version !== 1 ||
    result.actor_id !== c.actor_id ||
    !admitTemplateReference(result.reference, c) ||
    result.reference.lifecycle_changed_by !== c.actor_id
  )
    return null;
  const ref = result.reference;
  if (v.action === "create-template")
    return ref.version === 1 && ref.lifecycle_state === "active" ? (v as TemplateOperation) : null;
  const old = v.input.reference,
    state =
      v.action === "pause-template"
        ? "paused"
        : v.action === "activate-template"
          ? "active"
          : "closed";
  return ref.template_id === old.template_id &&
    ref.version === old.version &&
    ref.content_sha256 === old.content_sha256 &&
    ref.lifecycle_state === state
    ? (v as TemplateOperation)
    : null;
}
export function admitTemplatePage(
  input: unknown,
  context?: Partial<DeclarationContext>,
  defaults?: TemplateModel["defaults"],
): TemplatePage | null {
  try {
    const s = JSON.stringify(input);
    if (new TextEncoder().encode(s).length > 131072) return null;
    const v = JSON.parse(s);
    if (
      !record(v) ||
      !admitTemplateModel(v.model, context, defaults) ||
      !natural(v.sequence) ||
      v.sequence > 1000000
    )
      return null;
    if (v.operation === null) return v.sequence === 0 ? (v as TemplatePage) : null;
    const op = admitTemplateOperation(v.operation, v.model.context);
    if (op?.status === "completed") {
      if (op.action === "templates-page" && v.model.templates.page !== op.receipt!.result.page)
        return null;
      if (op.action === "spacecraft-page" && v.model.spacecraft.page !== op.receipt!.result.page)
        return null;
    }
    return op && op.sequence === v.sequence
      ? { model: v.model, sequence: v.sequence, operation: op }
      : null;
  } catch {
    return null;
  }
}
export function templateDefaults(m: TemplateModel): TemplateValues {
  return {
    spacecraft_id: "",
    schedule_type: "fixed_interval",
    anchor_at: m.defaults.anchor_at.replace(/Z$/, ""),
    time_utc: m.defaults.time_utc,
    interval_minutes: "360",
    window_offset_minutes: "0",
    window_duration_minutes: "30",
    contact_intent: "payload_downlink",
    success_measure: "minimum_duration",
    minimum_duration_seconds: "600",
    preferred_duration_seconds: "900",
    minimum_data_volume_bytes: "",
    contact_count: "1",
    minimum_separation_seconds: "0",
    priority: "high",
    approval_mode: "manual",
    maximum_occurrences_per_run: "100",
    maximum_lookback_hours: "168",
    rationale: "",
  };
}
