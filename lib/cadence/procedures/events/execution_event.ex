defmodule Cadence.Procedures.Events.ExecutionEvent do
  @moduledoc """
  Domain events for procedure execution lifecycle.

  These events are persisted via the outbox pattern and represent the
  authoritative record of execution state changes. Combined with StepEvents,
  the complete execution history can be reconstructed by replaying events.

  ## Event Types

  - `execution_started` - Execution began
  - `execution_running` - Execution transitioned to running (from pending or resumed from paused)
  - `execution_pausing` - Pause requested, waiting for current step(s) to complete
  - `execution_paused` - Execution paused at a safe point
  - `execution_completed` - Execution finished successfully
  - `execution_failed` - Execution failed with an error
  - `execution_cancelled` - Execution was cancelled/aborted

  ## Usage

      # Insert an execution lifecycle event
      ExecutionEvent.insert!(execution, :started)
      ExecutionEvent.insert!(execution, :completed, %{completed_at: DateTime.utc_now()})
      ExecutionEvent.insert!(execution, :failed, %{error_message: "Something went wrong"})

      # Query events to derive execution history
      events = ExecutionEvent.list_for_execution(execution_id)
  """

  alias Cadence.Outbox
  alias Cadence.Repo

  import Ecto.Query

  @event_types %{
    started: "procedure_execution_started",
    running: "procedure_execution_running",
    pausing: "procedure_execution_pausing",
    paused: "procedure_execution_paused",
    completed: "procedure_execution_completed",
    failed: "procedure_execution_failed",
    cancelled: "procedure_execution_cancelled"
  }

  @doc """
  Inserts an execution lifecycle event into the outbox.

  This is called from the ExecutionProcess or ExecutionCoordinator when
  execution status changes. The event will be processed by the outbox
  processor and broadcast via PubSub.

  ## Options

  - `:idempotency_key` - Optional key for idempotent inserts

  ## Examples

      ExecutionEvent.insert!(execution, :started)
      ExecutionEvent.insert!(execution, :completed, %{completed_at: DateTime.utc_now()})
      ExecutionEvent.insert!(execution, :failed, %{error_message: "Validation failed"})
  """
  @spec insert!(
          Cadence.Procedures.ProcedureExecution.t(),
          atom(),
          map(),
          keyword()
        ) :: Cadence.Outbox.Event.t()
  def insert!(execution, status, data \\ %{}, opts \\ []) do
    event_type = Map.fetch!(@event_types, status)
    idempotency_key = Keyword.get(opts, :idempotency_key)

    attrs = %{
      organization_id: execution.organization_id,
      mission_id: execution.mission_id,
      event_type: event_type,
      aggregate_type: "procedure_execution",
      aggregate_id: execution.id,
      actor_id: execution.triggered_by_user_id,
      actor_type: if(execution.triggered_by_user_id, do: "user", else: "system"),
      idempotency_key: idempotency_key,
      payload:
        %{
          procedure_id: execution.procedure_id,
          procedure_version_id: execution.procedure_version_id,
          target_id: execution.target_id,
          triggered_by: to_string(execution.triggered_by),
          parameters: execution.parameters
        }
        |> Map.merge(serialize_data(data))
    }

    # Use upsert semantics when idempotency_key is provided
    insert_opts =
      if idempotency_key do
        [on_conflict: :nothing, conflict_target: [:idempotency_key]]
      else
        []
      end

    case Outbox.insert(attrs, insert_opts) do
      {:ok, event} ->
        event

      {:error, changeset} ->
        raise "Failed to insert execution event: #{inspect(changeset.errors)}"
    end
  end

  @doc """
  Creates an outbox event changeset for use in Ecto.Multi transactions.

  This allows the execution event to be inserted atomically with other
  database operations (like updating the execution record).

  ## Example

      Multi.new()
      |> Multi.update(:execution, changeset)
      |> Multi.insert(:outbox_event, ExecutionEvent.new(execution, :completed, data))
      |> Repo.transaction()
  """
  @spec new(
          Cadence.Procedures.ProcedureExecution.t(),
          atom(),
          map()
        ) :: Ecto.Changeset.t()
  def new(execution, status, data \\ %{}) do
    event_type = Map.fetch!(@event_types, status)

    attrs = %{
      organization_id: execution.organization_id,
      mission_id: execution.mission_id,
      event_type: event_type,
      aggregate_type: "procedure_execution",
      aggregate_id: execution.id,
      actor_id: execution.triggered_by_user_id,
      actor_type: if(execution.triggered_by_user_id, do: "user", else: "system"),
      payload:
        %{
          procedure_id: execution.procedure_id,
          procedure_version_id: execution.procedure_version_id,
          target_id: execution.target_id,
          triggered_by: to_string(execution.triggered_by),
          parameters: execution.parameters
        }
        |> Map.merge(serialize_data(data))
    }

    Outbox.Event.new(attrs)
  end

  @doc """
  Lists all execution lifecycle events for an execution, ordered by insertion time.
  """
  @spec list_for_execution(String.t()) :: [Cadence.Outbox.Event.t()]
  def list_for_execution(execution_id) do
    event_types = Map.values(@event_types)

    from(e in Cadence.Outbox.Event,
      where: e.aggregate_type == "procedure_execution",
      where: e.aggregate_id == ^execution_id,
      where: e.event_type in ^event_types,
      order_by: [asc: e.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Returns the last known status from events for an execution.

  Useful for recovery scenarios where we need to determine execution state.
  """
  @spec derive_status([Cadence.Outbox.Event.t()]) :: atom() | nil
  def derive_status([]), do: nil

  def derive_status(events) do
    last_event = List.last(events)
    event_type_to_status(last_event.event_type)
  end

  @doc """
  Converts an event type string to a status atom.
  """
  def event_type_to_status("procedure_execution_started"), do: :pending
  def event_type_to_status("procedure_execution_running"), do: :running
  def event_type_to_status("procedure_execution_pausing"), do: :pausing
  def event_type_to_status("procedure_execution_paused"), do: :paused
  def event_type_to_status("procedure_execution_completed"), do: :completed
  def event_type_to_status("procedure_execution_failed"), do: :failed
  def event_type_to_status("procedure_execution_cancelled"), do: :cancelled
  def event_type_to_status(_), do: nil

  @doc """
  Converts a status atom to the corresponding event type string.
  """
  @spec event_type_for_status(atom()) :: String.t()
  def event_type_for_status(status) do
    Map.fetch!(@event_types, status)
  end

  @doc """
  Returns the PubSub topic for execution events for a given mission.
  """
  @spec topic_for_mission(String.t()) :: String.t()
  def topic_for_mission(mission_id) do
    "mission:#{mission_id}:procedures"
  end

  # Serialize data for JSON storage, handling atoms and other non-JSON types
  defp serialize_data(nil), do: %{}

  defp serialize_data(data) when is_map(data) do
    Map.new(data, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), serialize_value(v)}
      {k, v} -> {k, serialize_value(v)}
    end)
  end

  defp serialize_data(_), do: %{}

  defp serialize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp serialize_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp serialize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp serialize_value(value) when is_list(value), do: Enum.map(value, &serialize_value/1)
  defp serialize_value(value) when is_map(value), do: serialize_data(value)
  defp serialize_value(value), do: value
end
