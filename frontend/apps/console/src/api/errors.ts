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
  // #233 (api): who may change a mission or organization approval setting (ux U96 words).
  "approval_policy_change_requires_organization_admin",
  "approval_policy_change_requires_mission_admin",
  // Missions, spacecraft, setup
  "mission_not_found",
  "spacecraft_not_found",
  // (B) configuration workspace reads (api, ux U94): the snapshot and the packet choices.
  "spacecraft_source_limit_exceeded",
  "spacecraft_catalog_unavailable",
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
  "preview_failed",
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
  // #90 / U53 (api-ops 65f66a88e): a platform-wide binding's switch
  "blast_radius_changed",
  "binding_not_shared",
  "blast_radius_unavailable",
  // api-ops: a platform-wide binding can only read from a platform-shared source.
  "platform_target_required",
  // Providers and provider accounts (L12, L13)
  "provider_not_found",
  "grant_revoked",
  "grant_already_revoked",
  "account_changed",
  "account_archived",
  "credential_changed",
  "credential_already_revoked",
  "account_grant_not_found",
  // App activations (L10)
  "self_approval_forbidden",
  // #275: the console's activation code (as contact_plan_ and mission_model_), beside the old one.
  "activation_self_approval_forbidden",
  "not_requester",
  "share_not_active",
  "not_pending",
  "nothing_to_resume",
  "not_resumable",
  "activation_policy_changed",
  // U95 (domain's approve preflight a87fe44f6, api): approve refused, nothing recorded.
  "approved_activation_content_mismatch",
  "change_set_activation_stale",
  "mission_model_activation_manifest_required",
  "spacecraft_configuration_review_stale",
  "mission_model_comparison_report_required",
  // U95 additions (api b417a5757 with domain's R1).
  "spacecraft_configuration_review_required",
  "spacecraft_model_not_active",
  "activation_execution_in_progress",
  "activation_request_not_found",
  "app_not_found",
  "application_not_found",
  "application_not_installed",
  "application_unavailable",
  "surface_not_found",
  "host_session_mismatch",
  // U63 (api 396c59fd5): an apply refused per spacecraft; the message names them (ux's words).
  "telemetry_app_not_installed",
  "telemetry_packet_inputs_required",
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
  // U92 (api-ops' P0 fix 02901b298): GO refused, the group's members changed after submit.
  "command_group_members_changed",
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
  // U84 replay_conflict acknowledge: the note is over 500 characters, or not text.
  "invalid_note",
  "title_required",
  "uplink_not_blocked",
  "uplink_recovering",
  "uplink_recovery_refused",
  // U46 named release (api, DECISIONS #84): whole-request refusals before anything went out.
  "command_window_closed",
  "unbooked_contact_unconfirmed",
  "realized_contact_not_found",
  "realized_contact_not_releasable",
  // Alarms, attention
  "alarms_unavailable",
  "episode_not_found",
  "episode_cleared",
  "actor_not_assignable",
  "assignee_not_member",
  "attention_item_not_found",
  "attention_item_not_open",
  // §11 L14 provider-change decisions (api 30b3f60b9).
  "provider_change_stale",
  "provider_change_deadline_passed",
  // L14 flown passes: a pending change whose pass has ended can't be decided.
  "provider_change_expired",
  "retry_not_manual",
  "history_unavailable",
  // Contacts, planning, bookings
  "pass_not_found",
  // A13 contact record read (api 42e3b9550): no contact with this id.
  "contact_not_found",
  // U55 (api): Cadence's side of a scheduled contact can't be canceled or ended now.
  "contact_not_cancelable",
  "contact_not_live",
  "no_scheduled_contact",
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
  // U52 (api 6af9e279d): a start's template fan-out over the limit; details {count, limit}.
  "fleet_planning_occurrence_limit_exceeded",
  "fleet_repair_horizon_exceeded",
  // U76 (api 1a5976482): POST …/repairs with no attempts left, or a window it can't use.
  "fleet_repair_attempt_limit_exceeded",
  "fleet_repair_horizon_invalid",
  "plan_not_found",
  "plan_changed",
  "plan_not_editable",
  "plan_not_pending",
  // #257 (api): submit on a plan already waiting; approve by its submitter or drafter (independent).
  "plan_already_submitted",
  "contact_plan_self_approval_forbidden",
  // #277: a service identity made a version since the last approval and no one is accountable for it.
  "contact_plan_approver_authors_unknown",
  "plan_not_ready",
  "plan_not_repairable",
  "plan_not_resumable",
  // #268: execute once the plan's day has ended (nothing started).
  "contact_plan_day_ended",
  "plan_not_submittable",
  "plan_superseded",
  "draft_not_found",
  "draft_not_interrupted",
  "contact_plan_version_already_decided",
  // U61 day-plan lifecycle (api): another plan covers the day; a newer plan replaced this one
  // (not U27's plan_superseded); every pass's booking window had closed (#273).
  "contact_plan_day_already_planned",
  "contact_plan_replaced",
  "contact_plan_all_opportunities_expired",
  // #273 (api): the closed set changed since the approver looked; step 1's interim refusal.
  "contact_plan_expired_passes_changed",
  "contact_plan_opportunity_expired",
  "template_not_found",
  "requirement_not_found",
  "requirement_not_active",
  "requirement_rejected",
  "template_transition_not_allowed",
  "policy_changed",
  "grant_changed",
  // #283 (ux U105): automation grant proposals, decisions and tightenings.
  "automation_grant_self_approval_forbidden",
  "automation_grant_approver_authors_unknown",
  "automation_grant_not_proposed",
  "approval_policy_changed",
  "automation_grant_not_active",
  "automation_grant_not_narrower",
  "automation_grant_narrow_unchanged",
  "automation_grant_legacy",
  "automation_grant_capability_required",
  "authenticated_user_required",
  // #499 (U105 Suspended): resume refused, the grant isn't suspended (or it expired).
  "automation_grant_not_suspended",
  // Model approval gate (ux U65, domain 742567770)
  "human_mission_model_approver_required",
  "mission_model_self_approval_forbidden",
  // U88 (domain's orphan guard, 11-18): approve refused, no catalog revision names it.
  "mission_model_revision_not_in_catalog",
  "mission_model_comparison_not_passed",
  "mission_model_comparison_mismatch",
  "mission_model_runtime_plans_not_ready",
  "mission_model_revision_not_approvable",
  "mission_model_revision_not_found",
  "mission_model_comparison_report_not_found",
  "mission_model_decision_reason_required",
  "mission_model_decision_reason_too_long",
  "mission_model_revision_not_approved",
  "mission_model_comparison_failed",
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
  "snapshot_deleted",
  "playlist_not_found",
  // TEMPORARY, deleted with 9ac6dc8ee: the legacy route conversion (api v3.2; ux U79).
  "conversion_already_staged",
  "path_already_staged",
  // #499 (api): tightening approval would suspend automation grants; details {grants, digest}.
  "approval_tightening_suspends_grants",
  // #534 (mms-engineer, #548/#549): a packet definition version race; retryable, nothing written.
  "packet_definition_version_taken",
  // Change-set apply refusals (api changes.md § Errors), worded per code by #310 (ca-ux, U79).
  "change_set_changed",
  "checks_failed",
  "holds_not_acknowledged",
  "nothing_staged",
  "invalid_op",
  "open_change_set_not_empty",
  "nothing_to_convert",
  "conversion_in_progress",
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

/**
 * A code from something that isn't an ApiError (the plugin host bridge's HostBridgeError), checked
 * against the known vocabulary like isError.
 */
export const hasErrorCode = (code: string | null | undefined, expected: ErrorCode): boolean =>
  code === expected;

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
