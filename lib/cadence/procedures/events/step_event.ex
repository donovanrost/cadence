defmodule Cadence.Procedures.Events.StepEvent do
  @moduledoc """
  Domain events for procedure step execution.

  These events are persisted via the outbox pattern and represent the
  authoritative record of step execution history. The current state of
  an execution's steps can be derived by replaying these events.

  ## Event Types

  - `step_started` - A step began execution
  - `step_completed` - A step finished successfully
  - `step_failed` - A step encountered an error
  - `step_skipped` - A step was skipped (condition false)
  - `step_blocked` - A step was blocked (dependency failed)

  ## Usage

      # Insert a step event (typically from on_status_change callback)
      StepEvent.insert!(execution, "step_1", :completed, %{result: ...})

      # Query events to derive current state
      events = StepEvent.list_for_execution(execution_id)
      state = StepEvent.derive_state(events)
      # => %{running: [], completed: ["step_1"], failed: [], ...}
  """

  alias Cadence.Outbox
  alias Cadence.Repo

  import Ecto.Query

  @event_types %{
    running: "procedure_step_started",
    completed: "procedure_step_completed",
    failed: "procedure_step_failed",
    skipped: "procedure_step_skipped",
    blocked: "procedure_step_blocked",
    timed_out: "procedure_step_timed_out"
  }

  @doc """
  Inserts a step event into the outbox.

  This is called from the DAG executor's on_status_change callback.
  The event will be processed by the outbox processor and broadcast via PubSub.

  ## Options

  - `:idempotency_key` - Optional key for idempotent inserts. When provided,
    duplicate inserts with the same key will be ignored (ON CONFLICT DO NOTHING).
    Useful for resume operations where step events might be re-copied.

  ## Examples

      # Normal insert
      StepEvent.insert!(execution, "step_1", :completed, %{result: 42})

      # Idempotent insert for resume
      StepEvent.insert!(execution, "step_1", :completed, %{result: 42},
        idempotency_key: "resume:\#{execution.id}:step_1:completed")
  """
  @spec insert!(
          Cadence.Procedures.ProcedureExecution.t(),
          String.t(),
          atom(),
          term(),
          keyword()
        ) ::
          Cadence.Outbox.Event.t()
  def insert!(execution, step_name, status, data \\ nil, opts \\ []) do
    changeset = new(execution, step_name, status, data, opts)

    # Use upsert semantics when idempotency_key is provided
    idempotency_key = Keyword.get(opts, :idempotency_key)

    insert_opts =
      if idempotency_key do
        [on_conflict: :nothing, conflict_target: [:idempotency_key]]
      else
        []
      end

    case Repo.insert(changeset, insert_opts) do
      {:ok, event} -> event
      {:error, changeset} -> raise "Failed to insert step event: #{inspect(changeset.errors)}"
    end
  end

  @doc """
  Creates a step event changeset for use in Ecto.Multi transactions.

  This allows the step event to be inserted atomically with other
  database operations (like log entries).

  ## Example

      Multi.new()
      |> Multi.insert(:step_event, StepEvent.new(execution, "step_1", :completed, data))
      |> Multi.insert(:log, log_changeset)
      |> Repo.transaction()
  """
  @spec new(
          Cadence.Procedures.ProcedureExecution.t(),
          String.t(),
          atom(),
          term(),
          keyword()
        ) :: Ecto.Changeset.t()
  def new(execution, step_name, status, data \\ nil, opts \\ []) do
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
      payload: %{
        step_name: step_name,
        procedure_id: execution.procedure_id,
        data: serialize_data(data)
      }
    }

    Outbox.Event.new(attrs)
  end

  @doc """
  Lists all step events for an execution, ordered by insertion time.
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
  Derives the current step state by replaying events.

  Returns a map with:
  - `:running` - List of currently running step names
  - `:completed` - List of completed step names
  - `:failed` - List of failed step names
  - `:skipped` - List of skipped step names
  - `:blocked` - List of blocked step names
  - `:step_results` - Map of step_name => result data
  """
  @spec derive_state([Cadence.Outbox.Event.t()]) :: map()
  def derive_state(events) do
    initial = %{
      running: MapSet.new(),
      completed: MapSet.new(),
      failed: MapSet.new(),
      skipped: MapSet.new(),
      blocked: MapSet.new(),
      timed_out: MapSet.new(),
      step_results: %{}
    }

    state =
      Enum.reduce(events, initial, fn event, acc ->
        step_name = event.payload["step_name"]
        data = event.payload["data"]

        case event.event_type do
          "procedure_step_started" ->
            %{acc | running: MapSet.put(acc.running, step_name)}

          "procedure_step_completed" ->
            %{
              acc
              | running: MapSet.delete(acc.running, step_name),
                completed: MapSet.put(acc.completed, step_name),
                step_results: Map.put(acc.step_results, step_name, data)
            }

          "procedure_step_failed" ->
            %{
              acc
              | running: MapSet.delete(acc.running, step_name),
                failed: MapSet.put(acc.failed, step_name),
                step_results: Map.put(acc.step_results, step_name, data)
            }

          "procedure_step_skipped" ->
            %{
              acc
              | skipped: MapSet.put(acc.skipped, step_name),
                step_results: Map.put(acc.step_results, step_name, data)
            }

          "procedure_step_blocked" ->
            %{
              acc
              | blocked: MapSet.put(acc.blocked, step_name),
                step_results: Map.put(acc.step_results, step_name, data)
            }

          "procedure_step_timed_out" ->
            %{
              acc
              | running: MapSet.delete(acc.running, step_name),
                timed_out: MapSet.put(acc.timed_out, step_name),
                step_results: Map.put(acc.step_results, step_name, data)
            }

          _ ->
            acc
        end
      end)

    # Convert MapSets to lists for easier consumption
    %{
      running: MapSet.to_list(state.running),
      completed: MapSet.to_list(state.completed),
      failed: MapSet.to_list(state.failed),
      skipped: MapSet.to_list(state.skipped),
      blocked: MapSet.to_list(state.blocked),
      timed_out: MapSet.to_list(state.timed_out),
      step_results: state.step_results
    }
  end

  @doc """
  Converts a status atom to the corresponding event type string.
  """
  @spec event_type_for_status(atom()) :: String.t()
  def event_type_for_status(status) do
    Map.fetch!(@event_types, status)
  end

  @doc """
  Returns the PubSub topic for step events for a given execution.
  """
  @spec topic_for_execution(String.t()) :: String.t()
  def topic_for_execution(execution_id) do
    "procedure:#{execution_id}"
  end

  # Serialize data for JSON storage, handling atoms and other non-JSON types
  defp serialize_data(nil), do: nil

  defp serialize_data(data) when is_map(data) do
    Map.new(data, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), serialize_data(v)}
      {k, v} -> {k, serialize_data(v)}
    end)
  end

  defp serialize_data(data) when is_atom(data), do: Atom.to_string(data)
  defp serialize_data(data) when is_list(data), do: Enum.map(data, &serialize_data/1)
  defp serialize_data(data), do: data
end
