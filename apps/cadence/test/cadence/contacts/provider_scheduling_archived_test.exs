defmodule Cadence.Contacts.ProviderSchedulingArchivedTest do
  @moduledoc """
  An archived provider's routes are refused everywhere scheduling resolves them (#985). Archiving
  adds a newer, archived version while the transport keeps pinning the older active one; that
  pinned version alone would still look schedulable.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.ProviderScheduling
  alias Cadence.Contacts.SingleBookings.Search
  alias Cadence.ContactScheduleFixtures
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.MissionProviders.Archived
  alias Cadence.TestSupport.FakeProviderClient

  setup do
    fx = ContactScheduleFixtures.setup_schedule()

    {:ok, archived} =
      GroundNetworks.archive_provider(fx.organization_id, fx.mission_id, fx.provider.provider_id)

    # The transport still pins the older, active version.
    assert archived.version > fx.provider.version
    assert fx.transport.mission_provider_version == fx.provider.version
    fx
  end

  test "the route list refuses the route with mission_provider_archived on its rule", c do
    assert {:ok, %{routes: [], findings: findings}} =
             ProviderScheduling.list_ready_downlink_routes(
               c.organization_id,
               c.mission_id,
               c.spacecraft.spacecraft_id
             )

    assert %{code: :mission_provider_archived, resource_id: rule_id} =
             Enum.find(findings, &(&1.code == :mission_provider_archived))

    assert rule_id == c.rule.routing_rule_id
  end

  test "the fleet route list (fleet search, plans, ephemeris uploads) offers nothing", c do
    assert {:ok, routes, _providers} =
             ProviderScheduling.list_ready_downlink_routes_for_fleet(
               c.organization_id,
               c.mission_id,
               [c.spacecraft.spacecraft_id]
             )

    assert {:ok, %{routes: []}} = Map.fetch!(routes, c.spacecraft.spacecraft_id)
  end

  test "plan execution's route resolution and an opportunity search never reach it", c do
    assert {:error, :provider_scheduling_route_not_ready} =
             ProviderScheduling.resolve_ready_downlink_route(
               c.organization_id,
               c.mission_id,
               c.spacecraft.spacecraft_id,
               c.route.route_key
             )

    starts_at = DateTime.utc_now() |> DateTime.add(120) |> DateTime.truncate(:second)

    assert {:error, :provider_scheduling_route_not_ready} =
             ProviderScheduling.search_opportunities(
               c.organization_id,
               c.mission_id,
               c.route.route_key,
               %{
                 "spacecraft_id" => c.spacecraft.spacecraft_id,
                 "starts_at" => DateTime.to_iso8601(starts_at),
                 "ends_at" => DateTime.to_iso8601(DateTime.add(starts_at, 3_600))
               },
               client: FakeProviderClient,
               on_search: fn _params -> flunk("an archived provider was searched") end
             )
  end

  test "Book a pass offers nothing and names the refusal", c do
    from = DateTime.utc_now() |> DateTime.add(120) |> DateTime.truncate(:second)

    assert {:ok, %{offers: [], not_ready: not_ready}} =
             Search.run(c.scope, c.mission_id, %{
               "spacecraft_id" => c.spacecraft.spacecraft_id,
               "from" => DateTime.to_iso8601(from),
               "to" => DateTime.to_iso8601(DateTime.add(from, 3_600))
             })

    assert Enum.any?(not_ready, &(&1.code == "mission_provider_archived"))
  end

  test "archived_since names only pinned versions older than an archived one", c do
    key = {c.provider.provider_id, c.provider.version}
    newer = {c.provider.provider_id, c.provider.version + 5}

    assert Archived.archived_since(c.organization_id, c.mission_id, [key, newer]) ==
             MapSet.new([key])

    assert Archived.archived_since(c.organization_id, c.mission_id, []) == MapSet.new()
  end
end
