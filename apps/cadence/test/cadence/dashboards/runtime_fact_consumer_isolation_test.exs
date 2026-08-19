defmodule Cadence.Dashboards.RuntimeFactConsumerIsolationTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Catalog.Revision
  alias Cadence.Contacts.ScheduledContact

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DashboardResolveResult,
    Document,
    Frame,
    PlannedSourceRequest,
    RuntimeCache,
    RuntimeCacheKey,
    RuntimeFactConsumer,
    SourceResult
  }

  alias Cadence.Platform.EventBus

  @organization_id "organization-dashboard-fact-isolation"
  @mission_id "mission-dashboard-fact-isolation"

  @bus_names %{
    a: __MODULE__.BusA,
    b: __MODULE__.BusB
  }

  @cache_names %{
    a: __MODULE__.CacheA,
    b: __MODULE__.CacheB
  }

  @consumer_names %{
    a: __MODULE__.ConsumerA,
    b: __MODULE__.ConsumerB
  }

  test "two consumers isolate identical facts across bus and cache lifecycles" do
    cache_a = start_cache(:a)
    cache_b = start_cache(:b)
    bus_a = start_event_bus(:a)
    bus_b = start_event_bus(:b)
    consumer_a = start_consumer(:a)
    consumer_b = start_consumer(:b)

    catalog_entries = cache_entries(:telemetry)
    seed_cache(cache_a, catalog_entries)
    seed_cache(cache_b, catalog_entries)

    revision = %Revision{organization_id: @organization_id, mission_id: @mission_id}

    assert :ok = Cadence.Catalog.Facts.publish(bus_name(:a), revision)
    assert_cache_misses(cache_a, catalog_entries)
    assert_cache_hits(cache_b, catalog_entries)

    seed_cache(cache_a, catalog_entries)

    assert :ok = Cadence.Catalog.Facts.publish(bus_name(:b), revision)
    assert_cache_hits(cache_a, catalog_entries)
    assert_cache_misses(cache_b, catalog_entries)

    event_entries = cache_entries(:events, include_plan?: false)
    seed_cache(cache_a, event_entries)
    seed_cache(cache_b, event_entries)

    consumer_a_monitor = Process.monitor(consumer_a)
    bus_a_monitor = Process.monitor(bus_a)
    consumer_b_monitor = Process.monitor(consumer_b)
    bus_b_monitor = Process.monitor(bus_b)

    assert :ok = stop_supervised(consumer_child_id(:a))
    assert_receive {:DOWN, ^consumer_a_monitor, :process, ^consumer_a, _reason}

    assert :ok = stop_supervised(bus_child_id(:a))
    assert_receive {:DOWN, ^bus_a_monitor, :process, ^bus_a, _reason}

    assert Process.whereis(consumer_name(:b)) == consumer_b
    assert Process.whereis(bus_name(:b)) == bus_b
    assert_cache_hits(cache_b, event_entries)
    refute_received {:DOWN, ^consumer_b_monitor, :process, ^consumer_b, _reason}
    refute_received {:DOWN, ^bus_b_monitor, :process, ^bus_b, _reason}

    restarted_bus_a = start_event_bus(:a)
    restarted_consumer_a = start_consumer(:a)

    refute restarted_bus_a == bus_a
    refute restarted_consumer_a == consumer_a
    assert Process.whereis(consumer_name(:b)) == consumer_b
    assert Process.whereis(bus_name(:b)) == bus_b
    assert_cache_hits(cache_b, event_entries)

    contact = %ScheduledContact{organization_id: @organization_id, mission_id: @mission_id}

    assert :ok = Cadence.Contacts.Facts.publish(bus_name(:a), contact)
    assert_cache_misses(cache_a, event_entries)
    assert_cache_hits(cache_b, event_entries)

    seed_cache(cache_a, event_entries)

    assert :ok = Cadence.Contacts.Facts.publish(bus_name(:b), contact)
    assert_cache_hits(cache_a, event_entries)
    assert_cache_misses(cache_b, event_entries)
    assert Process.whereis(consumer_name(:b)) == consumer_b
    assert Process.whereis(bus_name(:b)) == bus_b
    refute_received {:DOWN, ^consumer_b_monitor, :process, ^consumer_b, _reason}
    refute_received {:DOWN, ^bus_b_monitor, :process, ^bus_b, _reason}
  end

  defp start_cache(set) do
    name = cache_name(set)

    pid =
      start_supervised!(%{
        id: cache_child_id(set),
        start: {RuntimeCache, :start_link, [[name: name]]},
        restart: :temporary
      })

    assert Process.whereis(name) == pid
    RuntimeCache.client(name)
  end

  defp start_event_bus(set) do
    name = bus_name(set)

    pid =
      start_supervised!(%{
        id: bus_child_id(set),
        start: {EventBus, :start_link, [[name: name, delivery: :sync, before_notify: nil]]},
        restart: :temporary
      })

    assert Process.whereis(name) == pid
    pid
  end

  defp start_consumer(set) do
    name = consumer_name(set)

    pid =
      start_supervised!(%{
        id: consumer_child_id(set),
        start:
          {RuntimeFactConsumer, :start_link,
           [
             [
               name: name,
               enabled?: true,
               event_bus: bus_name(set),
               runtime_cache: RuntimeCache.client(cache_name(set))
             ]
           ]},
        restart: :temporary
      })

    assert Process.whereis(name) == pid
    pid
  end

  defp cache_entries(logical_source, opts \\ []) do
    request = source_request(logical_source)
    source_key = RuntimeCacheKey.source_result(request)

    source_result = %SourceResult{request_id: request.request_id}

    frame_key =
      RuntimeCacheKey.frame(source_key,
        placement_id: "placement-dashboard-fact-isolation",
        frame_shape: frame_shape(logical_source)
      )

    frames = [
      %Frame{
        frame_id: "frame-dashboard-fact-isolation",
        source: logical_source,
        shape: frame_shape(logical_source)
      }
    ]

    entries = %{source_result: {source_key, source_result}, frame: {frame_key, frames}}

    if Keyword.get(opts, :include_plan?, true) do
      Map.put(entries, :plan, plan_entry(request))
    else
      entries
    end
  end

  defp plan_entry(%PlannedSourceRequest{} = source_request) do
    document = %Document{
      dashboard_id: "dashboard-fact-isolation",
      organization_id: @organization_id,
      mission_id: @mission_id,
      name: "Dashboard fact isolation"
    }

    resolve_request = %DashboardResolveRequest{
      organization_id: @organization_id,
      mission_id: @mission_id,
      dashboard_id: document.dashboard_id,
      document: document
    }

    key = RuntimeCacheKey.plan(resolve_request)

    result = %DashboardResolveResult{
      dashboard_id: document.dashboard_id,
      planned_source_requests: [source_request],
      plan_metadata: %{cache: %{plan_key: key}}
    }

    {key, result}
  end

  defp source_request(logical_source) do
    %PlannedSourceRequest{
      request_id: "source-dashboard-fact-isolation-#{logical_source}",
      organization_id: @organization_id,
      mission_id: @mission_id,
      logical_source: logical_source,
      observables: ["HK.counter"],
      sampling: %{mode: :latest}
    }
  end

  defp seed_cache(cache, entries) do
    Enum.each(entries, fn
      {:plan, {key, result}} ->
        assert :ok = RuntimeCache.put_plan(key, result, cache)

      {:source_result, {key, result}} ->
        assert :ok = RuntimeCache.put_source_result(key, result, cache)

      {:frame, {key, frames}} ->
        assert :ok = RuntimeCache.put_frame(key, frames, cache)
    end)
  end

  defp assert_cache_hits(cache, entries) do
    Enum.each(entries, fn
      {:plan, {key, result}} ->
        assert {:ok, ^result} = RuntimeCache.get_plan(key, cache)

      {:source_result, {key, result}} ->
        assert {:ok, ^result} = RuntimeCache.get_source_result(key, cache)

      {:frame, {key, frames}} ->
        assert {:ok, ^frames} = RuntimeCache.get_frame(key, cache)
    end)
  end

  defp assert_cache_misses(cache, entries) do
    Enum.each(entries, fn
      {:plan, {key, _result}} ->
        assert :miss = RuntimeCache.get_plan(key, cache)

      {:source_result, {key, _result}} ->
        assert :miss = RuntimeCache.get_source_result(key, cache)

      {:frame, {key, _frames}} ->
        assert :miss = RuntimeCache.get_frame(key, cache)
    end)
  end

  defp frame_shape(:events), do: :events
  defp frame_shape(_logical_source), do: :wide

  defp bus_name(set), do: Map.fetch!(@bus_names, set)
  defp cache_name(set), do: Map.fetch!(@cache_names, set)
  defp consumer_name(set), do: Map.fetch!(@consumer_names, set)

  defp bus_child_id(set), do: {__MODULE__, :bus, set}
  defp cache_child_id(set), do: {__MODULE__, :cache, set}
  defp consumer_child_id(set), do: {__MODULE__, :consumer, set}
end
