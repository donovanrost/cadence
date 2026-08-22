defmodule Cadence.Telemetry.DataManagement.WorkflowEvents do
  @moduledoc """
  Historical telemetry workflow event normalization and recording.

  This module owns the shared workflow and stage vocabulary, required event
  context, and the grouped request-item event shape.
  """

  alias Cadence.Telemetry.Storage

  @historical_data_workflows [:backfill, :import]
  @historical_data_workflow_stages [
    :requested,
    :approved,
    :rejected,
    :started,
    :completed,
    :failed,
    :retried
  ]

  @spec record(atom() | binary(), atom() | binary(), map(), keyword()) ::
          {:ok, Storage.BackfillLifecycleEvent.t()} | {:error, term()}
  def record(workflow, stage, attrs, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and (is_atom(stage) or is_binary(stage)) and
             is_map(attrs) and is_list(opts) do
    with {:ok, workflow} <- normalize_workflow(workflow),
         {:ok, stage} <- normalize_stage(stage),
         :ok <- validate_context(workflow, attrs) do
      Storage.record_backfill_lifecycle_workflow_event(
        workflow,
        stage,
        attrs,
        event_opts(opts)
      )
    end
  end

  @spec record_request(atom() | binary(), map(), [binary() | nil], keyword()) ::
          {:ok, [Storage.BackfillLifecycleEvent.t()]} | {:error, term()}
  def record_request(workflow, attrs, point_ids, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and is_map(attrs) and is_list(point_ids) and
             is_list(opts) do
    with {:ok, workflow} <- normalize_workflow(workflow) do
      {point_ids, request_group_id, attrs} = request_context(attrs, point_ids)

      record_request_items(workflow, attrs, point_ids, request_group_id, opts)
    end
  end

  @spec normalize_workflow(atom() | binary()) :: {:ok, :backfill | :import} | {:error, term()}
  def normalize_workflow(workflow) when workflow in @historical_data_workflows,
    do: {:ok, workflow}

  def normalize_workflow(workflow) when is_binary(workflow) do
    normalize_enum(
      workflow,
      @historical_data_workflows,
      :unsupported_historical_data_workflow
    )
  end

  def normalize_workflow(workflow),
    do: {:error, {:unsupported_historical_data_workflow, workflow}}

  @spec normalize_stage(atom() | binary()) :: {:ok, atom()} | {:error, term()}
  def normalize_stage(stage) when stage in @historical_data_workflow_stages,
    do: {:ok, stage}

  def normalize_stage(stage) when is_binary(stage) do
    normalize_enum(
      stage,
      @historical_data_workflow_stages,
      :unsupported_historical_data_workflow_stage
    )
  end

  def normalize_stage(stage),
    do: {:error, {:unsupported_historical_data_workflow_stage, stage}}

  @spec validate_context(:backfill | :import, map()) :: :ok | {:error, term()}
  def validate_context(workflow, attrs)
      when workflow in @historical_data_workflows and is_map(attrs) do
    [:organization_id, :mission_id, :data_source_id, :binding_id]
    |> Enum.reduce_while(:ok, fn field, :ok ->
      case require_present(attrs, field) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      :ok -> require_realm_and_run_id(workflow, attrs)
      {:error, reason} -> {:error, reason}
    end
  end

  defp request_context(attrs, point_ids) do
    point_ids = if point_ids == [], do: [nil], else: point_ids

    request_group_id =
      get_attr(attrs, :backfill_run_id) || Cadence.Ids.new("telemetry_backfill_run")

    attrs = Map.put(attrs, :backfill_run_id, request_group_id)

    {point_ids, request_group_id, attrs}
  end

  defp record_request_items(workflow, attrs, point_ids, request_group_id, opts) do
    item_count = length(point_ids)

    point_ids
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {point_id, item_index}, {:ok, events} ->
      record_request_item(
        workflow,
        attrs,
        point_id,
        request_group_id,
        item_count,
        item_index,
        opts,
        events
      )
    end)
    |> request_result()
  end

  defp record_request_item(
         workflow,
         attrs,
         point_id,
         request_group_id,
         item_count,
         item_index,
         opts,
         events
       ) do
    item_attrs =
      attrs
      |> request_item_attrs(point_id, request_group_id, item_count, item_index)
      |> compact_attrs()

    case record(workflow, :requested, item_attrs, opts) do
      {:ok, event} -> {:cont, {:ok, [event | events]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp request_result({:ok, events}), do: {:ok, Enum.reverse(events)}
  defp request_result({:error, reason}), do: {:error, reason}

  defp request_item_attrs(attrs, point_id, request_group_id, item_count, item_index) do
    item_run_id = request_item_run_id(request_group_id, item_count, item_index)
    request_mode = if item_count == 1, do: "single_point", else: "bulk_points"

    attrs
    |> Map.put(:backfill_run_id, item_run_id)
    |> Map.put(:import_run_id, item_run_id)
    |> maybe_put_request_point(point_id)
    |> Map.put(
      :payload,
      attrs
      |> get_attr(:payload, %{})
      |> ensure_map()
      |> Map.merge(%{
        "request_source" => "dashboard_direct_request",
        "request_mode" => request_mode,
        "request_group_id" => request_group_id,
        "request_item_index" => item_index,
        "request_item_count" => item_count,
        "request_item_run_id" => item_run_id
      })
    )
  end

  defp maybe_put_request_point(attrs, nil), do: attrs

  defp maybe_put_request_point(attrs, point_id) do
    attrs
    |> Map.put(:observable_id, point_id)
    |> Map.put(:point_id, point_id)
  end

  defp request_item_run_id(request_group_id, 1, _item_index), do: request_group_id

  defp request_item_run_id(request_group_id, _item_count, item_index),
    do: "#{request_group_id}-#{String.pad_leading(Integer.to_string(item_index), 3, "0")}"

  defp normalize_enum(value, allowed, error) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")

    case Enum.find(allowed, &(Atom.to_string(&1) == normalized)) do
      nil -> {:error, {error, value}}
      atom -> {:ok, atom}
    end
  end

  defp require_realm_and_run_id(workflow, attrs) do
    case require_realm(attrs) do
      :ok -> require_run_id(workflow, attrs)
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_run_id(:backfill, attrs), do: require_present(attrs, :backfill_run_id)
  defp require_run_id(:import, attrs), do: require_present(attrs, :import_run_id)

  defp require_present(attrs, field) do
    case get_attr(attrs, field) do
      value when is_binary(value) and value != "" -> :ok
      _value -> {:error, {:missing_field, field}}
    end
  end

  defp require_realm(attrs) do
    if is_nil(get_attr(attrs, :realm)) do
      {:error, {:missing_field, :realm}}
    else
      :ok
    end
  end

  defp event_opts(opts) do
    Keyword.take(opts, [:runtime_cache, :dashboard_runtime_invalidation?])
  end

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_value), do: %{}

  defp compact_attrs(attrs) do
    attrs
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp get_attr(attrs, key, default \\ nil)

  defp get_attr(attrs, key, default) when is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
