import type { ContactRequirementValues } from "./OpsContactRequirementNew.contracts";
import {
  natural,
  positive,
  record,
  safeId,
  safeText,
  validTime,
  requirementDataEqual,
  requirementSegment,
} from "./requirement-directory";
export type DeclarationContext = { organization_id: string; mission_id: string; actor_id: string };
export type SpacecraftChoices = {
  page: number;
  total: number;
  entries: { id: string; name: string }[];
};
export type DeclarationModel = {
  contract_version: 1;
  context: DeclarationContext;
  horizon: { earliest_start: string; latest_end: string };
  spacecraft: SpacecraftChoices;
  can_declare: boolean;
};
export type DeclarationAction = "validate" | "save" | "spacecraft-page";
export type DeclarationOperation = {
  sequence: number;
  action: DeclarationAction;
  input: Record<string, any>;
  status: "completed" | "rejected" | "unconfirmed";
  feedback?: string[];
  receipt: null | { receiptId: string; completedAt: string; result: Record<string, any> };
};
export type DeclarationPage = {
  model: DeclarationModel;
  sequence: number;
  operation: DeclarationOperation | null;
};
export const declarationFields = [
  "spacecraft_id",
  "contact_intent",
  "earliest_start",
  "latest_end",
  "success_measure",
  "minimum_duration_seconds",
  "preferred_duration_seconds",
  "minimum_data_volume_bytes",
  "contact_count",
  "minimum_separation_seconds",
  "priority",
  "allowed_providers",
  "excluded_providers",
  "allowed_stations",
  "excluded_stations",
  "rationale",
] as const;
export const declarationFeedback = {
  required_fields: "Choose a spacecraft and enter an operational rationale.",
  invalid_datetime: "Enter valid UTC start and end times.",
  invalid_number: "Use positive whole numbers for outcome amounts and a nonnegative separation.",
  spacecraft_unavailable: "Choose a spacecraft that still belongs to this mission.",
  forbidden: "Declaration authority is unavailable for this mission.",
  text_too_long: "Shorten the contact intent or rationale.",
  conflicting_constraints: "A provider or station cannot be both allowed and excluded.",
  horizon_order: "Set an end time after the start time.",
  duration_order: "Preferred duration must be at least the minimum duration.",
  duration_required: "Enter a minimum duration for this outcome.",
  volume_required: "Enter a minimum data volume for this outcome.",
  invalid_input: "Review the declaration fields and try again.",
  invalid_requirement:
    "The declaration is invalid. Check its spacecraft, outcome, horizon and constraints.",
  invalid_page: "The spacecraft page could not be loaded.",
} as const;
export const declarationFeedbackText = (codes: string[]) =>
  codes.map((c) => declarationFeedback[c as keyof typeof declarationFeedback]).join(" ");
const feedback = (v: any): v is string[] =>
  Array.isArray(v) &&
  v.length <= 8 &&
  v.every((c) => typeof c === "string" && Object.hasOwn(declarationFeedback, c));
