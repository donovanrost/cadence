defmodule Cadence.Telemetry.DataManagement.WorkflowEventEvidence do
  @moduledoc """
  Shared evidence readers for historical telemetry workflow events.

  Workflow correction, transition, and recovery services use this module to
  interpret the same persisted lifecycle payload without duplicating fallback
  paths for older event shapes.
  """

  alias Cadence.Telemetry.Storage

  @spec fetch(binary(), map()) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def fetch(event_id, attrs) when is_binary(event_id) and is_map(attrs) do
    with {:ok, organization_id} <- required_attr(attrs, :organization_id),
         {:ok, mission_id} <- required_attr(attrs, :mission_id) do
      case Storage.fetch_backfill_lifecycle_event(event_id,
             organization_id: organization_id,
             mission_id: mission_id
           ) do
        %Storage.BackfillLifecycleEvent{} = event -> {:ok, event}
        nil -> {:error, {:historical_workflow_event_not_found, event_id}}
      end
    end
  end

  @spec workflow(Storage.BackfillLifecycleEvent.t()) :: :backfill | :import | binary()
  def workflow(event) do
    case Map.get(event.payload, "workflow") do
      workflow when workflow in ["backfill", "import"] ->
        workflow

      _other ->
        workflow_from_event_type(event.event_type)
    end
  end

  @spec job_id(Storage.BackfillLifecycleEvent.t()) :: binary() | nil
  def job_id(%{payload: payload}) when is_map(payload) do
    case first_nested_map_value(payload, [["job_id"], [:job_id]]) do
      {:ok, job_id} -> job_id
      :error -> nil
    end
  end

  def job_id(_event), do: nil

  @spec retryable?(Storage.BackfillLifecycleEvent.t()) :: boolean()
  def retryable?(%{payload: payload}) when is_map(payload) do
    case first_nested_map_value(payload, [
           ["source", "failure", "retryable"],
           [:source, :failure, :retryable],
           ["failure", "retryable"]
         ]) do
      {:ok, retryable} -> retryable not in [false, "false"]
      :error -> true
    end
  end

  def retryable?(_event), do: true

  @spec recovery_action(Storage.BackfillLifecycleEvent.t()) :: term()
  def recovery_action(%{payload: payload}) when is_map(payload) do
    case first_nested_map_value(payload, [
           ["source", "failure", "recovery_action"],
           [:source, :failure, :recovery_action],
           ["failure", "recovery_action"],
           [:failure, :recovery_action],
           ["recovery_action"],
           [:recovery_action]
         ]) do
      {:ok, recovery_action} -> recovery_action
      :error -> nil
    end
  end

  def recovery_action(_event), do: nil

  @spec correction?(Storage.BackfillLifecycleEvent.t()) :: boolean()
  def correction?(event) do
    case Storage.BackfillLifecycleGroup.payload_value(event, :corrects_event_id) do
      event_id when is_binary(event_id) and event_id != "" -> true
      _event_id -> false
    end
  end

  defp workflow_from_event_type(event_type) do
    event_type
    |> Atom.to_string()
    |> case do
      "import_" <> _stage -> :import
      _event_type -> :backfill
    end
  end

  defp first_nested_map_value(map, paths) do
    Enum.find_value(paths, :error, fn path ->
      case nested_map_value(map, path) do
        {:ok, value} -> {:ok, value}
        :error -> nil
      end
    end)
  end

  defp nested_map_value(map, keys) do
    Enum.reduce_while(keys, {:ok, map}, fn key, {:ok, acc} ->
      if is_map(acc) and Map.has_key?(acc, key) do
        {:cont, {:ok, Map.get(acc, key)}}
      else
        {:halt, :error}
      end
    end)
  end

  defp required_attr(attrs, field) do
    case get_attr(attrs, field) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, {:missing_field, field}}
    end
  end

  defp get_attr(attrs, key) when is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end
end
