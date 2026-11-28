defmodule Cadence.Reads.DerivedPointsTest do
  @moduledoc """
  Derived parameters in the operator point catalog (#451 T4b), from a revision compiled through the
  real compiler (`DerivedPointFixtures`): the catalog lists the algorithm's output beside the
  packet field, keyed by the output parameter's semantic id, with the unit and type its
  declaration gives; the readers that ask the catalog (PointInfo, SpacecraftLive, point search,
  the dashboards' data-link resolver) resolve it; a revision's derived points are built once and
  a read runs the same queries at 5 and at 50 spacecraft.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Dashboards.{DataLink, DataLinkResolver}
  alias Cadence.DerivedPointFixtures, as: Fixtures
  alias Cadence.Ops.PointCatalog
  alias Cadence.Reads.{DerivedPoints, PointInfo, PointSearch, SpacecraftLive}
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore

  @org "org-derived-points"

  setup do
    mission = "mission-derived-#{System.unique_integer([:positive])}"
    persist_mission_scope(@org, mission)
    %{mission: mission, model: Fixtures.activate!(@org, mission)}
  end

  test "the catalog lists the algorithm's output with its unit and type, beside the packet field",
       c do
    assert [packet, derived] = PointCatalog.list_points(@org, c.mission)

    assert %{point_id: "HK.raw_counter", source: :packet, parameter_id: raw_id} = packet
    assert raw_id == c.model.raw_id

    assert derived == %{
             point_id: c.model.derived_id,
             parameter_id: c.model.derived_id,
             qualified_name: Fixtures.derived_name(),
             name: Fixtures.derived_name(),
             packet_name: nil,
             field_name: nil,
             unit: "V",
             data_type: :float,
             base_type: "float",
             space_system_id: c.model.space_system_id,
             source: :derived,
             stale_timeout_ms: nil,
             description: nil
           }

    assert is_binary(c.model.space_system_id)
    assert PointCatalog.resolve([packet, derived], Fixtures.derived_name()) == derived
  end

  test "PointInfo and SpacecraftLive resolve the derived point with its unit", c do
    assert %{unit: "V"} = Map.fetch!(PointInfo.by_id(@org, c.mission), c.model.derived_id)
    assert PointInfo.fetch(@org, c.mission, c.model.derived_id).unit == "V"

    assert [%{point_id: id, unit: "V", type: "numeric"}] =
             SpacecraftLive.points(@org, c.mission, [c.model.derived_id])

    assert id == c.model.derived_id
  end

  test "the dashboards' data-link resolver resolves the derived point", c do
    link = %DataLink{
      label: "Bus volts",
      target: :telemetry_point,
      target_id: c.model.derived_id,
      source: :warning
    }

    assert {:ok, inspector} =
             DataLinkResolver.resolve(link, organization_id: @org, mission_id: c.mission)

    assert inspector.status == :resolved
    refute (inspector.message || "") =~ "not present"

    rows = Map.new(inspector.rows, &{&1.label, &1.value})
    assert rows["Point"] == c.model.derived_id
    assert rows["Parameter"] == Fixtures.derived_name()
    assert rows["Unit"] == "V"
    refute Map.has_key?(rows, "Packet")
  end

  test "point search lists the derived point from the catalog", c do
    assert [point] = PointSearch.search(@org, c.mission, %{q: "bus_volts"})

    assert %{
             name: name,
             unit: "V",
             subsystem: "Derived",
             type: "numeric",
             latest: nil
           } = point

    assert point.id == c.model.derived_id
    assert name == Fixtures.derived_name()
  end

  test "a revision's derived points are built once and kept", c do
    assert [_derived] = DerivedPoints.list(@org, c.mission, c.model.revision_id)
    # The cache writes asynchronously; this call returns after the cast was handled.
    :sys.get_state(DerivedPoints)

    assert [{_key, _at, [%{unit: "V"}]}] =
             :ets.lookup(DerivedPoints, {@org, c.mission, c.model.revision_id})

    assert DerivedPoints.list(@org, c.mission, nil) == []
  end

  test "a catalog and PointInfo read run the same queries at 5 and at 50 spacecraft" do
    counts =
      for fleet <- [5, 50] do
        mission = "mission-derived-fleet-#{fleet}-#{System.unique_integer([:positive])}"
        persist_mission_scope(@org, mission)
        %{derived_id: derived_id} = Fixtures.activate!(@org, mission)
        persist_fleet(mission, fleet)

        # Cold: the first read builds the revision's derived points.
        {cold, points} = queries(fn -> PointCatalog.list_points(@org, mission) end)
        assert Enum.any?(points, &(&1.point_id == derived_id))
        :sys.get_state(DerivedPoints)

        {warm, _points} = queries(fn -> PointCatalog.list_points(@org, mission) end)
        {info, by_id} = queries(fn -> PointInfo.by_id(@org, mission) end)
        assert %{unit: "V"} = by_id[derived_id]

        {cold, warm, info}
      end

    assert [{cold, warm, info}, {cold, warm, info}] = counts
    # The cached read is the activation and its binding set, nothing per revision.
    assert warm < cold
  end

  defp persist_fleet(mission, count) do
    for n <- 1..count do
      {:ok, _} =
        SpacecraftStore.persist_spacecraft(
          @org,
          Spacecraft.new(%{
            spacecraft_id: "#{mission}-sc-#{n}",
            organization_id: @org,
            mission_id: mission,
            display_name: "SC-#{n}",
            scid: n
          })
        )
    end
  end

  # The Repo queries `fun` runs in this process, and its result.
  defp queries(fun) do
    test_pid = self()
    handler_id = "derived-points-queries-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:cadence, :repo, :query],
        fn _event, _measurements, _metadata, _config ->
          if self() == test_pid, do: send(test_pid, :derived_points_query)
        end,
        nil
      )

    result =
      try do
        fun.()
      after
        :telemetry.detach(handler_id)
      end

    {drain(0), result}
  end

  defp drain(count) do
    receive do
      :derived_points_query -> drain(count + 1)
    after
      0 -> count
    end
  end
end
