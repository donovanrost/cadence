defmodule Cadence.Dashboards.DashboardRegistryCostTest do
  @moduledoc """
  #1058: what a dashboard resolve reads of the data-source registry and writes of source health.

  - A resolve that carries ONE snapshot of the mission's registry (`DataSourceRegistry.with_snapshot/3`)
    asks the database nothing for each source request and stage; a snapshot of another mission is
    not used; the answer is the same as without one.
  - A re-observation of a source whose health is unchanged and was recorded within the touch
    interval writes nothing, and with the snapshot's status not even a read; a changed health is
    still recorded as a transition, and an unchanged one is touched once the interval has passed.
  - The exact and the fallback status keys are one statement, the exact one preferred.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Dashboards.{DataSourceRegistry, PlannedSourceRequest}
  alias Cadence.Management.DataSources
  alias Cadence.Projections.DataSources.Health
  alias Cadence.Projections.DataSources.Watermarks

  @org "org-registry-cost"
  @mission "mission-registry-cost"
  @t0 ~U[2026-11-28 12:00:00.000000Z]

  setup do
    persist_mission_scope(@org, @mission)
    persist_mission_scope(@org, "#{@mission}-other")
    DataSources.ensure_default_managed_sources!()
    previous = Application.get_env(:cadence, :data_sources)
    Application.put_env(:cadence, :data_sources, persisted?: true)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cadence, :data_sources, previous),
        else: Application.delete_env(:cadence, :data_sources)
    end)
  end

  defp request(mission \\ @mission) do
    %PlannedSourceRequest{
      request_id: "request-1",
      organization_id: @org,
      mission_id: mission,
      logical_source: :telemetry,
      observables: ["tlm.hk.battery_voltage"],
      data_context: %{realm: :flight},
      sampling: %{mode: :latest}
    }
  end

  defp queries(fun) do
    me = self()
    handler = "registry-cost-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measure, meta, _ -> send(me, {:query, meta.source}) end,
      nil
    )

    result = fun.()
    :telemetry.detach(handler)
    {result, drain([])}
  end

  defp drain(acc) do
    receive do
      {:query, source} -> drain([source | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp health(attrs \\ %{}) do
    Map.merge(
      %{
        organization_id: @org,
        mission_id: @mission,
        logical_source: :telemetry,
        data_source_id: "managed_questdb_primary",
        realm: :flight,
        dataset: "flight",
        source_health: :healthy,
        reason: :source_recovered,
        observed_at: @t0,
        payload: %{}
      },
      attrs
    )
  end

  describe "the registry snapshot" do
    test "a resolve with a snapshot asks the registry's tables nothing, and answers the same" do
      opts = DataSourceRegistry.with_snapshot([], @org, @mission)
      assert %{data_sources: [_ | _], data_bindings: [_ | _]} = opts[:registry_snapshot]

      {with_snapshot, snapshot_queries} =
        queries(fn -> for _ <- 1..4, do: DataSourceRegistry.resolve(request(), opts) end)

      assert Enum.filter(snapshot_queries, &String.starts_with?(&1 || "", "data_source")) == []

      {without, plain_queries} =
        queries(fn -> for _ <- 1..4, do: DataSourceRegistry.resolve(request(), []) end)

      assert length(plain_queries) >= 12
      assert with_snapshot == without
    end

    test "another mission's snapshot is not used, and with_snapshot leaves other opts alone" do
      opts = DataSourceRegistry.with_snapshot([], @org, "#{@mission}-other")

      {_result, queries} = queries(fn -> DataSourceRegistry.resolve(request(), opts) end)
      assert Enum.any?(queries, &String.starts_with?(&1 || "", "data_source"))

      assert DataSourceRegistry.with_snapshot([persisted?: false], @org, @mission) ==
               [persisted?: false]

      explicit = [data_sources: [], data_bindings: []]
      assert DataSourceRegistry.with_snapshot(explicit, @org, @mission) == explicit
    end
  end

  describe "source health on a read" do
    test "an unchanged, recently recorded health is not written again, and is a read-free no-op with the snapshot" do
      assert {:ok, _event, _status} = Health.record_source_health(health())

      [status] = Health.list_source_health_statuses(@org, @mission)
      assert status.last_seen_at == @t0

      # A second later: nothing is written (the status was last seen at @t0).
      later = DateTime.add(@t0, 1, :second)
      assert {:ok, :unchanged, _} = Health.record_source_health(health(%{observed_at: later}))
      t0 = @t0
      assert [%{last_seen_at: ^t0}] = Health.list_source_health_statuses(@org, @mission)

      # With the snapshot already holding the fresh status: no statement at all.
      snapshot = %{health_statuses: Health.list_source_health_statuses(@org, @mission)}

      {result, statements} =
        queries(fn ->
          Health.maybe_record_source_health(health(%{observed_at: later}),
            registry_snapshot: snapshot
          )
        end)

      assert result == :ok
      assert statements == []
    end

    test "a changed health is recorded as a transition, and an unchanged one is touched after the interval" do
      assert {:ok, _, _} = Health.record_source_health(health())

      assert {:ok, %{source_health: :unavailable}, _} =
               Health.record_source_health(
                 health(%{
                   source_health: :unavailable,
                   reason: :source_unavailable,
                   observed_at: DateTime.add(@t0, 1, :second)
                 })
               )

      touched = DateTime.add(@t0, 60, :second)

      assert {:ok, :unchanged, _} =
               Health.record_source_health(
                 health(%{
                   source_health: :unavailable,
                   reason: :source_unavailable,
                   observed_at: touched
                 })
               )

      assert [%{last_seen_at: ^touched}] = Health.list_source_health_statuses(@org, @mission)
    end

    test "the exact status key wins over the fallback, in one statement" do
      identity = health(%{source_binding_id: "binding-1"})

      fallback =
        health(%{
          source_binding_id: nil,
          realm: nil,
          dataset: nil,
          source_health: :degraded,
          reason: :source_degraded
        })

      assert {:ok, _, _} = Health.record_source_health(fallback)
      assert {:ok, %{source_health: :degraded}} = Health.fetch_status_for_identity(identity)

      assert {:ok, _, _} = Health.record_source_health(identity)

      {{:ok, status}, statements} = queries(fn -> Health.fetch_status_for_identity(identity) end)
      assert status.source_health == :healthy
      assert length(statements) == 1

      assert {:error, :source_health_status_not_found} =
               Health.fetch_status_for_identity(%{identity | data_source_id: "nope"})
    end
  end

  test "the watermark status lookup is one statement for both keys" do
    {result, statements} =
      queries(fn ->
        Watermarks.fetch_status_for_identity(%{
          organization_id: @org,
          mission_id: @mission,
          logical_source: :telemetry,
          data_source_id: "managed_questdb_primary",
          source_binding_id: "binding-1",
          realm: :flight,
          dataset: "flight"
        })
      end)

    assert {:error, :source_watermark_status_not_found} = result
    assert length(statements) == 1
  end
end
