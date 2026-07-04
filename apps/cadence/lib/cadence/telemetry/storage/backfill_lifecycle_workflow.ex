defmodule Cadence.Telemetry.Storage.BackfillLifecycleWorkflow do
  @moduledoc """
  Workflow-facing API for telemetry backfill/import lifecycle events.

  This module is intentionally smaller than a scheduler or import runner. It is
  the contract future orchestration code should use to record operator/system
  decisions before storage writes happen.
  """

  alias Cadence.Telemetry.Storage.{BackfillLifecycleEvent, BackfillLifecycleEvents}

  @type workflow :: :backfill | :import
  @type stage :: :requested | :approved | :rejected | :started | :completed | :failed | :retried

  @workflows [:backfill, :import]
  @stages [:requested, :approved, :rejected, :started, :completed, :failed, :retried]

  @spec record_event(workflow() | binary(), stage() | binary(), map(), keyword()) ::
          {:ok, BackfillLifecycleEvent.t()} | {:error, term()}
  def record_event(workflow, stage, attrs, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and (is_atom(stage) or is_binary(stage)) and
             is_map(attrs) and is_list(opts) do
    with {:ok, workflow} <- normalize_workflow(workflow),
         {:ok, stage} <- normalize_stage(stage),
         :ok <- require_workflow_context(workflow, attrs) do
      attrs
      |> workflow_event_attrs(workflow, stage)
      |> BackfillLifecycleEvents.record_event(opts)
    end
  end

  @spec execute(workflow() | binary(), map(), keyword(), (keyword() -> term()), keyword()) ::
          term() | {:error, term()}
  def execute(workflow, attrs, write_opts, operation_fun, opts \\ [])
      when (is_atom(workflow) or is_binary(workflow)) and is_map(attrs) and is_list(write_opts) and
             is_function(operation_fun, 1) and is_list(opts) do
    with {:ok, workflow} <- normalize_workflow(workflow),
         :ok <- require_workflow_context(workflow, attrs),
         :ok <- maybe_record_event(workflow, :requested, attrs, opts),
         :ok <- maybe_record_approval(workflow, attrs, opts),
         :ok <- record_event_or_error(workflow, :started, attrs, opts) do
      execute_operation(workflow, attrs, write_opts, operation_fun, opts)
    end
  end

  @spec workflows() :: [workflow()]
  def workflows, do: @workflows

  @spec stages() :: [stage()]
  def stages, do: @stages

  defp workflow_event_attrs(attrs, workflow, stage) do
    run_id = run_id(attrs, workflow)
    payload = payload(attrs, workflow, stage, run_id)

    attrs
    |> Map.merge(%{
      backfill_run_id: run_id,
      event_type: event_type(workflow, stage),
      authority: get_attr(attrs, :authority) || default_authority(stage),
      reason: get_attr(attrs, :reason) || default_reason(workflow, stage),
      payload: payload
    })
  end

  defp maybe_record_approval(workflow, attrs, opts) do
    case Keyword.get(opts, :approval, :approved) do
      :approved ->
        record_event_or_error(workflow, :approved, attrs, opts)

      "approved" ->
        record_event_or_error(workflow, :approved, attrs, opts)

      :rejected ->
        with :ok <- record_event_or_error(workflow, :rejected, attrs, opts) do
          {:error, {:workflow_rejected, workflow}}
        end

      "rejected" ->
        with :ok <- record_event_or_error(workflow, :rejected, attrs, opts) do
          {:error, {:workflow_rejected, workflow}}
        end

      approval ->
        {:error, {:unsupported_backfill_lifecycle_approval, approval}}
    end
  end

  defp maybe_record_event(workflow, stage, attrs, opts) do
    if Keyword.get(opts, :"record_#{stage}?", true) do
      record_event_or_error(workflow, stage, attrs, opts)
    else
      :ok
    end
  end

  defp record_event_or_error(workflow, stage, attrs, opts) do
    case record_event(workflow, stage, attrs, event_opts(opts)) do
      {:ok, _event} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_operation(workflow, attrs, write_opts, operation_fun, opts) do
    operation_fun.(workflow_write_opts(workflow, attrs, write_opts))
    |> record_operation_result(workflow, attrs, opts)
  end

  defp record_operation_result(:ok, workflow, attrs, opts) do
    record_event_or_error(workflow, :completed, attrs, opts)
  end

  defp record_operation_result({:ok, value}, workflow, attrs, opts) do
    case record_event_or_error(workflow, :completed, attrs, opts) do
      :ok -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  defp record_operation_result({:error, reason}, workflow, attrs, opts) do
    _result = record_event_or_error(workflow, :failed, failed_attrs(attrs, reason), opts)
    {:error, reason}
  end

  defp record_operation_result(other, workflow, attrs, opts) do
    case record_event_or_error(workflow, :completed, attrs, opts) do
      :ok -> other
      {:error, reason} -> {:error, reason}
    end
  end

  defp failed_attrs(attrs, reason) do
    attrs
    |> Map.put(:reason, get_attr(attrs, :failure_reason) || :workflow_operation_failed)
    |> Map.update(:payload, %{"error" => inspect(reason)}, fn payload ->
      payload
      |> ensure_map()
      |> Map.put("error", inspect(reason))
    end)
  end

  defp workflow_write_opts(:backfill, attrs, write_opts) do
    write_opts
    |> Keyword.put_new(:backfill_run_id, run_id(attrs, :backfill))
    |> Keyword.put_new(:record_backfill_lifecycle_event?, false)
  end

  defp workflow_write_opts(:import, attrs, write_opts) do
    write_opts
    |> Keyword.put_new(:import_run_id, run_id(attrs, :import))
    |> Keyword.put_new(:record_backfill_lifecycle_event?, false)
  end

  defp event_opts(opts) do
    Keyword.take(opts, [:runtime_cache, :dashboard_runtime_invalidation?])
  end

  defp payload(attrs, workflow, stage, run_id) do
    attrs
    |> get_attr(:payload, %{})
    |> ensure_map()
    |> Map.merge(%{
      "workflow" => Atom.to_string(workflow),
      "stage" => Atom.to_string(stage),
      "run_id" => run_id,
      "requested_event_type" => Atom.to_string(event_type(workflow, stage))
    })
  end

  defp event_type(:backfill, :requested), do: :backfill_requested
  defp event_type(:backfill, :approved), do: :backfill_approved
  defp event_type(:backfill, :rejected), do: :backfill_rejected
  defp event_type(:backfill, :started), do: :backfill_started
  defp event_type(:backfill, :completed), do: :backfill_completed
  defp event_type(:backfill, :failed), do: :backfill_failed
  defp event_type(:backfill, :retried), do: :backfill_retried
  defp event_type(:import, :requested), do: :import_requested
  defp event_type(:import, :approved), do: :import_approved
  defp event_type(:import, :rejected), do: :import_rejected
  defp event_type(:import, :started), do: :import_started
  defp event_type(:import, :completed), do: :import_completed
  defp event_type(:import, :failed), do: :import_failed
  defp event_type(:import, :retried), do: :import_retried

  defp default_authority(:approved), do: :authoritative
  defp default_authority(:completed), do: :authoritative
  defp default_authority(:retried), do: :authoritative
  defp default_authority(_stage), do: :unknown

  defp default_reason(workflow, stage), do: :"#{workflow}_#{stage}"

  defp require_workflow_context(workflow, attrs) do
    cond do
      not present?(get_attr(attrs, :organization_id)) ->
        {:error, {:missing_field, :organization_id}}

      not present?(get_attr(attrs, :mission_id)) ->
        {:error, {:missing_field, :mission_id}}

      is_nil(get_attr(attrs, :realm)) ->
        {:error, {:missing_field, :realm}}

      not present?(run_id(attrs, workflow)) ->
        {:error, {:missing_field, run_id_field(workflow)}}

      true ->
        :ok
    end
  end

  defp run_id(attrs, :backfill), do: get_attr(attrs, :backfill_run_id)

  defp run_id(attrs, :import),
    do: get_attr(attrs, :import_run_id) || get_attr(attrs, :backfill_run_id)

  defp run_id_field(:backfill), do: :backfill_run_id
  defp run_id_field(:import), do: :import_run_id

  defp normalize_workflow(workflow) when workflow in @workflows, do: {:ok, workflow}

  defp normalize_workflow(workflow) when is_binary(workflow) do
    normalize_enum(workflow, @workflows, :unsupported_backfill_lifecycle_workflow)
  end

  defp normalize_workflow(workflow),
    do: {:error, {:unsupported_backfill_lifecycle_workflow, workflow}}

  defp normalize_stage(stage) when stage in @stages, do: {:ok, stage}

  defp normalize_stage(stage) when is_binary(stage) do
    normalize_enum(stage, @stages, :unsupported_backfill_lifecycle_stage)
  end

  defp normalize_stage(stage), do: {:error, {:unsupported_backfill_lifecycle_stage, stage}}

  defp normalize_enum(value, allowed, error) do
    normalized = String.replace(value, "-", "_")

    case Enum.find(allowed, &(Atom.to_string(&1) == normalized)) do
      nil -> {:error, {error, value}}
      atom -> {:ok, atom}
    end
  end

  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_value), do: %{}

  defp present?(value), do: is_binary(value) and value != ""

  defp get_attr(attrs, key, default \\ nil)

  defp get_attr(attrs, key, default) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp get_attr(_attrs, _key, default), do: default
end
