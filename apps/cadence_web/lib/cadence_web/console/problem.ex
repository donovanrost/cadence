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
    transport_not_found: {404, "Transport not found."},
    plan_not_found: {404, "Contact plan not found."},
    draft_not_found: {404, "Draft not found."},
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
    plan_not_editable: {422, "The plan can't be edited like that."},
    version_conflict: {409, "The policy changed since you loaded it."},
    reviewer_is_author: {409, "You can't approve a version you saved."},
    policy_not_found: {404, "Policy or version not found."},
    template_not_found: {404, "Template not found."},
    template_rejected: {422, "The template change was refused."},
    policy_rejected: {422, "The policy change was refused."},
    plan_not_repairable:
      {409,
       "This plan can't be re-planned (it must come from a draft and be executing, partially reserved or failed)."},
    operation_conflict: {409, "That operation id was already used for another plan."},
    import_run_not_found: {404, "Import run not found."},
    command_not_found: {404, "Command not found."},
    episode_not_found: {404, "Alarm not found."},
    episode_cleared: {409, "That alarm has already cleared."},
    note_required: {422, "A note is required."},
    assignee_not_member: {422, "That person isn't a member of this organization."},
    unsupported_format: {422, "That file format isn't supported."},
    file_too_large: {413, "The file is larger than 50 MiB."},
    import_failed: {422, "The import could not be started."},
    already_member: {409, "That person is already a member."},
    already_invited: {409, "That person already has a pending invitation."},
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
