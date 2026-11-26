defmodule CadenceWeb.Console.ActivationConfigurationChangesAPITest do
  @moduledoc """
  #235 on L10: a spacecraft configuration request's detail says what changes, grouped by identical
  change (lead's final shape, 11-18 08:49:52Z): every distinct change once, exact counts, the
  first start's rows from nothing, the switches never rows, and the names of a group paged by
  `…/configuration-changes?group=N&offset=K`. Other requests carry `configuration_changes: null`.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: CatalogFixtures
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(org)
    user = TestFixtures.persist_user!(display_name: "Requester")
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    viewer = TestFixtures.persist_user!(display_name: "Viewer")
    TestFixtures.grant_membership!(viewer, org, role: :organization_admin)
    scope = scope(user, org, mission, membership)
    {o, m} = {org.organization_id, mission.mission_id}

    {first, rev_a, _endpoint} = CatalogFixtures.setup_imported_mission!(o, m)

    rev_b =
      CatalogFixtures.persist_imported_revision!(o, m,
        catalog_database_id: rev_a.catalog_database_id,
        revision_label: "Rev 2"
      )

    {:ok, mission} = Cadence.Missions.fetch_mission(o, m)

    # Two craft run on rev A (one direct activation), then drafts move both to rev B: the same
    # change, one group. A third starts for the first time on rev B.
    second = CatalogFixtures.persist_spacecraft!(o, m, display_name: "Second")
    policy!(scope, m, "direct")
    for craft <- [first, second], do: save!(scope, mission, craft, rev_a.catalog_revision_id)

    {:ok, request} = Review.request_many(scope, m, tokens(mission, [first, second]))
    {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)

    policy!(scope, m, "independent")
    for craft <- [first, second], do: save!(scope, mission, craft, rev_b.catalog_revision_id)
    third = CatalogFixtures.persist_spacecraft!(o, m, display_name: "Third")
    save!(scope, mission, third, rev_b.catalog_revision_id)

    {:ok, fleet} = Review.request_many(scope, m, tokens(mission, [first, second, third]))

    %{
      viewer: viewer,
      first: first,
      second: second,
      rev_a: rev_a,
      rev_b: rev_b,
      base: "/api/console/v1/missions/#{m}/activations",
      fleet: fleet.activation_request_id,
      direct: request.activation_request_id
    }
  end

  test "a fleet request: one group per distinct change, exact counts, first starts from nothing",
       c do
    changes = detail(c, c.fleet)["configuration_changes"]
    assert %{"total" => 3, "groups" => [_, _] = groups} = changes
    moved = Enum.find(groups, &(&1["first_start"] == false))
    started = Enum.find(groups, &(&1["first_start"] == true))

    # Both changed, so both lead (in the request's order); the same catalog move on two craft is
    # one group.
    assert %{
             "count" => 2,
             "first_start" => false,
             "telemetry_enabled" => false,
             "spacecraft" => names,
             "rows" => [
               %{
                 "field" => "catalog_revision",
                 "label" => "Catalog revision",
                 "before" => %{"id" => rev_a, "number" => number_a},
                 "after" => %{"id" => rev_b, "number" => number_b}
               }
             ]
           } = moved

    assert Enum.map(names, & &1["spacecraft_id"]) |> Enum.sort() ==
             Enum.sort([c.first.spacecraft_id, c.second.spacecraft_id])

    assert {rev_a, rev_b} == {c.rev_a.catalog_revision_id, c.rev_b.catalog_revision_id}
    assert {number_a, number_b} == {1, 2}

    # D2 (#543): each catalog revision the row names carries its composition. Rev A's one layer
    # names rev A (the first import); rev B may reuse it, so only its id is checked.
    [%{"before" => %{"composition" => before}, "after" => %{"composition" => later}}] =
      moved["rows"]

    assert %{
             "composition_id" => before_id,
             "number" => before_number,
             "imported_layers" => [%{"mount" => "/", "catalog_revision" => %{"id" => layer_rev}}]
           } = before

    assert is_binary(before_id) and is_integer(before_number)
    assert layer_rev == rev_a
    assert %{"composition_id" => later_id} = later
    assert is_binary(later_id)

    # From nothing: every set field is a row with before null; the switches never are.
    assert %{"count" => 1, "first_start" => true, "spacecraft" => [%{"name" => "Third"}]} =
             started

    assert Enum.all?(started["rows"], &is_nil(&1["before"]))
    fields = Enum.map(started["rows"], & &1["field"])
    assert "catalog_revision" in fields and "handled_apids" in fields
    refute Enum.any?(fields, &(&1 in ["telemetry_enabled", "commanding_enabled"]))
  end

  test "the names route pages a group; an unknown group is 404; a decided request carries null",
       c do
    groups = detail(c, c.fleet)["configuration_changes"]["groups"]
    index = Enum.find_index(groups, &(&1["count"] == 2))
    assert is_integer(index)

    assert %{"data" => %{"spacecraft" => [_, _], "next_offset" => nil}} =
             names(c, c.fleet, "group=#{index}") |> json_response(200)

    assert %{"data" => %{"spacecraft" => [_], "next_offset" => nil}} =
             names(c, c.fleet, "group=#{index}&offset=1") |> json_response(200)

    assert %{"error" => %{"code" => "configuration_changes_group_not_found"}} =
             names(c, c.fleet, "group=9") |> json_response(404)

    assert %{"error" => %{"code" => "invalid_params"}} =
             names(c, c.fleet, "group=x") |> json_response(422)

    # A decided request (the first, direct one, applied) carries none: what runs is its content.
    # Its reviewed craft still read, on every state (lead), for the console's link.
    direct = detail(c, c.direct)
    assert direct["configuration_changes"] == nil
    first_id = c.first.spacecraft_id

    second_id = c.second.spacecraft_id

    assert %{"spacecraft" => decided, "spacecraft_total" => 2} = direct
    assert Enum.map(decided, & &1["id"]) |> Enum.sort() == Enum.sort([first_id, second_id])

    assert %{"spacecraft_total" => 3, "spacecraft" => [_, _, _]} = detail(c, c.fleet)
  end

  defp detail(c, id) do
    c.viewer
    |> TestFixtures.member_conn()
    |> get(c.base <> "/" <> id)
    |> json_response(200)
    |> Map.fetch!("data")
    |> then(&Map.get(&1, "request", &1))
  end

  defp names(c, id, query),
    do:
      c.viewer
      |> TestFixtures.member_conn()
      |> get(c.base <> "/#{id}/configuration-changes?" <> query)

  defp tokens(mission, crafts),
    do: Map.new(crafts, &{&1.spacecraft_id, Drafts.snapshot(mission, &1).token})

  defp policy!(scope, mission_id, requirement) do
    policy = ActivationPolicy.load(scope.organization_id, mission_id)

    {:ok, _} =
      ActivationPolicy.save(scope, mission_id, policy.token, %{
        "value" => %{"approval_requirement" => requirement}
      })
  end

  defp save!(scope, mission, craft, catalog) do
    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => catalog,
        "handled_apids" => [42]
      })

    {:ok, _} =
      Drafts.save(
        scope,
        mission.mission_id,
        craft.spacecraft_id,
        Drafts.snapshot(mission, craft).token,
        document
      )
  end

  defp scope(user, org, mission, membership) do
    %Scope{
      actor_kind: :user,
      user: user,
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      organization_membership: membership,
      capabilities: MapSet.new([:organization_admin])
    }
  end
end