export function admitDeclarationValues(v: any): v is ContactRequirementValues {
  return (
    record(v) &&
    Object.keys(v).length === declarationFields.length &&
    declarationFields.every((k) => safeText(v[k], 4096))
  );
}
export function admitSpacecraftChoices(v: any): v is SpacecraftChoices {
  return (
    record(v) &&
    positive(v.page) &&
    v.page <= 1000000 &&
    natural(v.total) &&
    Array.isArray(v.entries) &&
    v.entries.length <= 25 &&
    v.entries.length === Math.min(25, Math.max(0, v.total - (v.page - 1) * 25)) &&
    v.entries.every((e: any) => record(e) && safeId(e.id) && safeText(e.name)) &&
    new Set(v.entries.map((e: any) => e.id)).size === v.entries.length
  );
}
export function admitDeclarationModel(
  v: any,
  context?: Partial<DeclarationContext>,
  horizon?: DeclarationModel["horizon"],
): v is DeclarationModel {
  return (
    record(v) &&
    v.contract_version === 1 &&
    record(v.context) &&
    ["organization_id", "mission_id", "actor_id"].every((k) => safeId(v.context[k])) &&
    (!context || Object.entries(context).every(([k, value]) => v.context[k] === value)) &&
    record(v.horizon) &&
    validTime(v.horizon.earliest_start) &&
    validTime(v.horizon.latest_end) &&
    Date.parse(v.horizon.earliest_start) < Date.parse(v.horizon.latest_end) &&
    (!horizon || requirementDataEqual(horizon, v.horizon)) &&
    admitSpacecraftChoices(v.spacecraft) &&
    v.can_declare === v.spacecraft.total > 0
  );
}
export function admitDeclarationOperation(
  v: any,
  c: DeclarationContext,
): DeclarationOperation | null {
  if (
    !record(v) ||
    !positive(v.sequence) ||
    v.sequence > 1000000 ||
    !["validate", "save", "spacecraft-page"].includes(v.action) ||
    !record(v.input) ||
    !["completed", "rejected", "unconfirmed"].includes(v.status)
  )
    return null;
  if (v.action === "spacecraft-page") {
    if (Object.keys(v.input).length !== 1 || !positive(v.input.page) || v.input.page > 1000000)
      return null;
  } else if (
    Object.keys(v.input).length !== 1 ||
    !admitDeclarationValues(v.input.contact_requirement)
  )
    return null;
  if (v.status !== "completed")
    return v.receipt === null && (v.status !== "rejected" || feedback(v.feedback))
      ? (v as DeclarationOperation)
      : null;
  const receipt = v.receipt;
  if (
    !record(receipt) ||
    !safeId(receipt.receiptId) ||
    !validTime(receipt.completedAt) ||
    !record(receipt.result)
  )
    return null;
  const r = receipt.result;
  if (v.action === "validate")
    return typeof r.valid === "boolean" &&
      feedback(r.feedback) &&
      (r.valid ? r.feedback.length === 0 : r.feedback.length > 0)
      ? (v as DeclarationOperation)
      : null;
  if (v.action === "spacecraft-page")
    return admitSpacecraftChoices(r.spacecraft) && r.spacecraft.page === v.input.page
      ? (v as DeclarationOperation)
      : null;
  return r.contract_version === 1 &&
    Object.entries(c).every(([k, value]) => r[k] === value) &&
    safeId(r.requirement_id) &&
    r.requirement_version === 1 &&
    typeof r.content_sha256 === "string" &&
    /^[a-f0-9]{64}$/.test(r.content_sha256)
    ? (v as DeclarationOperation)
    : null;
}
export function admitDeclarationPage(
  input: unknown,
  context?: Partial<DeclarationContext>,
  horizon?: DeclarationModel["horizon"],
): DeclarationPage | null {
  try {
    const s = JSON.stringify(input);
    if (new TextEncoder().encode(s).length > 131072) return null;
    const v = JSON.parse(s);
    if (
      !record(v) ||
      !admitDeclarationModel(v.model, context, horizon) ||
      !natural(v.sequence) ||
      v.sequence > 1000000
    )
      return null;
    if (v.operation === null) return v.sequence === 0 ? (v as DeclarationPage) : null;
    const op = admitDeclarationOperation(v.operation, v.model.context);
    return op && op.sequence === v.sequence
      ? { model: v.model, sequence: v.sequence, operation: op }
      : null;
  } catch {
    return null;
  }
}
export function declarationDefaults(m: DeclarationModel): ContactRequirementValues {
  return {
    spacecraft_id: m.spacecraft.entries[0]?.id ?? "",
    contact_intent: "payload_downlink",
    earliest_start: m.horizon.earliest_start.replace(/Z$/, ""),
    latest_end: m.horizon.latest_end.replace(/Z$/, ""),
    success_measure: "minimum_data_volume",
    minimum_duration_seconds: "600",
    preferred_duration_seconds: "900",
    minimum_data_volume_bytes: "1000000000",
    contact_count: "1",
    minimum_separation_seconds: "0",
    priority: "high",
    allowed_providers: "",
    excluded_providers: "",
    allowed_stations: "",
    excluded_stations: "",
    rationale: "",
  };
}
export const declarationResultHref = (m: DeclarationModel, op: DeclarationOperation) =>
  `/missions/${requirementSegment(m.context.mission_id)}/ops/requirements/${requirementSegment(op.receipt!.result.requirement_id)}`;
