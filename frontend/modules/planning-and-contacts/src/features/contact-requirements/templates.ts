import { arrayOf, oneOf, type Snapshot } from "@cadence/plugin-sdk/admission";
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
  admitDeclarationContext,
  type SpacecraftChoices,
  type DeclarationContext,
} from "./declaration";
import type { TemplateValues } from "./OpsContactRequirementTemplate.contracts";
export type TemplateReference = Snapshot<{
  organization_id: string;
  mission_id: string;
  template_id: string;
  version: number;
  content_sha256: string;
  lifecycle_state: "active" | "paused" | "closed";
  lifecycle_changed_at: string;
  lifecycle_changed_by: string;
}>;
export type TemplateEntry = Snapshot<{
  reference: TemplateReference;
  spacecraft_id: string;
  contact_intent: string;
  schedule: {
    anchor_at: string;
    ends_at: string | null;
    window_offset_seconds: number;
    window_duration_seconds: number;
  } & ({ type: "fixed_interval"; interval_seconds: number } | { type: "daily"; time_utc: string });
}>;
export type TemplateModel = Snapshot<{
  contract_version: 1;
  context: DeclarationContext;
  defaults: { anchor_at: string; time_utc: string };
  can_manage: boolean;
  templates: { page: number; more: boolean; entries: TemplateEntry[] };
  spacecraft: SpacecraftChoices;
}>;
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
export type TemplateLifecycleAction = "pause-template" | "activate-template" | "close-template";
export type TemplateEffectAction = TemplateLifecycleAction | "create-template";
export type TemplateInputs = {
  "validate-template": { template: TemplateValues };
  "create-template": { template: TemplateValues };
  "pause-template": { reference: TemplateReference };
  "activate-template": { reference: TemplateReference };
  "close-template": { reference: TemplateReference };
  "templates-page": { page: number };
  "spacecraft-page": { page: number };
};
type EffectResult<S extends TemplateReference["lifecycle_state"]> = {
  contract_version: 1;
  actor_id: string;
  reference: TemplateReference & { lifecycle_state: S };
};
export type TemplateFeedback = keyof typeof templateFeedback;
export type TemplateResults = {
  "validate-template": { valid: boolean; feedback: TemplateFeedback[] };
  "create-template": EffectResult<"active"> & { reference: { version: 1 } };
  "pause-template": EffectResult<"paused">;
  "activate-template": EffectResult<"active">;
  "close-template": EffectResult<"closed">;
  "templates-page": { page: number };
  "spacecraft-page": { page: number };
};
export type TemplateCommand = {
  [A in TemplateAction]: Snapshot<{ action: A; input: TemplateInputs[A] }>;
}[TemplateAction];
export type TemplateRequest = {
  [A in TemplateAction]: [action: A, input: Snapshot<TemplateInputs[A]>];
}[TemplateAction];
export type TemplateOperation = {
  [A in TemplateAction]: Snapshot<
    {
      sequence: number;
      action: A;
      input: TemplateInputs[A];
    } & (
      | {
          status: "completed";
          receipt: { receiptId: string; completedAt: string; result: TemplateResults[A] };
        }
      | { status: "rejected"; receipt: null; feedback: TemplateFeedback[] }
      | { status: "unconfirmed"; receipt: null }
    )
  >;
}[TemplateAction];
export type TemplateCompletion = Extract<
  TemplateOperation,
  { action: TemplateEffectAction; status: "completed" }
>;
export function isTemplateCompletion(op: TemplateOperation): op is TemplateCompletion {
  return op.status === "completed" && !templatePure(op.action);
}
export type TemplatePage = Snapshot<{
  model: TemplateModel;
  sequence: number;
  operation: TemplateOperation | null;
}>;
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
export const templateFeedbackText = (codes: readonly TemplateFeedback[]) =>
  codes.map((c) => templateFeedback[c]).join(" ");
const feedback = (v: unknown): v is TemplateFeedback[] =>
  arrayOf(
    v,
    (c): c is TemplateFeedback => typeof c === "string" && Object.hasOwn(templateFeedback, c),
  ) && v.length <= 8;
const time = (v: unknown): v is string =>
  typeof v === "string" && /^(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,6})?$/.test(v);
export const templatePure = (action: TemplateAction) =>
  action === "validate-template" || action.endsWith("-page");
