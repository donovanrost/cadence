defmodule Cadence.Control.ScidRoutesTest do
  @moduledoc """
  #1078 P5 slice E1b-1: an endpoint's SCID routes are built from two reads, the endpoint and the
  spacecraft it and its relay set name, however many origins the set has. An origin craft that was
  archived is kept as archived (its frames are refused with a reason), one without a SCID is left
  out, and a read that finds nothing checks nothing.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Control.ScidRoutes, as: Builder
  alias Cadence.Protocol.ScidRoutes
  alias Cadence.SourceEndpoints
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore

  setup do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    org = "org-scid-routes-" <> suffix
    mission = "mission-scid-routes-" <> suffix
    persist_mission_scope(org, mission)
    %{org: org, mission: mission}
  end

  test "a relay's routes: own craft, active origins, an archived one, no SCID left out", c do
    relay = craft!(c, "relay", 11)
    active = craft!(c, "active", 21)
    archived = craft!(c, "archived", 31)
    craft!(c, "no-scid", nil)

    {:ok, _} =
      SpacecraftStore.archive_spacecraft(c.org, c.mission, archived.spacecraft_id, %{
        "kind" => "test"
      })

    endpoint = endpoint!(c, relay)

    {:ok, _} =
      SourceEndpoints.write_relay(c.org, c.mission, endpoint.source_endpoint_id, %{
        "origin_spacecraft_ids" => [
          active.spacecraft_id,
          archived.spacecraft_id,
          id(c, "no-scid"),
          "sc-gone"
        ]
      })

    routes = Builder.build(c.org, c.mission, endpoint.source_endpoint_id)

    assert routes.own_scid == 11
    assert routes.own_spacecraft_id == relay.spacecraft_id
    assert ScidRoutes.classify(routes, 11) == :direct
    assert ScidRoutes.classify(routes, 21) == {:relayed, active.spacecraft_id}
    assert ScidRoutes.classify(routes, 31) == {:archived, archived.spacecraft_id}
    assert ScidRoutes.classify(routes, 99) == :mismatch
    assert map_size(routes.routes) == 2
  end

  test "an endpoint that isn't a relay checks its own craft's SCID only", c do
    craft = craft!(c, "plain", 7)
    endpoint = endpoint!(c, craft)

    routes = Builder.build(c.org, c.mission, endpoint.source_endpoint_id)

    assert routes.own_scid == 7
    refute ScidRoutes.relay?(routes)
    assert ScidRoutes.classify(routes, 8) == :mismatch
  end

  test "a craft with no SCID, or an endpoint that can't be read, checks nothing", c do
    endpoint = endpoint!(c, craft!(c, "unnumbered", nil))

    refute ScidRoutes.checks?(Builder.build(c.org, c.mission, endpoint.source_endpoint_id))
    refute ScidRoutes.checks?(Builder.build(c.org, c.mission, "no-such-endpoint"))
  end

  test "the reads don't grow with the relay set", c do
    relay = craft!(c, "big-relay", 1)
    endpoint = endpoint!(c, relay)

    sizes =
      for size <- [3, 60] do
        # SCIDs are unique in a mission, and 10 bits: each size takes its own range.
        base = if size == 3, do: 200, else: 300
        ids = for n <- 1..size, do: craft!(c, "origin-#{size}-#{n}", base + n).spacecraft_id

        {:ok, _} =
          SourceEndpoints.write_relay(c.org, c.mission, endpoint.source_endpoint_id, %{
            "origin_spacecraft_ids" => ids
          })

        {routes, queries} =
          count_queries(fn -> Builder.build(c.org, c.mission, endpoint.source_endpoint_id) end)

        assert map_size(routes.routes) == size
        queries
      end

    assert [same, same] = sizes
    assert same == 2
  end

  defp craft!(c, name, scid) do
    craft =
      Spacecraft.new(%{
        spacecraft_id: id(c, name),
        mission_id: c.mission,
        display_name: name,
        scid: scid
      })

    {:ok, persisted} = SpacecraftStore.persist_spacecraft(c.org, craft)
    persisted
  end

  defp id(c, name), do: "sc-#{name}-#{c.mission}"

  defp endpoint!(c, craft) do
    {:ok, endpoint} = SourceEndpoints.ensure_managed_source_endpoint(c.org, craft)
    endpoint
  end

  defp count_queries(fun) do
    owner = self()
    counter = :counters.new(1, [])
    handler = make_ref()

    :ok =
      :telemetry.attach(
        handler,
        [:cadence, :repo, :query],
        fn _event, _measurements, _metadata, _config ->
          if self() == owner, do: :counters.add(counter, 1, 1)
        end,
        nil
      )

    try do
      {fun.(), :counters.get(counter, 1)}
    after
      :telemetry.detach(handler)
    end
  end
end
