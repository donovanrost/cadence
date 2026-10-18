defmodule Cadence.Reads.SpacecraftCommandingTest do
  use Cadence.DataCase, async: false
  alias Cadence.Auth.Scope
  alias Cadence.Reads.SpacecraftCommanding
  alias Cadence.SourceEndpoints.SourceEndpoint

  alias Cadence.{
    SourceEndpoints,
    Spacecraft,
    SpacecraftStore,
    SpacecraftType,
    SpacecraftTypeStore
  }

  @org "org-commanding-owner"
  @mission "mission-commanding-owner"
  @probe Path.expand(
           "../../../../../frontend/modules/commanding/src/features/spacecraft-commanding/producer-consumer-probe.mjs",
           __DIR__
         )

  setup do
    persist_mission_scope(@org, @mission)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @org,
      user: %{user_id: "command-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    %{scope: scope}
  end

  test "exact profile version and counted spacecraft endpoints reach the public component", c do
    profile =
      SpacecraftType.new(%{
        mission_id: @mission,
        display_name: "Reviewed bus",
        downlink_protocol: :tm,
        uplink_protocol: :tc
      })

    assert {:ok, pinned} = SpacecraftTypeStore.persist_spacecraft_type(@org, profile)

    assert {:ok, _newer} =
             SpacecraftTypeStore.persist_spacecraft_type(@org, %{
               pinned
               | version: 2,
                 display_name: "Newer bus",
                 uplink_protocol: :uslp
             })

    craft =
      craft("owned", spacecraft_type_id: pinned.spacecraft_type_id, spacecraft_type_version: 1)

    other = craft("other", scid: nil)

    for i <- 1..26,
        do: endpoint("owned-#{String.pad_leading(to_string(i), 2, "0")}", craft.spacecraft_id)

    endpoint("mission-only", nil)
    endpoint("foreign-craft", other.spacecraft_id)

    assert {:ok, doc} =
             SpacecraftCommanding.load(c.scope, @mission, craft.spacecraft_id, %{"page" => "2"})

    assert doc["profile"]["version"] == 1
    assert doc["profile"]["name"] == "Reviewed bus"
    assert doc["profile"]["uplink"] == "tc"
    assert doc["endpoints"]["total_count"] == 26
    assert [%{"id" => "owned-26"}] = doc["endpoints"]["items"]
    refute Map.has_key?(doc, "runtime_ready")
    {output, status} = System.cmd("node", [@probe, Jason.encode!(doc)], stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "SPACECRAFT_COMMANDING_CONSUMER_OK"

    if directory = System.get_env("CADENCE_SPACECRAFT_COMMANDING_FIXTURES") do
      File.mkdir_p!(directory)
      File.write!(Path.join(directory, "pinned-last.json"), Jason.encode!(doc))
    end

    assert {:ok, searched} =
             SpacecraftCommanding.load(c.scope, @mission, craft.spacecraft_id, %{
               "page" => "100",
               "query" => "owned-26"
             })

    assert searched["query"] == %{"page" => 1, "query" => "owned-26"}
    assert searched["endpoints"]["total_count"] == 1
  end

  test "unbound and missing pinned profile versions are distinct without substituting the latest",
       c do
    unbound = craft("unbound")
    assert {:ok, data} = SpacecraftCommanding.load(c.scope, @mission, unbound.spacecraft_id)
    assert data["profile"]["status"] == "unbound"

    missing =
      craft("missing",
        spacecraft_type_id: "missing-profile",
        spacecraft_type_version: 7,
        scid: nil
      )

    assert {:ok, data} = SpacecraftCommanding.load(c.scope, @mission, missing.spacecraft_id)
    assert data["profile"]["status"] == "unavailable"
    assert data["profile"]["id"] == "missing-profile"
    assert data["profile"]["version"] == 7
    assert data["profile"]["uplink"] == nil
    assert data["endpoints"]["total_count"] == 0
  end

  test "scope and query admission fail closed", c do
    craft = craft("owned")

    for params <- [
          %{"page" => "0"},
          %{"query" => "bad\n"},
          %{"spacecraft_id" => "foreign"},
          %{"page" => "100001"}
        ] do
      assert {:error, :unavailable} =
               SpacecraftCommanding.load(c.scope, @mission, craft.spacecraft_id, params)
    end

    for scope <- [
          %{c.scope | organization_id: "foreign"},
          %{c.scope | mission_id: "foreign"},
          %{c.scope | actor_kind: :service},
          %{c.scope | organization_membership: nil}
        ] do
      assert {:error, :unavailable} =
               SpacecraftCommanding.load(scope, @mission, craft.spacecraft_id)
    end

    assert {:error, :unavailable} = SpacecraftCommanding.load(c.scope, @mission, "absent")
  end

  defp craft(id, opts \\ []) do
    value =
      Spacecraft.new(
        Map.merge(
          %{mission_id: @mission, spacecraft_id: id, display_name: id, scid: 0},
          Map.new(opts)
        )
      )

    assert {:ok, value} = SpacecraftStore.persist_spacecraft(@org, value)
    value
  end

  defp endpoint(id, craft) do
    value =
      SourceEndpoint.new(%{
        mission_id: @mission,
        source_endpoint_id: id,
        spacecraft_id: craft,
        display_name: id,
        scid: 0,
        metadata: %{"private" => "must not project"}
      })

    assert {:ok, value} = SourceEndpoints.persist_source_endpoint(@org, value)
    value
  end
end
