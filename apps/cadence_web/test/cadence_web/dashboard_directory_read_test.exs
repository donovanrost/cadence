defmodule CadenceWeb.DashboardDirectoryReadTest do
  @moduledoc """
  The dashboards directory read model (`Reads.Dashboards.Directory`), which the console's directory
  API serves. The legacy page and its frontend contract check went with L8a; the cross-organization
  and revoked-session checks are in `Console.DashboardDirectoryAPITest`.
  """
  use CadenceWeb.ConnCase, async: false
  alias Cadence.Auth.Scope
  alias Cadence.Dashboards
  alias Cadence.Dashboards.{CurrentVersions, DirectoryActions, Document}
  alias Cadence.Reads.Dashboards.Directory
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    context = %{
      org: org,
      user: user,
      scope: scope,
      mission: mission,
      base: Dashboards.load_document!(@fixture),
      conn: TestFixtures.member_conn(user)
    }

    flight = create(context, "Flight board", "Thermal monitoring", ["flight", "thermal"])
    power = create(context, "Power board", "Bus voltage", ["flight", "eps"])
    archived = create(context, "Archived board", "Old telemetry", ["old"])

    :ok =
      Dashboards.archive_document(org.organization_id, mission.mission_id, archived.dashboard_id)

    Map.merge(context, %{flight: flight, power: power, archived: archived})
  end

  test "filters by text, every chosen tag, stars and archive; sorts and attributes saves", c do
    star(c, c.flight)

    {:ok, _} =
      Dashboards.record_dashboard_view(org(c), mission(c), c.user.user_id, c.power.dashboard_id)

    assert {:ok, model} = Directory.load(c.scope, mission(c))
    assert model.version == 2
    assert model.author
    assert Enum.map(model.rows, & &1.name) |> Enum.sort() == ["Flight board", "Power board"]
    assert model.available_tags == ["eps", "flight", "thermal"]
    flight = Enum.find(model.rows, &(&1.id == c.flight.dashboard_id))
    assert %{starred: true, archived: false, updated_by: name, updated_at: at} = flight
    assert name == c.user.display_name
    assert is_binary(at)
    assert [%{id: starred}] = model.shortcuts.starred
    assert starred == c.flight.dashboard_id
    assert [%{id: viewed, viewed_at: viewed_at}] = model.shortcuts.recent
    assert viewed == c.power.dashboard_id and is_binary(viewed_at)

    assert names(c, %{"query" => "voltage"}) == ["Power board"]
    assert names(c, %{"tags" => "flight,thermal"}) == ["Flight board"]

    assert names(c, %{"tags" => "flight", "sort" => "name_desc"}) == [
             "Power board",
             "Flight board"
           ]

    assert names(c, %{"starred" => "true"}) == ["Flight board"]

    assert names(c, %{"archived" => "true", "sort" => "name"}) ==
             ["Archived board", "Flight board", "Power board"]

    # Bookmarks from the earlier directory still resolve.
    assert names(c, %{"lifecycle" => "all", "tag" => "old", "sort" => "widgets"}) ==
             ["Archived board"]

    other = member_scope(c)

    assert {:ok, %{rows: rows, shortcuts: %{starred: []}}} =
             Directory.load(other, mission(c))

    refute Enum.any?(rows, & &1.starred)
  end

  test "bounds pagination and rejects malformed input and foreign scopes", c do
    for n <- 1..49, do: create(c, "Board #{String.pad_leading(to_string(n), 2, "0")}", nil, [])

    assert {:ok, %{rows: first, total: 51, pages: 2}} =
             Directory.load(c.scope, mission(c), %{"sort" => "name"})

    assert length(first) == 50

    assert {:ok, %{rows: [_], filters: %{"page" => 2}}} =
             Directory.load(c.scope, mission(c), %{"sort" => "name", "page" => "2"})

    for params <- [
          %{"page" => "0"},
          %{"page" => "1.5"},
          %{"query" => %{}},
          %{"starred" => "yes"},
          %{"lifecycle" => "deleted"},
          %{"tags" => Enum.map_join(1..11, ",", &"t#{&1}")},
          %{"unknown" => "x"}
        ] do
      assert {:error, _} = Directory.load(c.scope, mission(c), params)
    end

    for scope <- [
          %{c.scope | user: nil},
          %{c.scope | organization_membership: nil},
          %{c.scope | mission_id: "foreign"}
        ] do
      assert {:error, _} = Directory.load(scope, mission(c))
    end
  end

  defp create(c, name, description, tags) do
    %Document{} = base = c.base

    document = %Document{
      base
      | organization_id: org(c),
        mission_id: mission(c),
        dashboard_id: "directory-#{System.unique_integer([:positive])}",
        name: name,
        description: description,
        metadata: Map.put(base.metadata, :tags, tags)
    }

    {:ok, created} = CurrentVersions.create(org(c), document, created_by: c.user.user_id)
    created
  end

  defp star(c, dashboard),
    do:
      {:ok, _} =
        DirectoryActions.execute(c.scope, mission(c), "star", %{
          "dashboard_id" => dashboard.dashboard_id,
          "starred" => true
        })

  defp names(c, params) do
    {:ok, model} = Directory.load(c.scope, mission(c), params)
    Enum.map(model.rows, & &1.name)
  end

  defp member_scope(c) do
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, c.org)
    Scope.new(%{user: user, organization_id: org(c), organization_membership: membership})
  end

  defp org(c), do: c.org.organization_id
  defp mission(c), do: c.mission.mission_id
end
