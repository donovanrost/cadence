defmodule CadenceWeb.Console.Problem do
  @moduledoc """
  The console API error envelope: `{"error": {"code", "message", "details"?}}`.

  Codes are stable snake_case strings the SPA can switch on; messages are
  human-readable and may change.
  """

  import Plug.Conn

  @known %{
    unauthenticated: {401, "Sign in to continue."},
    invalid_csrf: {403, "The request CSRF token is invalid. Reload the page and try again."},
    forbidden: {403, "You do not have permission to do that."},
    scope_mismatch: {403, "That resource belongs to a different organization."},
    not_found: {404, "Not found."},
    mission_not_found: {404, "Mission not found."},
    organization_not_found: {404, "Organization not found."},
    spacecraft_not_found: {404, "Spacecraft not found."},
    profile_not_found: {404, "Profile not found."},
    catalog_revision_not_found: {404, "Catalog revision not found."},
    transport_not_found: {404, "Transport not found."},
    plan_not_found: {404, "Contact plan not found."},
    draft_not_found: {404, "Draft not found."},
    command_draft_not_found: {404, "You have no saved draft for this mission."},
    command_draft_changed: {409, "Your draft was saved from another tab. Reload it to continue."},
    draft_not_interrupted: {409, "The draft isn't interrupted; there is nothing to continue."},
    planning_not_set_up: {422, "Contact planning isn't set up for this mission."},
    horizon_exceeds_policy: {422, "The day is longer than the planning policy allows."},
    inputs_changed: {409, "Planning inputs changed while starting; try again."},
    draft_failed: {422, "The draft could not be started."},
    plan_not_ready: {422, "The plan has unmet requirements or conflicts."},
    plan_superseded:
      {409, "Newer requirement or template versions overtook this draft. Draft the day again."},
    acknowledgements_required: {422, "Acknowledge every unmet requirement to approve."},
    plan_changed: {409, "The plan changed since you loaded it."},
    plan_not_submittable: {409, "The plan can't be submitted in its current state."},
    plan_not_resumable: {409, "The plan isn't waiting to execute."},
    plan_not_pending: {409, "The plan isn't waiting for approval."},
    contact_plan_version_already_decided:
      {422, "This version was already decided. Reload to see it."},
    booking_not_found: {404, "That pass isn't a booking of this plan."},
    booking_not_unconfirmed:
      {409, "That booking isn't waiting on the provider past the confirmation window."},
    booking_already_resolved: {409, "Someone already resolved that booking."},
    plan_not_editable: {422, "The plan can't be edited like that."},
    version_conflict: {409, "The policy changed since you loaded it."},
    reviewer_is_author: {409, "You can't approve a version you saved."},
    policy_not_found: {404, "Policy or version not found."},
    template_not_found: {404, "Template not found."},
    requirement_not_found: {404, "Contact requirement not found."},
    requirement_not_active: {409, "That requirement is closed or canceled, so it can't change."},
    app_not_found: {404, "App not found."},
    settings_section_not_found: {404, "Settings section not found."},
    provider_account_not_found: {404, "Provider account not found."},
    provider_adapter_not_found: {404, "Provider adapter not found."},
    in_use: {409, "Missions still use this. Move them to another account first."},
    already_retired: {409, "This account was already removed."},
    settings_enforced_by_organization:
      {409, "The organization doesn't let missions change this setting."},
    app_action_failed: {422, "The app change was refused."},
    template_rejected: {422, "The template change was refused."},
    requirement_rejected: {422, "The requirement change was refused."},
    policy_rejected: {422, "The policy change was refused."},
    plan_not_repairable:
      {409,
       "This plan can't be re-planned (it must come from a draft and be executing, partially reserved or failed)."},
    operation_conflict: {409, "That operation id was already used for another plan."},
    import_run_not_found: {404, "Import run not found."},
    command_not_found: {404, "Command not found."},
    episode_not_found: {404, "Alarm not found."},
    attention_item_not_found: {404, "That attention item wasn't found."},
    pass_not_found: {404, "Pass not found."},
    pass_changed: {409, "The booking changed since you loaded it."},
    pass_not_releasable: {409, "That booking can't be released."},
    provider_cancel_failed: {502, "The provider didn't confirm the cancel."},
    uplink_not_blocked: {409, "The uplink on that pass isn't blocked."},
    uplink_recovery_refused: {409, "Recovery was refused."},
    attention_item_not_open: {409, "That attention item was already resolved."},
    retry_not_manual:
      {409, "Cadence is already retrying this; there is nothing to retry by hand."},
    actor_not_assignable: {422, "The actor is always the signed-in user."},
    holds_unacknowledged:
      {422,
       "Some preflight HOLDs aren't acknowledged or cleared. Re-run preflight and resolve them."},
    episode_cleared: {409, "That alarm has already cleared."},
    note_required: {422, "A note is required."},
    assignee_not_member: {422, "That person isn't a member of this organization."},
    unsupported_format: {422, "That file format isn't supported."},
    file_too_large: {413, "The file is larger than 50 MiB."},
    import_failed: {422, "The import could not be started."},
    already_member: {409, "That person is already a member."},
    already_invited: {409, "That person already has a pending invitation."},
    member_not_found: {404, "That person isn't a member of this organization."},
    invitation_not_found: {404, "That invitation isn't pending (accepted, revoked or expired)."},
    service_identity_not_found: {404, "That service identity isn't active in this organization."},
    current_password_incorrect: {422, "The current password isn't right."},
    too_many_attempts: {429, "Too many wrong passwords. Wait, then try again."},
    password_managed_externally:
      {409, "This account's password is set by the environment and can't be changed here."},
    session_not_found: {404, "That session isn't yours or has already ended."},
    last_admin:
      {409, "An organization needs at least one admin. Make someone else an admin first."},
    invalid_params: {422, "The request parameters are invalid."},
    history_unavailable: {503, "Telemetry history is unavailable right now."},
    catalog_unavailable: {503, "The command catalog is unavailable right now."},
    alarms_unavailable: {503, "Alarms are unavailable right now."},
    commanding_unavailable: {503, "Commanding is unavailable right now."},
    command_group_not_found: {404, "Command group not found."},
    duplicate_operation: {409, "That operation was already submitted."},
    preflight_stale: {409, "Something changed since the preflight. Run it again."},
    preflight_no_go: {422, "The preflight has NO-GO checks."},
    command_group_too_large: {422, "The group is larger than allowed."},
    command_catalog_not_active: {409, "There is no active command catalog."},
    title_required: {422, "A title is required."},
    log_entry_required: {422, "A log entry is required when a second GO is needed."},
    command_group_not_pending: {409, "That group isn't waiting for a decision."},
    command_group_self_approval_not_allowed: {403, "You can't approve your own request."},
    not_the_requested_approver: {403, "The requester asked another operator for the GO."},
    command_group_review_stale: {409, "The group changed since you opened it. Reload it."},
    command_group_basis_changed:
      {409, "The command catalog changed since this was submitted. It must be resubmitted."},
    exclusions_required: {422, "Name the targets to exclude."},
    unknown_excluded_target: {422, "An excluded target isn't in this group."},
    invalid_decision: {422, "That decision isn't valid."},
    command_group_not_abortable: {409, "That group can't be aborted any more."},
    reason_required: {422, "A reason is required."},
    command_request_already_started: {409, "That command has already started."},
    command_request_not_found: {404, "Command request not found."},
    encode_unavailable:
      {409, "These bytes can't be shown: the request's catalog revision isn't the active one."},
    station_not_found: {404, "Ground station not found."},
    window_not_found: {404, "Availability window not found."},
    window_overlaps: {409, "That window overlaps another of the same kind at this station."},
    window_cleared: {409, "That window is already cleared."},
    invalid_window: {422, "The window is invalid (kind, start, or end before start)."}
  }

  @doc "Sends the error envelope for a known reason atom and halts."
  @spec respond(Plug.Conn.t(), atom(), map() | nil) :: Plug.Conn.t()
  def respond(conn, reason, details \\ nil) when is_atom(reason) do
    {status, code, message} = describe(reason)

    conn
    |> put_status(status)
    |> Phoenix.Controller.json(body(code, message, details))
    |> halt()
  end

  @doc "Returns `{status, code, message}` for a reason; unknown reasons are 422."
  @spec describe(atom()) :: {pos_integer(), binary(), binary()}
  def describe(reason) when is_atom(reason) do
    case Map.fetch(@known, reason) do
      {:ok, {status, message}} -> {status, Atom.to_string(reason), message}
      :error -> {422, Atom.to_string(reason), "The request could not be completed."}
    end
  end

  @spec body(binary(), binary(), map() | nil) :: map()
  def body(code, message, nil), do: %{error: %{code: code, message: message}}

  def body(code, message, details),
    do: %{error: %{code: code, message: message, details: details}}
end
