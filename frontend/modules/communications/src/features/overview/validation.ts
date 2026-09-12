import { COMMS_OVERVIEW_QUERY_VERSION } from "./contracts.ts";
import type {
  PresentationAttrs,
  TextPresentation,
  Status,
  EmptyState,
  TransportEmptyState,
  TransportRow,
  TransportSummary,
  Finding,
  FindingGroup,
  ValidationSummary,
  CommsOverview,
  CommsOverviewPresentation,
} from "./contracts";

export function unwrapCommsOverviewResponse(value: unknown): CommsOverviewPresentation {
  if (
    !isRecord(value) ||
    value.queryVersion !== COMMS_OVERVIEW_QUERY_VERSION ||
    !isCommsOverviewPresentation(value.presentation)
  ) {
    throw new Error("The communications overview response is invalid.");
  }

  return value.presentation;
}

export function isCommsOverviewPresentation(value: unknown): value is CommsOverviewPresentation {
  if (!isRecord(value) || !validPresentationAttrs(value.root) || !isRecord(value.header)) {
    return false;
  }

  return (
    validAttrs(value.header.attrs) &&
    validPresentationAttrs(value.header.body) &&
    validPresentationAttrs(value.header.content) &&
    validTextPresentation(value.header.eyebrow) &&
    validTextPresentation(value.header.title) &&
    validTextPresentation(value.header.title_suffix) &&
    validOverview(value.overview)
  );
}

function validOverview(value: unknown): value is CommsOverview {
  return (
    isRecord(value) &&
    validTransportSummary(value.transport) &&
    validValidationSummary(value.validation)
  );
}

function validTransportSummary(value: unknown): value is TransportSummary {
  return (
    isRecord(value) &&
    nonEmptyString(value.id) &&
    nonEmptyString(value.eyebrow) &&
    nonNegativeInteger(value.count) &&
    typeof value.count_label === "string" &&
    typeof value.description === "string" &&
    validStatus(value.status) &&
    typeof value.empty === "boolean" &&
    validTransportEmptyState(value.empty_state) &&
    Array.isArray(value.rows) &&
    value.rows.length <= 100 &&
    value.rows.every(validTransportRow) &&
    nonEmptyString(value.manage_label) &&
    nonEmptyString(value.manage_href) &&
    nonEmptyString(value.add_label) &&
    nonEmptyString(value.add_href) &&
    value.empty === (value.rows.length === 0)
  );
}

function validTransportEmptyState(value: unknown): value is TransportEmptyState {
  return (
    isRecord(value) &&
    validEmptyState(value) &&
    nonEmptyString(value.action_label) &&
    nonEmptyString(value.action_href)
  );
}

function validTransportRow(value: unknown): value is TransportRow {
  return (
    isRecord(value) &&
    nonEmptyString(value.id) &&
    nonEmptyString(value.display_name) &&
    typeof value.metadata === "string" &&
    nonEmptyString(value.href)
  );
}

function validValidationSummary(value: unknown): value is ValidationSummary {
  return (
    isRecord(value) &&
    nonEmptyString(value.id) &&
    nonEmptyString(value.eyebrow) &&
    nonEmptyString(value.title) &&
    typeof value.description === "string" &&
    validStatus(value.status) &&
    typeof value.empty === "boolean" &&
    validEmptyState(value.empty_state) &&
    nonEmptyString(value.findings_id) &&
    Array.isArray(value.finding_groups) &&
    value.finding_groups.length <= 20 &&
    value.finding_groups.every(validFindingGroup) &&
    value.empty === (value.finding_groups.length === 0)
  );
}

function validEmptyState(value: unknown): value is EmptyState {
  return isRecord(value) && nonEmptyString(value.title) && typeof value.description === "string";
}

function validFindingGroup(value: unknown): value is FindingGroup {
  return (
    isRecord(value) &&
    nonEmptyString(value.id) &&
    nonEmptyString(value.title) &&
    typeof value.description === "string" &&
    Array.isArray(value.findings) &&
    value.findings.length <= 20 &&
    value.findings.every(validFinding)
  );
}

function validFinding(value: unknown): value is Finding {
  return (
    isRecord(value) &&
    (value.id === null || nonEmptyString(value.id)) &&
    nonEmptyString(value.title) &&
    typeof value.body === "string" &&
    (value.action_label === undefined ||
      value.action_label === null ||
      typeof value.action_label === "string") &&
    (value.action_href === undefined ||
      value.action_href === null ||
      typeof value.action_href === "string") &&
    validStatus(value.status)
  );
}

function validStatus(value: unknown): value is Status {
  return (
    isRecord(value) &&
    (value.tone === "ready" ||
      value.tone === "attention" ||
      value.tone === "blocked" ||
      value.tone === "info") &&
    nonEmptyString(value.label)
  );
}

function validTextPresentation(value: unknown): value is TextPresentation {
  return isRecord(value) && validAttrs(value.attrs) && typeof value.text === "string";
}

function validPresentationAttrs(value: unknown): value is PresentationAttrs {
  return isRecord(value) && validAttrs(value.attrs);
}

function validAttrs(value: unknown): value is Record<string, string> {
  return (
    isRecord(value) &&
    Object.keys(value).length <= 32 &&
    Object.entries(value).every(
      ([key, attribute]) =>
        (["id", "class", "role"].includes(key) || /^aria-[a-z-]+$/.test(key)) &&
        typeof attribute === "string" &&
        attribute.length <= 4096,
    )
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.length <= 4096 && value.trim().length > 0;
}

function nonNegativeInteger(value: unknown): value is number {
  return Number.isInteger(value) && Number(value) >= 0;
}
