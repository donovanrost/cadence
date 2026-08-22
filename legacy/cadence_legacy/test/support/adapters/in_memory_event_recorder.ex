defmodule Cadence.Test.Adapters.InMemoryEventRecorder do
  @moduledoc """
  In-memory implementation of EventRecorder for testing.

  Stores recorded events in an Agent for inspection in tests.
  Provides helper functions to query recorded events.

  ## Usage in Tests

      setup do
        {:ok, _} = InMemoryEventRecorder.start_link()
        Application.put_env(:cadence, :event_recorder, InMemoryEventRecorder)
        on_exit(fn -> Application.delete_env(:cadence, :event_recorder) end)
        :ok
      end

      test "records alarm acknowledgment" do
        # ... perform action that should record event ...

        events = InMemoryEventRecorder.list_events()
        assert length(events) == 1
        assert {:alarm_acknowledged, _alarm, _actor, _attrs} = hd(events)
      end
  """

  @behaviour Cadence.Ports.Recordings.EventRecorder

  use Agent

  # ===========================================================================
  # Lifecycle
  # ===========================================================================

  @doc """
  Starts the in-memory event recorder.
  """
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  @doc """
  Stops the event recorder.
  """
  def stop do
    try do
      Agent.stop(__MODULE__)
    catch
      :exit, _ -> :ok
    end

    :ok
  end

  @doc """
  Clears all recorded events.
  """
  def clear do
    if Process.whereis(__MODULE__) do
      Agent.update(__MODULE__, fn _ -> [] end)
    end

    :ok
  end

  # ===========================================================================
  # EventRecorder Implementation
  # ===========================================================================

  @impl true
  def record(event_type, aggregate, actor_id, attrs) do
    record_event({event_type, aggregate, actor_id, attrs, nil})
    :ok
  end

  @impl true
  def record_with_context(event_type, aggregate, actor_id, attrs, context) do
    record_event({event_type, aggregate, actor_id, attrs, context})
    :ok
  end

  # ===========================================================================
  # Query Functions
  # ===========================================================================

  @doc """
  Returns all recorded events in order (newest first).
  """
  def list_events do
    if Process.whereis(__MODULE__) do
      Agent.get(__MODULE__, & &1)
    else
      []
    end
  end

  @doc """
  Returns all events of a specific type.
  """
  def list_events_by_type(event_type) do
    list_events()
    |> Enum.filter(fn {type, _, _, _, _} -> type == event_type end)
  end

  @doc """
  Returns all events for a specific aggregate ID.
  """
  def list_events_for_aggregate(aggregate_id) do
    list_events()
    |> Enum.filter(fn {_, aggregate, _, _, _} ->
      Map.get(aggregate, :id) == aggregate_id
    end)
  end

  @doc """
  Returns all events recorded by a specific actor.
  """
  def list_events_by_actor(actor_id) do
    list_events()
    |> Enum.filter(fn {_, _, aid, _, _} -> aid == actor_id end)
  end

  @doc """
  Returns the count of recorded events.
  """
  def event_count do
    length(list_events())
  end

  @doc """
  Returns the count of events of a specific type.
  """
  def event_count_by_type(event_type) do
    length(list_events_by_type(event_type))
  end

  @doc """
  Returns the most recently recorded event.
  """
  def last_event do
    list_events() |> List.first()
  end

  @doc """
  Returns the most recently recorded event of a specific type.
  """
  def last_event_by_type(event_type) do
    list_events_by_type(event_type) |> List.first()
  end

  @doc """
  Checks if an event of the given type was recorded.
  """
  def recorded?(event_type) do
    event_count_by_type(event_type) > 0
  end

  @doc """
  Checks if an event of the given type was recorded for the aggregate.
  """
  def recorded?(event_type, aggregate_id) do
    list_events()
    |> Enum.any?(fn {type, aggregate, _, _, _} ->
      type == event_type and Map.get(aggregate, :id) == aggregate_id
    end)
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp record_event(event) do
    if Process.whereis(__MODULE__) do
      Agent.update(__MODULE__, fn events -> [event | events] end)
    end
  end
end