export function admitTemplateValues(v: unknown): v is TemplateValues {
  return (
    record(v) && Object.keys(v).length === 19 && templateFields.every((k) => safeText(v[k], 4096))
  );
}
export function admitTemplateReference(
  v: unknown,
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
    oneOf(["active", "paused", "closed"], v.lifecycle_state) &&
    validTime(v.lifecycle_changed_at) &&
    safeId(v.lifecycle_changed_by)
  );
}
function entry(v: unknown, c: DeclarationContext): v is TemplateEntry {
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
  v: unknown,
  context?: Partial<DeclarationContext>,
  defaults?: TemplateModel["defaults"],
): v is TemplateModel {
  if (!record(v) || v.contract_version !== 1 || !admitDeclarationContext(v.context, context))
    return false;
  const admittedContext = v.context;
  return (
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
    arrayOf(v.templates.entries, (e): e is TemplateEntry => entry(e, admittedContext)) &&
    v.templates.entries.length <= 25 &&
    (!v.templates.more || v.templates.entries.length === 25) &&
    new Set(v.templates.entries.map((e) => e.reference.template_id)).size ===
      v.templates.entries.length
  );
}
export function isTemplateCommand(
  v: unknown,
  c: DeclarationContext,
): v is TemplateCommand & Record<string, unknown> {
  if (
    !record(v) ||
    !oneOf(templateActions, v.action) ||
    !record(v.input) ||
    Object.keys(v.input).length !== 1
  )
    return false;
  if (v.action === "templates-page" || v.action === "spacecraft-page")
    return positive(v.input.page) && v.input.page <= 1000000;
  if (v.action === "validate-template" || v.action === "create-template")
    return admitTemplateValues(v.input.template);
  return admitTemplateReference(v.input.reference, c);
}
export function admitTemplateOperation(
  v: unknown,
  c: DeclarationContext,
): TemplateOperation | null {
  return validTemplateOperation(v, c) ? v : null;
}
function validTemplateOperation(v: unknown, c: DeclarationContext): v is TemplateOperation {
  if (
    !record(v) ||
    !positive(v.sequence) ||
    v.sequence > 1000000 ||
    !isTemplateCommand(v, c) ||
    !oneOf(["completed", "rejected", "unconfirmed"], v.status)
  )
    return false;
  if (v.status !== "completed")
    return v.receipt === null && (v.status !== "rejected" || feedback(v.feedback));
  const r = v.receipt;
  if (!record(r) || !safeId(r.receiptId) || !validTime(r.completedAt) || !record(r.result))
    return false;
  const result = r.result;
  if (v.action === "templates-page" || v.action === "spacecraft-page")
    return result.page === v.input.page;
  if (v.action === "validate-template")
    return (
      typeof result.valid === "boolean" &&
      feedback(result.feedback) &&
      (result.valid ? result.feedback.length === 0 : result.feedback.length > 0)
    );
  if (
    result.contract_version !== 1 ||
    result.actor_id !== c.actor_id ||
    !admitTemplateReference(result.reference, c) ||
    result.reference.lifecycle_changed_by !== c.actor_id
  )
    return false;
  const ref = result.reference;
  if (v.action === "create-template") return ref.version === 1 && ref.lifecycle_state === "active";
  const old = v.input.reference,
    state =
      v.action === "pause-template"
        ? "paused"
        : v.action === "activate-template"
          ? "active"
          : "closed";
  return (
    ref.template_id === old.template_id &&
    ref.version === old.version &&
    ref.content_sha256 === old.content_sha256 &&
    ref.lifecycle_state === state
  );
}
export function admitTemplatePage(
  input: unknown,
  context?: Partial<DeclarationContext>,
  defaults?: TemplateModel["defaults"],
): TemplatePage | null {
  try {
    const s = JSON.stringify(input);
    if (new TextEncoder().encode(s).length > 131072) return null;
    const v: unknown = JSON.parse(s);
    if (
      !record(v) ||
      !admitTemplateModel(v.model, context, defaults) ||
      !natural(v.sequence) ||
      v.sequence > 1000000
    )
      return null;
    if (v.operation === null)
      return v.sequence === 0 ? { model: v.model, sequence: 0, operation: null } : null;
    const op = admitTemplateOperation(v.operation, v.model.context);
    if (op?.status === "completed") {
      if (op.action === "templates-page" && v.model.templates.page !== op.receipt.result.page)
        return null;
      if (op.action === "spacecraft-page" && v.model.spacecraft.page !== op.receipt.result.page)
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
