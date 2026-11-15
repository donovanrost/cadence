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
    invalid_rollback_target: 422,
    nothing_to_roll_back: 422,
    rollback_unknown_kind: 422,
    rollback_crosses_legacy: 409,
    change_set_open: 409,
    rollback_in_progress: 409
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
    invalid_rollback_target: "Choose a revision from r1 up to the one before the current one.",
    nothing_to_roll_back: "Nothing differs from that revision.",
    rollback_unknown_kind: "A revision in that range has changes this version can't undo.",
    rollback_crosses_legacy:
      "The range includes a legacy activation; roll back to it, not past it.",
    change_set_open: "Finish or discard the open change set first.",
    rollback_in_progress:
      "A rollback is staged; apply or discard it before staging other changes."
  }

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

  @doc "Sends the envelope for a facade error and halts."
  @spec error(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def error(conn, {:invalid_op, index, errors}),
    do: respond(conn, :invalid_op, %{index: index, errors: encode(errors)})

  # U65: the model approval gate's apply refusals, named by catalog revision number.
  def error(conn, {:mission_model_revision_not_approved, ids}) when is_list(ids) do
    numbers = model_numbers(conn, ids)

    respond_raw(
      conn,
      409,
      "mission_model_revision_not_approved",
      ModelApplyRefusals.sentence(:mission_model_revision_not_approved, Map.values(numbers)),
      %{mission_model_revision_ids: ids, catalog_revision_numbers: Enum.map(ids, &numbers[&1])}
    )
  end

  def error(conn, {:mission_model_comparison_failed, revision_id, report_id}) do
    number = conn |> model_numbers([revision_id]) |> Map.get(revision_id)

    respond_raw(
      conn,
      409,
      "mission_model_comparison_failed",
      ModelApplyRefusals.sentence(:mission_model_comparison_failed, [number]),
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

    respond_raw(conn, Map.fetch!(@status, tag), Atom.to_string(tag), message, %{
      spacecraft_ids: ids
    })
  end

  def error(conn, {tag, details}) when is_map_key(@status, tag),
    do: respond(conn, tag, encode(details))

  def error(conn, tag) when is_map_key(@status, tag), do: respond(conn, tag, nil)

  def error(conn, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  def error(conn, _unknown),
    do: respond_raw(conn, 422, "unprocessable", "The request could not be completed.", nil)

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
