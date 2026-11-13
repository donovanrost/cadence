import { decode, type Reader } from "./decode.ts";
import type { ApiError } from "./http.ts";
import { isRecord } from "./json.ts";

/**
 * The server's error codes the console handles (typing plan §12 A2): taken from the contracts in
 * docs/apogee/api plus codes the console already branches on. `isError(e, "version_conlfict")`
 * is a compile error, so a typo or a server rename can no longer silently drop a recovery path.
 * Add a code here when a contract adds one.
 */
export const errorCodes = [
  // Generic
  "unauthenticated",
  "forbidden",
  "not_found",
  "invalid_params",
  "invalid_csrf",
  "version_conflict",
  "duplicate_operation",
  "operation_conflict",
  "in_use",
  "session_changed",
  // Auth, account, people
  "credentials_incorrect",
  "password_incorrect",
  "current_password_incorrect",
  "password_managed_externally",
  "too_many_attempts",
  "account_disabled",
  "session_not_found",
  "already_invited",
  "already_member",
  "member_not_found",
  "organization_not_found",
  "invitation_not_found",
  "invitation_not_pending",
  "invitation_unavailable",
  "invitation_case_changed",
  "invitation_for_another_account",
  "service_identity_not_found",
  "settings_enforced_by_organization",
  // Missions, spacecraft, setup
  "mission_not_found",
  "spacecraft_not_found",
  "profile_not_found",
  "station_not_found",
  "transport_not_found",
  "provider_account_not_found",
  "provider_adapter_not_found",
  "change_set_open",
  "holds_blocking",
  "holds_unacknowledged",
  "acknowledgements_required",
  "apply_interrupted",
  "invalid_rollback_target",
  "nothing_to_roll_back",
  "rollback_crosses_legacy",
  "rollback_in_progress",
  "reserved_metadata_key",
  "catalog_revision_not_found",
  "catalog_unavailable",
  "catalog_command_in_flight",
  "import_run_not_found",
  "unsupported_format",
  "artifact_not_found",
  "import_running",
  // Data sources (L11, api-ops)
  "data_source_not_found",
  "binding_not_found",
  "run_not_found",
  "data_source_state",
  "binding_changed",
  "platform_source",
  // Providers and provider accounts (L12, L13)
  "provider_not_found",
  "grant_revoked",
  "grant_already_revoked",
  "account_changed",
  "account_archived",
  "credential_changed",
  "credential_already_revoked",
  "app_not_found",
  "application_not_found",
  "application_not_installed",
  "application_unavailable",
  "surface_not_found",
  "host_session_mismatch",
  // Commanding
  "command_catalog_not_active",
  "command_not_found",
  "command_draft_not_found",
  "command_draft_changed",
  "command_group_not_found",
  "command_group_not_pending",
  "command_group_not_abortable",
  "command_group_basis_changed",
  "command_group_review_stale",
  "command_group_self_approval_not_allowed",
  "command_group_too_large",
  "command_request_not_found",
  "command_request_already_started",
  "not_the_requested_approver",
  "reviewer_is_author",
  "preflight_no_go",
  "preflight_stale",
  "encode_unavailable",
  "exclusions_required",
  "unknown_excluded_target",
  "inputs_changed",
  "log_entry_required",
  "note_required",
  "reason_required",
  "title_required",
  "uplink_not_blocked",
  "uplink_recovering",
  "uplink_recovery_refused",
  // Alarms, attention
  "alarms_unavailable",
  "episode_not_found",
  "episode_cleared",
  "actor_not_assignable",
  "assignee_not_member",
  "attention_item_not_found",
  "attention_item_not_open",
  "retry_not_manual",
  "history_unavailable",
  // Contacts, planning, bookings
  "pass_not_found",
  "pass_changed",
  "pass_not_releasable",
  "provider_cancel_failed",
  "booking_not_found",
  "booking_not_unconfirmed",
  "booking_already_resolved",
  "booking_changed",
  "not_cancellable",
  "route_not_ready",
  "route_changed",
  "opportunity_expired",
  "token_invalid",
  "search_unavailable",
  "window_overlaps",
  "horizon_exceeds_policy",
  "planning_not_set_up",
  "fleet_planning_requirement_not_active",
  "fleet_repair_horizon_exceeded",
  "plan_not_found",
  "plan_changed",
  "plan_not_editable",
  "plan_not_pending",
  "plan_not_ready",
  "plan_not_repairable",
  "plan_not_resumable",
  "plan_not_submittable",
  "plan_superseded",
  "draft_not_found",
  "draft_not_interrupted",
  "contact_plan_version_already_decided",
  "template_not_found",
  "requirement_not_found",
  "requirement_not_active",
  "requirement_rejected",
  "template_transition_not_allowed",
  "policy_changed",
  "grant_changed",
  // Dashboards
  "dashboard_unavailable",
  "dashboard_not_ready",
  "dashboard_in_use",
  "invalid_command",
  "too_many_commands",
  "already_retired",
  "library_item_changed",
  "library_item_in_use",
  "share_expired",
  "share_revoked",
] as const;
export type ErrorCode = (typeof errorCodes)[number];

/** The code of a refusal (4xx) or of a server error envelope (5xx `serverCode`), else null. */
export function codeOf(error: ApiError | null | undefined): string | null {
  if (!error) return null;
  if ("code" in error) return error.code;
  return error.kind === "unavailable" ? (error.serverCode ?? null) : null;
}

/** The refusal's code when it's one the console knows, for code-keyed message maps; else null. */
export function knownErrorCode(error: ApiError | null | undefined): ErrorCode | null {
  const code = codeOf(error);
  return errorCodes.find((candidate) => candidate === code) ?? null;
}

/** True when the server refused with `code`, which must be a known error code. */
export function isError(error: ApiError | null | undefined, code: ErrorCode): boolean {
  return codeOf(error) === code;
}

/** The refusal's `details`, decoded with `read`; null when absent or not that shape. */
export function detailsOf<T>(error: ApiError | null | undefined, read: Reader<T>): T | null {
  if (!error || !("details" in error) || error.details === undefined) return null;
  const decoded = decode(read, error.details);
  return decoded.ok ? decoded.value : null;
}

/**
 * Per-field messages from a 422 `invalid_params` (details keyed by field path; each a sentence
 * or a list of sentences), the one implementation the forms share. `rename` maps a server path
 * to the form's key (e.g. strip a `settings.` prefix).
 */
export function fieldErrors(
  error: ApiError | null | undefined,
  rename: (path: string) => string = (path) => path,
): Record<string, string> {
  if (!error || error.kind !== "invalid" || !isRecord(error.details)) return {};
  const out: Record<string, string> = {};
  for (const [path, value] of Object.entries(error.details)) {
    const text = Array.isArray(value)
      ? value.filter((v): v is string => typeof v === "string").join(" ")
      : value;
    if (typeof text === "string" && text) out[rename(path)] = text;
  }
  return out;
}
