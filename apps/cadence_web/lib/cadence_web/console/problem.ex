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
    spacecraft_route_not_found: {404, "Extra route not found."},
    profile_not_found: {404, "Profile not found."},
    catalog_revision_not_found: {404, "Catalog revision not found."},
    artifact_not_found: {404, "Source file not found."},
    import_running: {409, "An import of this file is still running."},
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
    # #268: execute after the plan's UTC day has ended; nothing is started.
    contact_plan_day_ended: {409, "This plan's day has ended, so nothing was booked."},
    plan_not_pending: {409, "The plan isn't waiting for approval."},
    # #257: submit only submits; a plan already waiting for approval changes nothing.
    plan_already_submitted: {409, "The plan is already waiting for approval."},
    # #273 step 1 (until domain's rule approves the rest): the approval is refused while any
    # selected pass's booking window has closed; nothing is recorded. ux's words (U97).
    contact_plan_opportunity_expired:
      {409,
       "The booking window has closed for some of this plan's passes, so it can't be approved as it is. Nothing was recorded."},
    contact_plan_self_approval_forbidden:
      {403,
       "You submitted this plan or drafted a version of it since it was last approved, so another org admin approves it."},
    contact_plan_version_already_decided:
      {422, "This version was already decided. Reload to see it."},
    booking_not_found: {404, "That pass isn't a booking of this plan."},
    booking_not_unconfirmed:
      {409, "That booking isn't waiting on the provider past the confirmation window."},
    booking_already_resolved: {409, "Someone already resolved that booking."},
    plan_not_editable: {422, "The plan can't be edited like that."},
    # ux 11-14: generic (eight writes share it); a context may override with its own noun.
    version_conflict:
      {409,
       "This changed since you opened it, so your changes weren't saved. Reload to see the current version."},
    reviewer_is_author: {409, "You can't approve a version you saved."},
    policy_not_found: {404, "Policy or version not found."},
    template_not_found: {404, "Template not found."},
    requirement_not_found: {404, "Contact requirement not found."},
    requirement_not_active: {409, "That requirement is closed or canceled, so it can't change."},
    app_not_found: {404, "App not found."},
    application_not_found: {404, "App not found."},
    surface_not_found: {404, "That app has no such screen."},
    application_not_installed: {409, "This app isn't installed here."},
    application_unavailable: {503, "This app can't be loaded right now."},
    settings_section_not_found: {404, "Settings section not found."},
    provider_account_not_found: {404, "Provider account not found."},
    provider_adapter_not_found: {404, "Provider adapter not found."},
    in_use: {409, "Missions still use this. Move them to another account first."},
    account_changed: {409, "This account changed since you loaded it."},
    account_archived: {409, "This account was removed."},
    account_grant_not_found: {404, "Grant not found."},
    grant_already_revoked: {409, "This grant was already revoked."},
    credential_changed: {409, "The credential changed since you loaded it."},
    credential_already_revoked: {409, "This credential was already revoked."},
    provider_not_found: {404, "Provider not found."},
    grant_revoked: {409, "That grant was revoked. Ask an organization admin for a new one."},
    already_retired: {409, "This account was already removed."},
    approval_policy_change_requires_organization_admin:
      {403, "Not saved: only an organization admin can change this approval setting."},
    approval_policy_change_requires_mission_admin:
      {403,
       "Not saved: only a mission admin or an organization admin can change approval settings."},
    settings_enforced_by_organization:
      {409, "The organization doesn't let missions change this setting."},
    app_action_failed: {422, "The app change was refused."},
    template_rejected: {422, "The template change was refused."},
    policy_changed:
      {409, "The planning policy changed since you loaded it. Review it, then try again."},
    grant_changed: {409, "This grant changed since you loaded it."},
    grant_not_found: {404, "Automation grant not found."},
    # #283 (ux U105): a grant takes effect only after a second org admin approves it. The
    # console words each from its code and details; these are the server's plain fallbacks.
    automation_grant_self_approval_forbidden:
      {403, "Not approved: another org admin approves this grant. Your approval wasn't recorded."},
    automation_grant_approver_authors_unknown:
      {403,
       "Not approved: the service identity has no one recorded as accountable for it, so its grant can't be approved yet. Your approval wasn't recorded."},
    automation_grant_not_proposed:
      {409, "This grant isn't waiting for approval, so nothing was recorded. Reload to see it."},
    approval_policy_changed:
      {409,
       "Not approved: the mission's approval setting changed after this grant was proposed. Your approval wasn't recorded. It has to be proposed again."},
    automation_grant_not_active: {403, "The grant isn't active."},
    automation_grant_not_narrower:
      {422,
       "Not narrowed: this change gives the service more than it has now, so it needs approval. Propose it as a new grant instead."},
    automation_grant_legacy:
      {409,
       "This grant was issued before two-person approval, so it can only be revoked. Propose a new grant instead."},
    automation_grant_narrow_unchanged:
      {422, "Not narrowed: nothing changed. Choose less than the grant allows now."},
    # #499: resume (ca-ux words the console's lines; these are the server's fallbacks).
    automation_grant_not_suspended:
      {409, "This grant isn't suspended, so there's nothing to resume. Reload to see it."},
    automation_grant_service_has_grant:
      {409,
       "This service already has a grant here. Revoke it, or propose a wider one that replaces it."},
    approval_tightening_unavailable:
      {503,
       "Not saved: Cadence can't check what this change would suspend right now. Try again later."},
    approval_tightening_suspends_grants:
      {409,
       "Not saved: this change suspends automation grants that were approved by one person. Review them and save again to confirm."},
    automation_grant_capability_required:
      {403, "You can't propose or approve a grant for something you can't do yourself."},
    authenticated_user_required:
      {403, "Only a person can do this, not a service identity. Nothing changed."},
    route_changed: {409, "The route to that station changed. Search again."},
    opportunity_expired: {409, "That offer has gone. Search again."},
    token_invalid: {422, "That offer can't be booked. Search again."},
    search_unavailable: {503, "The providers couldn't be searched right now."},
    template_transition_not_allowed:
      {409, "The template can't move to that state from where it is."},
    requirement_rejected: {422, "The requirement change was refused."},
    policy_rejected: {422, "The policy change was refused."},
    # ux U76: a re-plan the planning policy doesn't allow.
    fleet_repair_attempt_limit_exceeded:
      {409, "No re-plan attempts left. The planning policy sets the limit."},
    fleet_repair_horizon_exceeded:
      {422, "That window is longer than the planning policy allows for a re-plan."},
    fleet_repair_horizon_invalid: {422, "Choose a window that ends after it starts."},
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
    contact_start_not_missed:
      {409, "Cadence is still trying to start this pass. Mark it as seen once it's missed."},
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
    invitation_not_pending:
      {409, "That invitation was already answered, revoked or has expired."},
    service_identity_not_found: {404, "That service identity isn't active in this organization."},
    current_password_incorrect: {422, "The current password isn't right."},
    password_incorrect: {422, "That password isn't right."},
    admin_mode_required: {403, "Admin mode has ended. Enter it again to continue."},
    data_source_not_found: {404, "That data source isn't visible to this mission."},
    binding_not_found: {404, "That binding isn't this mission's."},
    binding_changed: {409, "Someone else changed this binding. Reload it."},
    blast_radius_changed:
      {409, "What this switch affects changed while you were confirming. Check it again."},
    binding_not_shared: {409, "That binding is this mission's own; no platform-wide sheet."},
    platform_target_required:
      {422, "A platform-wide binding can only use a platform-shared source."},
    blast_radius_unavailable:
      {503, "Cadence couldn't count what this switch affects, so it won't switch it now."},
    data_source_state: {409, "The data source is already in that state."},
    platform_source: {403, "Shared by the platform. Platform admins change it in admin mode."},
    run_not_found: {404, "That run isn't this mission's."},
    data_source_unavailable: {503, "The data source couldn't be changed right now."},
    credentials_incorrect: {422, "That email and password don't match."},
    account_disabled: {403, "This account is disabled. Ask an administrator to enable it."},
    invitation_unavailable: {409, "This invitation can't be used any more."},
    invitation_for_another_account: {409, "This invitation is for another account."},
    invitation_case_changed: {409, "This invitation changed while you were on it. Reload it."},
    too_many_attempts: {429, "Too many wrong passwords. Wait, then try again."},
    password_managed_externally:
      {409, "This account's password is set by the environment and can't be changed here."},
    session_not_found: {404, "That session isn't yours or has already ended."},
    last_admin:
      {409, "An organization needs at least one admin. Make someone else an admin first."},
    invalid_params: {422, "The request parameters are invalid."},
    history_unavailable: {503, "Telemetry history is unavailable right now."},
    dashboard_unavailable: {503, "This dashboard couldn't be resolved right now."},
    share_not_active: {409, "That share is already revoked or expired."},
    playlist_not_found: {404, "This playlist was deleted."},
    provider_change_stale:
      {409, "The provider changed this booking again. Review the new change."},
    provider_change_deadline_passed: {409, "The deadline to decide this change has passed."},
    provider_change_expired:
      {409, "The pass has ended, so this change can't be decided any more."},
    library_item_not_found: {404, "Library widget not found."},
    library_item_changed: {409, "This library widget changed since you opened it."},
    library_item_in_use: {409, "Dashboards still place this library widget."},
    invalid_command: {422, "One of the edits can't be applied."},
    too_many_commands: {422, "Too many unsaved edits. Save to keep going."},
    dashboard_not_ready: {422, "Some widgets aren't ready to save."},
    dashboard_in_use: {409, "A playlist shows this dashboard. Confirm to archive it anyway."},
    dashboard_id_in_use: {409, "That dashboard id is already in use."},
    dashboard_import_conflict:
      {409, "A dashboard with that id exists here with different content."},
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
    activation_request_not_found: {404, "Activation request not found."},
    configuration_changes_group_not_found:
      {404, "That group of spacecraft isn't in this request."},
    not_pending: {409, "That request has already been decided."},
    activation_approver_authored_content:
      {403,
       "Not approved: you saved part of what this request activates, so another person approves it. Your approval wasn't recorded."},
    not_requester: {403, "Only the person who requested it can withdraw it."},
    activation_policy_changed:
      {409, "The activation policy changed since this was requested. Request it again."},
    nothing_to_resume: {409, "There's nothing to retry."},
    not_resumable: {409, "This can't be retried. Request activation again."},
    activation_execution_in_progress: {409, "It's applying now."},
    command_group_not_pending: {409, "That group isn't waiting for a decision."},
    command_group_self_approval_not_allowed: {403, "You can't approve your own request."},
    not_the_requested_approver: {403, "The requester asked another operator for the GO."},
    command_group_review_stale: {409, "The group changed since you opened it. Reload it."},
    command_group_basis_changed:
      {409, "The command catalog changed since this was submitted. It must be resubmitted."},
    command_group_members_changed:
      {409, "This group's commands changed after it was submitted. It must be resubmitted."},
    exclusions_required: {422, "Name the targets to exclude."},
    unknown_excluded_target: {422, "An excluded target isn't in this group."},
    invalid_decision: {422, "That decision isn't valid."},
    command_group_not_abortable: {409, "That group can't be aborted any more."},
    reason_required: {422, "A reason is required."},
    command_request_already_started: {409, "That command has already started."},
    command_request_not_found: {404, "Command request not found."},
    event_not_found: {404, "Event not found."},
    fleet_planning_occurrence_limit_exceeded:
      {422,
       "This start goes over the limit of template requirements. Include fewer templates, or narrow their targets."},
    # U55: cancel or end a pass's contact (the console words each state itself).
    # U65: the model approval gate (words: ux; codes: domain's).
    human_mission_model_approver_required:
      {403, "Not approved: a person has to approve this, not a service identity."},
    mission_model_self_approval_forbidden:
      {403, "Not approved: you imported this revision, so another org admin has to approve it."},
    mission_model_comparison_not_passed: {409, "Not approved: the comparison didn't pass."},
    mission_model_comparison_mismatch:
      {409, "Not approved: the comparison is out of date. Run it again."},
    mission_model_runtime_plans_not_ready:
      {409, "Not approved: Cadence is still preparing this revision. Try again in a moment."},
    mission_model_revision_not_approvable:
      {409, "Not approved: this revision was already approved, rejected or replaced."},
    mission_model_revision_not_found: {404, "Mission model revision not found."},
    mission_model_comparison_report_not_found: {404, "Comparison report not found."},
    mission_model_decision_reason_required: {422, "Give a reason first."},
    mission_model_decision_reason_too_long: {422, "Keep the reason under 2,000 characters."},
    mission_model_no_active_binding_set:
      {409, "There's no active configuration to compare this revision against."},
    # ux U88 (d9f3c0295): domain's guard; no catalog revision names the model revision.
    mission_model_revision_not_in_catalog:
      {409,
       "Not approved: the catalog doesn't list this revision. To approve it, import its file as a new catalog revision."},
    mission_model_unavailable: {503, "Mission models are unavailable right now."},
    contact_not_cancelable: {409, "This contact can't be canceled now."},
    contact_not_live: {409, "This contact isn't live, so it can't be ended."},
    no_scheduled_contact: {404, "This pass has no contact in Cadence."},
    contacts_unavailable: {503, "Contacts are unavailable right now."},
    # U46 named release (whole-request refusals; ux 11-13 words the console's own lines).
    command_window_closed: {409, "Not released: this contact's command window is closed."},
    unbooked_contact_unconfirmed:
      {409, "This contact isn't a booked pass. Confirm to release into it anyway."},
    realized_contact_not_found: {404, "Contact not found."},
    contact_not_found: {404, "Contact not found."},
    realized_contact_not_releasable: {409, "Not released: the contact has ended."},
    attention_unavailable: {503, "That couldn't be done right now. Try again."},
    encode_unavailable:
      {409, "These bytes can't be shown: the request's catalog revision isn't the active one."},
    station_not_found: {404, "Ground station not found."},
    window_not_found: {404, "Availability window not found."},
    window_overlaps: {409, "That window overlaps another of the same kind at this station."},
    window_cleared: {409, "That window is already cleared."},
    invalid_window: {422, "The window is invalid (kind, start, or end before start)."},
    # (B) a spacecraft's configuration workspace (the host's words; ux re-words).
    spacecraft_configuration_changed:
      {409,
       "This spacecraft changed since you started editing. Compare the latest saved configuration before saving again."},
    spacecraft_configuration_review_stale:
      {409, "The active fleet configuration changed. Review the latest state and submit again."},
    spacecraft_configuration_review_unavailable:
      {409, "Save your current configuration and resolve external changes before submitting it."},
    spacecraft_switch_set_by_change_set:
      {409, "A change set changed Telemetry or Commanding since this was saved. Save it again."},
    spacecraft_catalog_set_by_profile:
      {409, "This spacecraft's catalog is set by its profile, through a change set."},
    spacecraft_catalog_required: {422, "Choose a catalog before submitting this configuration."},
    spacecraft_catalog_unavailable:
      {422, "That catalog revision isn't available on this mission."},
    spacecraft_packet_inputs_required:
      {422, "Connect a packet source and select packets for Telemetry Decom."},
    spacecraft_packet_input_unavailable: {422, "That packet source isn't this spacecraft's."},
    spacecraft_source_limit_exceeded: {422, "Too many packet sources for one spacecraft."},
    mission_model_revision_not_approved:
      {409, "Not applied: the catalog revision isn't approved yet."},
    # #275 (U94, ca-ux's amendment): the requester only; an author gets
    # activation_approver_authored_content (#236).
    # ca-ux on #608: neutral, so it's true with or without via_service; U95's ending.
    activation_self_approval_forbidden:
      {403,
       "Not approved: you, or a service identity you're accountable for, requested this, so another person approves it. Your approval wasn't recorded."},
    # #534 (mms-ux): another generation saved a packet definition under the same version at the
    # same moment; nothing was written, and doing it again re-resolves. Retryable.
    packet_definition_version_taken:
      {409,
       "Not applied: another change saved a packet definition at the same moment, so nothing changed. Try again."},
    # #280 (U100): who made this can't be established; details.service names the service whose
    # accountable people aren't recorded (null when none is involved).
    activation_approver_authors_unknown:
      {403, "Not approved: Cadence can't tell who made this, so this can't be approved yet."},
    contact_plan_approver_authors_unknown:
      {403, "Not approved: Cadence can't tell who made this plan, so this can't be approved yet."},
    mission_model_approver_authors_unknown:
      {403,
       "Not approved: Cadence can't tell who imported this revision, so this can't be approved yet."},
    # #260 (mms-ux): the console names the revision, the decider and the time from the details.
    mission_model_revision_already_approved:
      {409,
       "Not approved: this catalog revision was already approved, so your approval wasn't recorded. Reload to see it."},
    command_group_approver_authors_unknown:
      {403,
       "Not approved: Cadence can't tell who sent this command group, so this can't be approved yet."},
    command_request_approver_authors_unknown:
      {403,
       "Not approved: Cadence can't tell who sent this command request, so this can't be approved yet."}
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
