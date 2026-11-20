defmodule CadenceWeb.Console.ConfigJSON do
  @moduledoc """
  Wire encoding for change sets and configuration revisions (fe-setup's §K):
  the facade shapes with string keys, atoms as lowercase strings, times as
  ISO-8601, and documents/values passed through as JSON. Also maps facade
  error tags to the console error envelope, keeping each tag as its `code`.
  """

  import Plug.Conn

  alias Cadence.Reads.ModelApplyRefusals
  alias Cadence.Reads.TelemetryApplyRefusals
  alias CadenceWeb.Console.Problem

  @status %{
    frozen_in_review: 409,
    change_set_changed: 409,
    path_already_staged: 409,
    reviewer_is_author: 409,
    activation_policy_changed: 409,
    entity_gone: 409,
    invalid_op: 422,
    reason_required: 422,
    comment_required: 422,
    nothing_staged: 422,
    not_in_review: 422,
    checks_failed: 422,
    holds_not_acknowledged: 422,
    holds_blocking: 409,
    catalog_command_in_flight: 409,
    telemetry_app_not_installed: 409,
    telemetry_packet_inputs_required: 409,
    mission_model_revision_not_approved: 409,
    mission_model_comparison_failed: 409,
    invalid_range: 422,
    forbidden: 403,
    change_set_not_found: 404,
    revision_not_found: 404,
    change_not_found: 404,
    op_not_found: 404,
    mission_not_found: 404,
    apply_interrupted: 503,
    # #262: Cadence couldn't run the checks (submit or approve); nothing was applied, retry may work.
    preview_failed: 503,
    invalid_rollback_target: 422,
    nothing_to_roll_back: 422,
    rollback_unknown_kind: 422,
    rollback_crosses_legacy: 409,
    change_set_open: 409,
    rollback_in_progress: 409,
    # U82: an archive refused because the transport or station is still used (stage, submit, review).
    in_use: 409,
    # ux U79 legacy route conversion. TEMPORARY: removed with 9ac6dc8ee.
    conversion_in_progress: 409,
    conversion_already_staged: 409,
    open_change_set_not_empty: 409,
    nothing_to_convert: 422
  }

  @messages %{
    frozen_in_review: "The change set is in review; staging is paused until it is decided.",
    change_set_changed: "The change set changed since you loaded it. Reload and try again.",
    path_already_staged: "Someone else already staged a change to this field.",
    reviewer_is_author: "You can't review a change set you submitted or contributed to.",
    activation_policy_changed: "The approval policy changed; the change set was reopened.",
    entity_gone: "The item no longer exists.",
    invalid_op: "A staged change is invalid.",
    reason_required: "Enter a reason (10 to 2000 characters).",
    comment_required: "Enter a comment.",
    nothing_staged: "Nothing is staged.",
    not_in_review: "The change set isn't in review.",
    checks_failed: "Checks failed; nothing was applied.",
    holds_not_acknowledged: "Acknowledge the holds to apply.",
    holds_blocking:
      "This change can't apply yet: commands in flight or configurations pending block it.",
    catalog_command_in_flight:
      "A command started while applying; nothing was applied. Try again when it finishes.",
    # The apply's own refusals (api-ops 11-15); the preview's blocking hold normally says it first.
    telemetry_app_not_installed: "Not applied: the telemetry app isn't installed.",
    telemetry_packet_inputs_required: "Not applied: telemetry's packet inputs aren't set up.",
    mission_model_revision_not_approved: "Not applied: the catalog revision isn't approved yet.",
    mission_model_comparison_failed:
      "Not applied: the catalog revision's comparison didn't pass.",
    invalid_range: "Choose an older revision first.",
    forbidden: "You do not have permission to do that.",
    change_set_not_found: "Change set not found.",
    revision_not_found: "Revision not found.",
    change_not_found: "Change not found.",
    op_not_found: "Change not found.",
    mission_not_found: "Mission not found.",
    apply_interrupted: "The apply was interrupted and did not take effect. Try again.",
    preview_failed:
      "Cadence couldn't run the checks, so nothing changed. Try again; if it keeps happening, " <>
        "tell the team that runs Cadence for you.",
    invalid_rollback_target: "Choose a revision from r1 up to the one before the current one.",
    nothing_to_roll_back: "Nothing differs from that revision.",
    rollback_unknown_kind: "A revision in that range has changes this version can't undo.",
    rollback_crosses_legacy:
      "The range includes a legacy activation; roll back to it, not past it.",
    change_set_open: "Finish or discard the open change set first.",
    rollback_in_progress:
      "A rollback is staged; apply or discard it before staging other changes.",
    in_use: "It's still in use, so it can't be archived.",
    conversion_in_progress:
      "A route conversion batch is staged, so other changes can't be staged until it's applied or discarded.",
    conversion_already_staged: "A conversion batch is already staged.",
    open_change_set_not_empty:
      "The open change set has other changes; apply or discard them first.",
    nothing_to_convert: "There are no older routes left to convert."
  }

  @approve_holds_blocking "Not approved: a blocking hold stands, so nothing was applied and the " <>
                            "change set stays in review. Your approval wasn't recorded. Approve " <>
                            "it once the hold clears; the checks show it."

  @approve_preview_failed "Not approved: Cadence couldn't run the checks, so nothing was applied " <>
                            "and the change set stays in review. Your approval wasn't recorded. " <>
                            "Try again; if it keeps happening, tell the team that runs Cadence " <>
                            "for you."

  @doc "Deep-encodes a facade value for JSON."
  @spec encode(term()) :: term()
  def encode(%DateTime{} = value), do: value
  def encode(%Date{} = value), do: value
  # Cadence stores naive timestamps as UTC; the console reads ISO-8601 with a zone (qa #37).
  def encode(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
  def encode(%Time{} = value), do: value
  def encode(%Decimal{} = value), do: Decimal.to_float(value)

  def encode(value) when is_struct(value),
    do: value |> Map.from_struct() |> Map.delete(:__meta__) |> encode()

  def encode(value) when is_map(value), do: Map.new(value, fn {k, v} -> {key(k), encode(v)} end)
  def encode(value) when is_list(value), do: Enum.map(value, &encode/1)
  def encode(value) when is_tuple(value), do: value |> Tuple.to_list() |> encode()
  def encode(value) when is_boolean(value) or is_nil(value), do: value
  def encode(value) when is_atom(value), do: Atom.to_string(value)
  def encode(value), do: value

  # mms-ux (for ca-ux): the four server-worded MM&S refusals open with the submit's act. A submit
  # under 'needs a second person's approval' was Request review, so "Not sent for review:"
  # replaces "Not applied:"; the rest of each sentence is unchanged. An approve applies.
  @by_act ~w(telemetry_app_not_installed telemetry_packet_inputs_required
    mission_model_revision_not_approved mission_model_comparison_failed)a

  @doc "Sends the envelope for a facade error and halts."
  @spec error(Plug.Conn.t(), term()) :: Plug.Conn.t()
  # #280 (U100): who made this change set can't be established (a service with nobody on record).
  def error(conn, {:change_set_approver_authors_unknown, details}),
    do:
      respond_raw(
        conn,
        403,
        "change_set_approver_authors_unknown",
        "Not approved: Cadence can't tell who made this change set, so this can't be approved yet.",
        details
      )

  def error(conn, {:invalid_op, index, errors}),
    do: respond(conn, :invalid_op, %{index: index, errors: encode(errors)})

  # U65: the model approval gate's apply refusals, named by catalog revision number.
  def error(conn, {:mission_model_revision_not_approved, ids}) when is_list(ids) do
    numbers = model_numbers(conn, ids)

    respond_raw(
      conn,
      409,
      "mission_model_revision_not_approved",
      by_act(
        conn,
        ModelApplyRefusals.sentence(:mission_model_revision_not_approved, Map.values(numbers))
      ),
      %{mission_model_revision_ids: ids, catalog_revision_numbers: Enum.map(ids, &numbers[&1])}
    )
  end

  def error(conn, {:mission_model_comparison_failed, revision_id, report_id}) do
    number = conn |> model_numbers([revision_id]) |> Map.get(revision_id)

    respond_raw(
      conn,
      409,
      "mission_model_comparison_failed",
      by_act(conn, ModelApplyRefusals.sentence(:mission_model_comparison_failed, [number])),
      %{
        mission_model_revision_id: revision_id,
        comparison_report_id: report_id,
        catalog_revision_number: number
      }
    )
  end

  def error(conn, {:catalog_command_in_flight, ids}) when is_list(ids),
    do: respond(conn, :catalog_command_in_flight, %{command_request_ids: ids})

  # ux U63: the apply's telemetry refusals name the spacecraft (TelemetryApplyRefusals).
  def error(conn, {tag, ids})
      when tag in [:telemetry_app_not_installed, :telemetry_packet_inputs_required] and
             is_list(ids) do
    scope = conn.assigns[:current_scope]
    mission = conn.assigns[:current_mission]

    message =
      TelemetryApplyRefusals.message(
        tag,
        ids,
        scope && scope.organization_id,
        mission && mission.mission_id
      )

    respond_raw(conn, Map.fetch!(@status, tag), Atom.to_string(tag), by_act(conn, message), %{
      spacecraft_ids: ids
    })
  end

  # The conversion's 'alone in its set' refusal names the open set (domain gives its id).
  def error(conn, {:open_change_set_not_empty, change_set_id}) when is_binary(change_set_id),
    do: respond(conn, :open_change_set_not_empty, %{change_set_id: change_set_id})

  # #262 (ux U79, amended in #374): an approve refused by a blocking hold that appeared after the
  # submit, in approve's own words; the preview stays the details, so the checks show the hold.
  def error(conn, {:holds_blocking, preview}) when is_map(preview) do
    if approving?(conn),
      do: respond_raw(conn, 409, "holds_blocking", @approve_holds_blocking, encode(preview)),
      else: respond(conn, :holds_blocking, encode(preview))
  end

  # #262: never the cause (a database error's text) on the wire; Submission logs it.
  def error(conn, {:preview_failed, _cause}) do
    if approving?(conn),
      do: respond_raw(conn, 503, "preview_failed", @approve_preview_failed, nil),
      else: respond(conn, :preview_failed, nil)
  end

  def error(conn, {tag, details}) when tag in @by_act,
    do: respond_by_act(conn, tag, encode(details))

  def error(conn, tag) when tag in @by_act, do: respond_by_act(conn, tag, nil)

  def error(conn, {tag, details}) when is_map_key(@status, tag),
    do: respond(conn, tag, encode(details))

  def error(conn, tag) when is_map_key(@status, tag), do: respond(conn, tag, nil)

  # #534 (api-ops' condition 3): another generation saved a packet definition under the version
  # this one resolved, at the same moment. Nothing was applied; doing it again re-resolves. mms-ux's
  # apply line; the console words a refused "Request review" itself, since it knows the act.
  def error(conn, {:packet_definition_content_changed, packet_definition_id, version}),
    do:
      respond_raw(
        conn,
        409,
        "packet_definition_version_taken",
        "Not applied: another change saved a packet definition at the same moment, so nothing changed. Try again.",
        %{packet_definition_id: packet_definition_id, version: version, retryable: true}
      )

  def error(conn, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  def error(conn, _unknown),
    do: respond_raw(conn, 422, "unprocessable", "The request could not be completed.", nil)

  defp by_act(conn, "Not applied: " <> rest) do
    if conn.assigns[:submit_act] == :request_review,
      do: "Not sent for review: " <> rest,
      else: "Not applied: " <> rest
  end

  defp by_act(_conn, message), do: message

  # Only an approve reaches these two from review: send back runs no checks.
  defp approving?(conn), do: conn.private[:phoenix_action] == :review

  defp respond_by_act(conn, tag, details),
    do:
      respond_raw(
        conn,
        Map.fetch!(@status, tag),
        Atom.to_string(tag),
        by_act(conn, Map.fetch!(@messages, tag)),
        details
      )

  defp respond(conn, tag, details),
    do:
      respond_raw(
        conn,
        Map.fetch!(@status, tag),
        Atom.to_string(tag),
        Map.fetch!(@messages, tag),
        details
      )

  defp respond_raw(conn, status, code, message, details) do
    conn
    |> put_status(status)
    |> Phoenix.Controller.json(Problem.body(code, message, details))
    |> halt()
  end

  defp model_numbers(conn, ids) do
    scope = conn.assigns[:current_scope]
    mission = conn.assigns[:current_mission]

    ModelApplyRefusals.numbers(
      scope && scope.organization_id,
      mission && mission.mission_id,
      ids
    )
  end

  defp key(key) when is_atom(key), do: Atom.to_string(key)
  defp key(key), do: key
end
