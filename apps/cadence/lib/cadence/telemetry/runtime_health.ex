defmodule Cadence.Telemetry.RuntimeHealth do
  @moduledoc """
  In-memory health view for BEAM-owned runtime schedulers and dispatchers.

  This process subscribes to runtime telemetry events and keeps counters in
  process memory. It is intentionally local and rebuildable; it does not write
  operational health observations back to Postgres.
  """

  use GenServer

  @default_recent_limit 50

  @events [
    [:cadence, :contacts, :scheduler, :notification],
    [:cadence, :contacts, :scheduler, :projection_rebuild],
    [:cadence, :contacts, :scheduler, :timer_scheduled],
    [:cadence, :contacts, :scheduler, :timer_fired],
    [:cadence, :contacts, :scheduler, :stale_timer],
    [:cadence, :contacts, :scheduler, :reconcile],
    [:cadence, :contacts, :scheduler, :safety_reconcile],
    [:cadence, :commanding, :dispatcher, :reconcile],
    [:cadence, :commanding, :lane_dispatcher, :dispatch_attempt],
    [:cadence, :commanding, :lane_dispatcher, :dispatch_result],
    [:cadence, :commanding, :lane_dispatcher, :timer_scheduled],
    [:cadence, :commanding, :lane_dispatcher, :stale_timer],
    [:cadence, :commanding, :verifier_scheduler, :notification],
    [:cadence, :commanding, :verifier_scheduler, :projection_rebuild],
    [:cadence, :commanding, :verifier_scheduler, :timer_scheduled],
    [:cadence, :commanding, :verifier_scheduler, :timer_fired],
    [:cadence, :commanding, :verifier_scheduler, :stale_timer],
    [:cadence, :commanding, :verifier_scheduler, :reconcile],
    [:cadence, :commanding, :verifier_scheduler, :safety_reconcile],
    [:cadence, :jobs, :dispatcher, :notification],
    [:cadence, :jobs, :dispatcher, :dispatch_attempt],
    [:cadence, :jobs, :dispatcher, :jobs_claimed],
    [:cadence, :jobs, :dispatcher, :worker_started],
    [:cadence, :jobs, :dispatcher, :worker_start_failed],
    [:cadence, :jobs, :dispatcher, :safety_dispatch_scheduled],
    [:cadence, :jobs, :dispatcher, :stale_timer],
    [:cadence, :runtime, :provider_ingress_executor, :backpressure_entered],
    [:cadence, :runtime, :provider_ingress_executor, :backpressure_released],
    [:cadence, :runtime, :provider_ingress_executor, :capacity_waiter_registered],
    [:cadence, :runtime, :provider_ingress_executor, :capacity_waiter_released],
    [:cadence, :runtime, :ingress_persistence_projector, :capacity_waiter_registered],
    [:cadence, :runtime, :ingress_persistence_projector, :capacity_waiter_released]
  ]

  @type source ::
          :contacts_scheduler
          | :commanding_dispatcher
          | :commanding_lane_dispatcher
          | :commanding_verifier_scheduler
          | :jobs_dispatcher
          | :provider_ingress_executor
          | :ingress_persistence_projector

  @type recent_event :: %{
          source: source(),
          event: atom(),
          event_name: [atom()],
          observed_at: DateTime.t(),
          measurements: map(),
          metadata: map()
        }

  @type source_summary :: %{
          total_events: non_neg_integer(),
          stale_timer_count: non_neg_integer(),
          safety_activity_count: non_neg_integer(),
          events: %{optional(atom()) => non_neg_integer()},
          reasons: %{optional(atom()) => non_neg_integer()},
          last_event_at: DateTime.t() | nil
        }

  @type snapshot :: %{
          total_events: non_neg_integer(),
          stale_timer_count: non_neg_integer(),
          safety_activity_count: non_neg_integer(),
          sources: %{optional(source()) => source_summary()},
          recent_events: [recent_event()],
          subscribed_events: [[atom()]]
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec events() :: [[atom()]]
  def events, do: @events

  @spec snapshot(GenServer.server()) :: snapshot()
  def snapshot(server \\ __MODULE__) do
    GenServer.call(server, :snapshot)
  end

  @spec reset(GenServer.server()) :: :ok
  def reset(server \\ __MODULE__) do
    GenServer.call(server, :reset)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    name = Keyword.get(opts, :name, __MODULE__)
    handler_id = Keyword.get(opts, :handler_id, default_handler_id(name))
    recent_limit = Keyword.get(opts, :recent_limit, @default_recent_limit)

    state =
      empty_state(%{
        name: name,
        handler_id: handler_id,
        recent_limit: recent_limit
      })

    attach_handlers(handler_id, name)

    {:ok, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, snapshot_from_state(state), state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, empty_state(state)}
  end

  @impl true
  def handle_cast({:runtime_event, event_name, measurements, metadata, observed_at}, state) do
    source = source_from_event(event_name)
    event = List.last(event_name)

    recent_event = %{
      source: source,
      event: event,
      event_name: event_name,
      observed_at: observed_at,
      measurements: measurements,
      metadata: metadata
    }

    source_summary =
      state.sources
      |> Map.get(source, empty_source_summary())
      |> record_source_event(event, metadata, observed_at)

    state =
      state
      |> Map.update!(:total_events, &(&1 + 1))
      |> Map.update!(:stale_timer_count, &(&1 + stale_timer_increment(event)))
      |> Map.update!(
        :safety_activity_count,
        &(&1 + safety_activity_increment(event, metadata))
      )
      |> Map.update!(:sources, &Map.put(&1, source, source_summary))
      |> Map.update!(
        :recent_events,
        &limit_recent_events([recent_event | &1], state.recent_limit)
      )

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
    :ok
  end

  @spec handle_event([atom()], map(), map(), map()) :: :ok
  def handle_event(event_name, measurements, metadata, %{server: server}) do
    GenServer.cast(
      server,
      {:runtime_event, event_name, measurements, metadata, DateTime.utc_now()}
    )
  end

  defp attach_handlers(handler_id, server) do
    _ = :telemetry.detach(handler_id)

    :ok =
      :telemetry.attach_many(
        handler_id,
        @events,
        &__MODULE__.handle_event/4,
        %{server: server}
      )
  end

  defp default_handler_id(name) when is_atom(name), do: "#{__MODULE__}.#{name}"
  defp default_handler_id(_name), do: "#{__MODULE__}.#{System.unique_integer([:positive])}"

  defp empty_state(%{name: name, handler_id: handler_id, recent_limit: recent_limit}) do
    %{
      name: name,
      handler_id: handler_id,
      recent_limit: recent_limit,
      total_events: 0,
      stale_timer_count: 0,
      safety_activity_count: 0,
      sources: %{},
      recent_events: []
    }
  end

  defp source_from_event([:cadence, :contacts, :scheduler, _event]),
    do: :contacts_scheduler

  defp source_from_event([:cadence, :commanding, :dispatcher, _event]),
    do: :commanding_dispatcher

  defp source_from_event([:cadence, :commanding, :lane_dispatcher, _event]),
    do: :commanding_lane_dispatcher

  defp source_from_event([:cadence, :commanding, :verifier_scheduler, _event]),
    do: :commanding_verifier_scheduler

  defp source_from_event([:cadence, :jobs, :dispatcher, _event]),
    do: :jobs_dispatcher

  defp source_from_event([:cadence, :runtime, :provider_ingress_executor, _event]),
    do: :provider_ingress_executor

  defp source_from_event([:cadence, :runtime, :ingress_persistence_projector, _event]),
    do: :ingress_persistence_projector

  defp record_source_event(source_summary, event, metadata, observed_at) do
    source_summary
    |> Map.update!(:total_events, &(&1 + 1))
    |> Map.update!(:stale_timer_count, &(&1 + stale_timer_increment(event)))
    |> Map.update!(
      :safety_activity_count,
      &(&1 + safety_activity_increment(event, metadata))
    )
    |> Map.update!(:events, &Map.update(&1, event, 1, fn count -> count + 1 end))
    |> record_reason(metadata)
    |> Map.put(:last_event_at, observed_at)
  end

  defp record_reason(source_summary, %{reason: reason}) when is_atom(reason) do
    Map.update!(source_summary, :reasons, &Map.update(&1, reason, 1, fn count -> count + 1 end))
  end

  defp record_reason(source_summary, _metadata), do: source_summary

  defp empty_source_summary do
    %{
      total_events: 0,
      stale_timer_count: 0,
      safety_activity_count: 0,
      events: %{},
      reasons: %{},
      last_event_at: nil
    }
  end

  defp stale_timer_increment(:stale_timer), do: 1
  defp stale_timer_increment(_event), do: 0

  defp safety_activity_increment(:safety_reconcile, _metadata), do: 1
  defp safety_activity_increment(:safety_dispatch_scheduled, _metadata), do: 1
  defp safety_activity_increment(_event, %{reason: :safety}), do: 1
  defp safety_activity_increment(_event, _metadata), do: 0

  defp limit_recent_events(events, recent_limit) do
    Enum.take(events, max(recent_limit, 0))
  end

  defp snapshot_from_state(state) do
    %{
      total_events: state.total_events,
      stale_timer_count: state.stale_timer_count,
      safety_activity_count: state.safety_activity_count,
      sources: state.sources,
      recent_events: Enum.reverse(state.recent_events),
      subscribed_events: @events
    }
  end
end
