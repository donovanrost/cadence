defmodule Cadence.Test.Adapters.FakeEventPublisher do
  @moduledoc """
  Fake event publisher for testing.

  Implements `Cadence.Ports.Messaging.EventPublisher` behavior by collecting
  published events in an Agent, allowing tests to assert on what events were published.

  ## Usage

      setup do
        {:ok, pid} = FakeEventPublisher.start_link()
        on_exit(fn -> FakeEventPublisher.stop(pid) end)
        {:ok, publisher: pid}
      end

      test "publishes alarm event", %{publisher: pid} do
        # ... trigger action that publishes event ...

        events = FakeEventPublisher.get_events(pid)
        assert length(events) == 1
        assert match?({:alarm_triggered, _}, hd(events).event)
      end

  ## Process-Based Subscriptions

  The fake publisher also supports process-based subscriptions for testing
  real-time event flows:

      test "receives published events" do
        FakeEventPublisher.subscribe("mission:123:alarms")

        # ... trigger action ...

        assert_receive {:event, {:alarm_triggered, _alarm}}
      end
  """

  use Agent

  @behaviour Cadence.Ports.Messaging.EventPublisher

  # ============================================================================
  # Agent Lifecycle
  # ============================================================================

  @doc """
  Starts the fake event publisher agent.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    Agent.start_link(
      fn ->
        %{
          events: [],
          subscriptions: %{}
        }
      end,
      name: name
    )
  end

  @doc """
  Stops the fake event publisher agent.
  """
  def stop(pid \\ __MODULE__) do
    try do
      Agent.stop(pid)
    catch
      :exit, _ -> :ok
    end

    :ok
  end

  # ============================================================================
  # Behaviour Implementation
  # ============================================================================

  @impl true
  def publish(topic, event) do
    publish(topic, event, [])
  end

  @impl true
  def publish(topic, event, opts) do
    Agent.update(__MODULE__, fn state ->
      # Record the event
      entry = %{
        topic: topic,
        event: event,
        opts: opts,
        published_at: DateTime.utc_now()
      }

      # Notify subscribed processes
      subscribers = Map.get(state.subscriptions, topic, [])
      Enum.each(subscribers, fn pid -> send(pid, {:event, event}) end)

      %{state | events: [entry | state.events]}
    end)

    :ok
  end

  @impl true
  def publish_batch(topic, events) do
    Enum.each(events, &publish(topic, &1))
    :ok
  end

  @impl true
  def subscribe(topic) do
    Agent.update(__MODULE__, fn state ->
      subscribers = Map.get(state.subscriptions, topic, [])
      new_subscribers = [self() | subscribers] |> Enum.uniq()
      %{state | subscriptions: Map.put(state.subscriptions, topic, new_subscribers)}
    end)

    :ok
  end

  @impl true
  def unsubscribe(topic) do
    Agent.update(__MODULE__, fn state ->
      subscribers = Map.get(state.subscriptions, topic, [])
      new_subscribers = List.delete(subscribers, self())
      %{state | subscriptions: Map.put(state.subscriptions, topic, new_subscribers)}
    end)

    :ok
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  @doc """
  Returns all events that have been published.

  Events are returned in reverse chronological order (most recent first).
  """
  def get_events(pid \\ __MODULE__) do
    if Process.whereis(pid) || is_pid(pid) do
      Agent.get(pid, fn state -> state.events end)
    else
      []
    end
  end

  @doc """
  Alias for `get_events/1` for consistency with other test adapters.
  """
  def list_events(pid \\ __MODULE__) do
    get_events(pid)
  end

  @doc """
  Returns events published to a specific topic.
  """
  def get_events_for_topic(topic, pid \\ __MODULE__) do
    Agent.get(pid, fn state ->
      Enum.filter(state.events, &(&1.topic == topic))
    end)
  end

  @doc """
  Returns the most recently published event.
  """
  def last_event(pid \\ __MODULE__) do
    Agent.get(pid, fn state ->
      List.first(state.events)
    end)
  end

  @doc """
  Returns the count of published events.
  """
  def event_count(pid \\ __MODULE__) do
    Agent.get(pid, fn state -> length(state.events) end)
  end

  @doc """
  Clears all collected events.
  """
  def clear(pid \\ __MODULE__) do
    Agent.update(pid, fn state -> %{state | events: []} end)
  end

  @doc """
  Clears all subscriptions.
  """
  def clear_subscriptions(pid \\ __MODULE__) do
    Agent.update(pid, fn state -> %{state | subscriptions: %{}} end)
  end

  @doc """
  Finds events matching the given criteria.

  ## Examples

      FakeEventPublisher.find_events(topic: "mission:123:alarms")
      FakeEventPublisher.find_events(event_type: :alarm_triggered)
  """
  def find_events(criteria, pid \\ __MODULE__) do
    Agent.get(pid, fn state ->
      Enum.filter(state.events, fn entry ->
        Enum.all?(criteria, fn
          {:topic, topic} -> entry.topic == topic
          {:event_type, type} -> elem(entry.event, 0) == type
        end)
      end)
    end)
  end

  @doc """
  Asserts that an event was published matching the criteria.

  Raises if no matching event is found.
  """
  def assert_event_published(criteria, pid \\ __MODULE__) do
    case find_events(criteria, pid) do
      [] ->
        all_events = get_events(pid)

        raise ExUnit.AssertionError,
          message: """
          Expected an event matching #{inspect(criteria)} to have been published.

          Events published: #{inspect(all_events, pretty: true)}
          """

      events ->
        events
    end
  end

  @doc """
  Asserts that no events were published.
  """
  def assert_no_events(pid \\ __MODULE__) do
    case get_events(pid) do
      [] ->
        :ok

      events ->
        raise ExUnit.AssertionError,
          message: """
          Expected no events to have been published.

          Events published: #{inspect(events, pretty: true)}
          """
    end
  end

  @doc """
  Asserts that a specific event type was published to a topic.

  ## Example

      FakeEventPublisher.assert_published("mission:123:alarms", :alarm_triggered)
  """
  def assert_published(topic, event_type, pid \\ __MODULE__) do
    assert_event_published([topic: topic, event_type: event_type], pid)
  end
end
