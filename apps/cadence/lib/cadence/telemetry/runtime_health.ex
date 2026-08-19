defmodule Cadence.Telemetry.RuntimeHealth do
  @moduledoc """
  In-memory health view for BEAM-owned runtime schedulers and dispatchers.

  This process subscribes to runtime telemetry events and keeps counters in
  process memory. It is intentionally local and rebuildable; it does not write
  operational health observations back to Postgres.
  """

  use GenServer

  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.Dashboards.RuntimeInvalidation.Event
  alias Cadence.Telemetry.Profiler

  @default_recent_limit 50
  @client_tag {__MODULE__, :client}
  @event_route_key :cadence_runtime_health_route

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
    [:cadence, :runtime, :ingress_persistence_projector, :capacity_waiter_released],
    Profiler.ingress_result_event(),
    RuntimeInvalidation.telemetry_event(),
    RuntimeInvalidation.decision_telemetry_event()
  ]

  @type source ::
          :contacts_scheduler
          | :commanding_dispatcher
          | :commanding_lane_dispatcher
          | :commanding_verifier_scheduler
          | :jobs_dispatcher
          | :telemetry_ingress
          | :provider_ingress_executor
          | :ingress_persistence_projector
          | :dashboards_runtime_invalidation

  @type recent_event :: %{
          optional(:runtime_event) => Event.t(),
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
          boundaries: %{optional(atom()) => non_neg_integer()},
          last_event_at: DateTime.t() | nil
        }

  @type snapshot :: %{
          total_events: non_neg_integer(),
          stale_timer_count: non_neg_integer(),
          safety_activity_count: non_neg_integer(),
          sources: %{optional(source()) => source_summary()},
          metrics: map(),
          recent_events: [recent_event()],
          subscribed_events: [[atom()]]
        }

  @type client :: %{
          required(:tag) => {module(), :client},
          required(:server) => pid(),
          required(:event_route) => term()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec events() :: [[atom()]]
  def events, do: @events

  @doc """
  Returns the immutable routing client captured by a runtime-health instance.
  """
  @spec client(GenServer.server() | client()) :: client()
  def client(server \\ __MODULE__)
  def client(%{tag: @client_tag} = client), do: client
  def client(server), do: GenServer.call(server, :client)

  @spec snapshot(GenServer.server() | client()) :: snapshot()
  def snapshot(server \\ __MODULE__) do
    GenServer.call(resolve_server(server), :snapshot)
  end

  @spec reset(GenServer.server() | client()) :: :ok
  def reset(server \\ __MODULE__) do
    GenServer.call(resolve_server(server), :reset)
  end

  @doc """
  Executes a telemetry event routed only to the selected runtime-health instance.
  """
  @spec execute(GenServer.server() | client(), [atom()], map(), map()) :: :ok
  def execute(server_or_client, event_name, measurements, metadata)
      when is_list(event_name) and is_map(measurements) and is_map(metadata) do
    client = resolve_client(server_or_client)

    :telemetry.execute(
      event_name,
      measurements,
      Map.put(metadata, @event_route_key, client.event_route)
    )
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    name = Keyword.get(opts, :name, __MODULE__)
    handler_id = Keyword.get_lazy(opts, :handler_id, fn -> {__MODULE__, self(), make_ref()} end)
    recent_limit = Keyword.get(opts, :recent_limit, @default_recent_limit)
    event_route = Keyword.get(opts, :event_route, :default)

    client = %{
      tag: @client_tag,
      server: self(),
      event_route: event_route
    }

    state =
      empty_state(%{
        client: client,
        name: name,
        handler_id: handler_id,
        recent_limit: recent_limit
      })

    case attach_handlers(handler_id, client) do
      :ok -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:client, _from, state) do
    {:reply, state.client, state}
  end

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
    runtime_event = runtime_event(event_name, measurements, metadata, observed_at)

    recent_event =
      %{
        source: source,
        event: event,
        event_name: event_name,
        observed_at: observed_at,
        measurements: measurements,
        metadata: metadata
      }
      |> maybe_put_runtime_event(runtime_event)

    source_summary =
      state.sources
      |> Map.get(source, empty_source_summary())
      |> record_source_event(event, metadata, runtime_event, observed_at)

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
        :metrics,
        &record_metrics(&1, source, event, measurements, metadata, observed_at)
      )
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
  def handle_event(event_name, measurements, metadata, %{client: client}) do
    if Map.get(metadata, @event_route_key, :default) == client.event_route do
      GenServer.cast(
        client.server,
        {:runtime_event, event_name, measurements, metadata, DateTime.utc_now()}
      )
    end

    :ok
  end

  defp attach_handlers(handler_id, client) do
    case :telemetry.attach_many(
           handler_id,
           @events,
           &__MODULE__.handle_event/4,
           %{client: client}
         ) do
      :ok ->
        :ok

      {:error, :already_exists} ->
        {:error, {:telemetry_handler_already_exists, handler_id}}
    end
  end

  defp empty_state(%{
         client: client,
         name: name,
         handler_id: handler_id,
         recent_limit: recent_limit
       }) do
    %{
      client: client,
      name: name,
      handler_id: handler_id,
      recent_limit: recent_limit,
      total_events: 0,
      stale_timer_count: 0,
      safety_activity_count: 0,
      sources: %{},
      metrics: empty_metrics(),
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

  defp source_from_event([:cadence, :runtime, :telemetry_ingress, _event]),
    do: :telemetry_ingress

  defp source_from_event([:cadence, :dashboards, :runtime_invalidation, _event]),
    do: :dashboards_runtime_invalidation

  defp runtime_event(event_name, measurements, metadata, observed_at) do
    if event_name == RuntimeInvalidation.telemetry_event() do
      case Event.from_metadata(metadata, measurements, occurred_at: observed_at) do
        {:ok, %Event{} = event} -> event
        :error -> nil
      end
    else
      nil
    end
  end

  defp maybe_put_runtime_event(recent_event, %Event{} = runtime_event),
    do: Map.put(recent_event, :runtime_event, runtime_event)

  defp maybe_put_runtime_event(recent_event, _runtime_event), do: recent_event

  defp record_source_event(source_summary, event, metadata, runtime_event, observed_at) do
    source_summary
    |> Map.update!(:total_events, &(&1 + 1))
    |> Map.update!(:stale_timer_count, &(&1 + stale_timer_increment(event)))
    |> Map.update!(
      :safety_activity_count,
      &(&1 + safety_activity_increment(event, metadata))
    )
    |> Map.update!(:events, &Map.update(&1, event, 1, fn count -> count + 1 end))
    |> record_reason(metadata)
    |> record_boundary(event, runtime_event, metadata)
    |> Map.put(:last_event_at, observed_at)
  end

  defp record_reason(source_summary, %{reason: reason}) when is_atom(reason) do
    Map.update!(source_summary, :reasons, &Map.update(&1, reason, 1, fn count -> count + 1 end))
  end

  defp record_reason(source_summary, _metadata), do: source_summary

  defp record_boundary(source_summary, _event, %Event{boundary: boundary}, _metadata) do
    Map.update!(
      source_summary,
      :boundaries,
      &Map.update(&1, boundary, 1, fn count -> count + 1 end)
    )
  end

  defp record_boundary(source_summary, :invalidate, _runtime_event, %{boundary: boundary})
       when is_atom(boundary) do
    Map.update!(
      source_summary,
      :boundaries,
      &Map.update(&1, boundary, 1, fn count -> count + 1 end)
    )
  end

  defp record_boundary(source_summary, _event, _runtime_event, _metadata), do: source_summary

  defp empty_source_summary do
    %{
      total_events: 0,
      stale_timer_count: 0,
      safety_activity_count: 0,
      events: %{},
      reasons: %{},
      boundaries: %{},
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
      metrics: snapshot_metrics(state.metrics),
      recent_events: Enum.reverse(state.recent_events),
      subscribed_events: @events
    }
  end

  defp empty_metrics do
    %{
      ingress_processing_latency_ms: %{}
    }
  end

  defp record_metrics(
         metrics,
         :telemetry_ingress,
         :processing_result,
         measurements,
         metadata,
         observed_at
       ) do
    case normalize_ingress_latency_sample(measurements, metadata, observed_at) do
      nil ->
        metrics

      sample ->
        put_in(
          metrics,
          [:ingress_processing_latency_ms, ingress_latency_sample_key(sample)],
          sample
        )
    end
  end

  defp record_metrics(metrics, _source, _event, _measurements, _metadata, _observed_at),
    do: metrics

  defp normalize_ingress_latency_sample(measurements, metadata, observed_at) do
    with duration_us when is_integer(duration_us) and duration_us >= 0 <-
           Map.get(measurements, :end_to_end_us),
         mission_id when is_binary(mission_id) and mission_id != "" <-
           Map.get(metadata, :mission_id) do
      source_endpoint_id =
        Map.get(metadata, :source_endpoint_id) ||
          Map.get(metadata, :source_endpoint_ref) ||
          Map.get(metadata, :source_ref)

      %{
        observable_id: "ingress.processing_latency_ms",
        mission_id: mission_id,
        source_endpoint_id: source_endpoint_id,
        spacecraft_id: Map.get(metadata, :spacecraft_id),
        transport_id: Map.get(metadata, :transport_id),
        ground_station_id:
          Map.get(metadata, :ground_station_id) || Map.get(metadata, :antenna_id),
        link_id: Map.get(metadata, :link_id) || Map.get(metadata, :link_assignment_id),
        adapter_key: Map.get(metadata, :adapter_key),
        value: duration_us / 1000.0,
        unit: "ms",
        observed_at: observed_at,
        error?: Map.get(metadata, :error?, false),
        measurements: measurements,
        metadata: metadata
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
    else
      _missing -> nil
    end
  end

  defp ingress_latency_sample_key(%{source_endpoint_id: source_endpoint_id})
       when is_binary(source_endpoint_id) and source_endpoint_id != "" do
    {:source_endpoint, source_endpoint_id}
  end

  defp ingress_latency_sample_key(%{mission_id: mission_id}), do: {:mission, mission_id}

  defp snapshot_metrics(metrics) do
    %{
      ingress_processing_latency_ms:
        metrics
        |> Map.get(:ingress_processing_latency_ms, %{})
        |> Map.values()
        |> Enum.sort_by(&{Map.get(&1, :mission_id), Map.get(&1, :source_endpoint_id, "")})
    }
  end

  defp resolve_client(%{tag: @client_tag} = client), do: client
  defp resolve_client(server), do: client(server)

  defp resolve_server(%{tag: @client_tag, server: server}), do: server
  defp resolve_server(server), do: server
end
