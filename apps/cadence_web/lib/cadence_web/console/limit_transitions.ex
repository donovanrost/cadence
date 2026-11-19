defmodule CadenceWeb.Console.LimitTransitions do
  @moduledoc """
  Turns the limit-evaluation fact stream into per-mission *transition*
  notifications for console channels.

  `Cadence.Limits.Facts` publishes every committed evaluation; at 1 Hz feeds
  most of those repeat the previous state. This relay remembers the last
  normalized state per point and broadcasts
  `{:console_limit_transition, mission_id, spacecraft_id}` on
  `topic(mission_id)` only when a point's state changes (or is first seen
  since boot). The memory is bounded by the number of points with limits.
  """

  use GenServer

  alias Cadence.Limits.{Event, Facts}
  alias Cadence.Platform.EventBus

  @pubsub Cadence.PubSub

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec topic(binary()) :: binary()
  def topic(mission_id) when is_binary(mission_id), do: "console:limit-transitions:" <> mission_id

  @spec subscribe(binary()) :: :ok | {:error, term()}
  def subscribe(mission_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(mission_id))

  @impl true
  def init(opts) do
    :ok = Facts.subscribe(Keyword.get(opts, :event_bus, EventBus), self())

    {:ok, %{}}
  end

  @impl true
  def handle_call({:cadence_fact, _topic, fact}, _from, states),
    do: {:reply, :ok, observe(fact, states)}

  @impl true
  def handle_cast({:cadence_fact, _topic, fact}, states), do: {:noreply, observe(fact, states)}

  @impl true
  def handle_info(_message, states), do: {:noreply, states}

  @doc false
  @spec observe(term(), map()) :: map()
  def observe(%Event{mission_id: mission_id} = event, states) when is_binary(mission_id) do
    key = {mission_id, event.spacecraft_id, event.point_id}

    case Map.fetch(states, key) do
      {:ok, state} when state == event.normalized_state ->
        states

      _changed ->
        Phoenix.PubSub.broadcast(
          @pubsub,
          topic(mission_id),
          {:console_limit_transition, mission_id, event.spacecraft_id}
        )

        Map.put(states, key, event.normalized_state)
    end
  end

  def observe(_fact, states), do: states
end
