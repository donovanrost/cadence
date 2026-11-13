defmodule Cadence.Control.Activations.ApplyAttention do
  @moduledoc """
  The `activation_apply` source of the mission attention read (director, 2026-11-13): an approved
  activation whose apply failed (`apply_failed`) or stalled midway (`apply_stalled`: in progress
  past `Resume.stalled_after_ms/0` with no executor holding its lock), so someone retries it
  (`Control.Activations.resume/4`, the console's `Retry apply`).

  Nothing to acknowledge. An item is open until its execution succeeds (resolved, action
  `applied`) or a newer activation of the mission succeeds (action `superseded`);
  `resolved_by` kind `system`. One item per request, id = the activation request id.
  """

  import Ecto.Query

  alias Cadence.Control.Activations.{ActivationExecutionRow, Description, ExecutionLock, Resume}
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo
  alias Cadence.SpacecraftStore

  @source "activation_apply"
  @resolved_window_s 60

  def source, do: @source

  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    now = DateTime.utc_now()
    executions = executions(org, mission)

    executions
    |> Enum.filter(&stuck?(&1, now))
    |> Enum.reject(&superseded_at(&1, executions))
    |> Enum.sort_by(&since/1, DateTime)
    |> Enum.map(&item/1)
  end

  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(org, mission, %DateTime{} = since) do
    executions = executions(org, mission)

    for row <- executions,
        {action, at} <- List.wrap(resolution(row, executions)),
        DateTime.compare(at, since) != :lt,
        DateTime.diff(DateTime.utc_now(), at) <= @resolved_window_s do
      %{
        id: row.activation_request_id,
        source: @source,
        resolved_by: %{"kind" => "system"},
        action: action,
        resolved_at: at
      }
    end
  end

  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: 0}
  def counts(org, mission), do: %{open: length(items(org, mission)), acknowledged: 0}

  defp executions(org, mission) do
    ActivationExecutionRow
    |> where([e], e.organization_id == ^org and e.mission_id == ^mission)
    |> order_by([e], asc: e.started_at)
    |> Repo.all()
  end

  defp stuck?(%{status: :failed}, _now), do: true

  defp stuck?(%{status: :in_progress} = row, now),
    do: Resume.stalled?(row.started_at, now) and ExecutionLock.free?(row.activation_request_id)

  defp stuck?(_row, _now), do: false

  # A newer activation of the mission applied after this one started: this one is moot.
  defp superseded_at(row, executions) do
    executions
    |> Enum.find(fn other ->
      other.status == :succeeded and other.activation_request_id != row.activation_request_id and
        DateTime.after?(other.started_at, row.started_at)
    end)
    |> case do
      nil -> nil
      newer -> newer.completed_at
    end
  end

  # Only executions that were stuck and got out of it resolve; a first-time success doesn't.
  defp resolution(%{status: :succeeded} = row, _executions) do
    if restarted?(row), do: {"applied", row.completed_at}
  end

  defp resolution(row, executions) do
    case superseded_at(row, executions) do
      %DateTime{} = at -> {"superseded", at}
      nil -> nil
    end
  end

  # A resumed execution names its resumer as the executor (Control.Activations.resume/4).
  defp restarted?(row),
    do: match?(%{"kind" => "user"}, unwrap(row.executor_actor_document))

  defp since(%{status: :failed} = row), do: row.completed_at || row.started_at
  defp since(row), do: row.started_at

  defp item(row) do
    error = unwrap(row.error_document) || %{}
    code = if row.status == :failed, do: error["code"]
    description = describe(row.activation_request_id)
    ids = description.spacecraft_ids

    %{
      id: row.activation_request_id,
      source: @source,
      conflict: if(row.status == :failed, do: "apply_failed", else: "apply_stalled"),
      state: "open",
      error_code: code,
      error: error_sentence(row.status, code, row, ids),
      # Retry apply can succeed; otherwise the next step is a new request (ux U41).
      retryable: row.status == :in_progress or Resume.retryable_code?(code),
      activation_request_id: row.activation_request_id,
      summary: description.summary,
      kind: description.kind,
      app: description.app,
      spacecraft_ids: ids,
      spacecraft_id: if(match?([_one], ids), do: hd(ids)),
      spacecraft_count: length(ids),
      since: since(row),
      raised_at: since(row)
    }
  end

  defp describe(request_id) do
    case ManagementActivations.fetch_approved(request_id) do
      {:ok, approved} -> Description.describe(approved.metadata)
      {:error, _not_approved} -> Description.describe(%{})
    end
  end

  # ux U41 (decisions.md): standalone sentences, never the raw reason.
  defp error_sentence(:in_progress, _code, _row, _ids),
    do: "Applying didn't finish, and nothing is working on it now."

  defp error_sentence(:failed, "activation_execution_interrupted", _row, _ids),
    do: "Applying was cut off: Cadence lost its database connection partway."

  defp error_sentence(:failed, "spacecraft_configuration_review_stale", row, ids),
    do:
      "#{whose_configuration(row, ids)} changed after it was reviewed, so the reviewed version " <>
        "can't be applied."

  defp error_sentence(:failed, "approved_activation_content_mismatch", _row, _ids),
    do: "What would be applied now differs from what was approved, so it wasn't applied."

  defp error_sentence(:failed, _code, _row, _ids), do: "Applying failed."

  defp whose_configuration(row, [id]) do
    case SpacecraftStore.fetch_spacecraft(row.organization_id, row.mission_id, id) do
      {:ok, %{display_name: name}} when is_binary(name) -> "#{name}'s configuration"
      _unknown -> "A spacecraft's configuration"
    end
  end

  defp whose_configuration(_row, _several), do: "A spacecraft's configuration"

  defp unwrap(document), do: JsonDocument.unwrap_value(document)
end
