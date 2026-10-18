defmodule CadenceWeb.OpsDirectoryPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Auth.Scope
  alias Cadence.Dashboards
  alias Cadence.Dashboards.{CurrentVersions, DirectoryActions, Document}
  alias Cadence.Reads.Dashboards.Directory
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )

  @renderer Path.expand(
              "../../../../frontend/modules/dashboards-and-exploration/src/features/directory/producer-render-check.mjs",
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
      conn: TestFixtures.member_conn(user),
      path: "/missions/#{mission.mission_id}/ops/dashboards"
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

    {:ok, all} = Directory.load(c.scope, mission(c), %{"archived" => "true"})
    {:ok, empty} = Directory.load(c.scope, mission(c), %{"query" => "nothing-matches"})
    render_check([model, all, empty])

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

  test "the host binds URL filters and consumes ordered, token-bound actions", c do
    path = c.path <> "?tags=thermal"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    assert %{"id" => "dashboards.directory", "status" => "ready"} = original
    assert [%{"id" => id, "starred" => false}] = original["data"]["model"]["rows"]
    command = %{"dashboard_id" => id, "starred" => true}

    assert action(view, path, %{original | "token" => Ecto.UUID.generate()}, "star", 1, command)[
             "ok"
           ] == false

    assert %{"status" => "rejected"} =
             action(view, path, original, "star", 2, command)["snapshot"]

    assert %{"status" => "ok", "page" => page} =
             action(view, path, original, "star", 1, command)["snapshot"]

    assert [%{"starred" => true}] = page["data"]["model"]["rows"]
    assert page["data"]["sequence"] == 1

    assert %{"status" => "rejected"} =
             action(view, path, original, "star", 1, command)["snapshot"]

    refresh(view, c.path)
    assert action(view, path, original, "star", 2, command)["ok"] == false
  end

  test "operators archive, restore and duplicate; other organizations cannot", c do
    {:ok, view, _} = live(c.conn, c.path)
    page = page(view)
    id = c.power.dashboard_id

    assert %{"status" => "ok", "page" => archived} =
             action(view, c.path, page, "archive", 1, %{"dashboard_id" => id})["snapshot"]

    refute Enum.any?(archived["data"]["model"]["rows"], &(&1["id"] == id))

    assert %{"status" => "ok"} =
             action(view, c.path, page, "restore", 2, %{"dashboard_id" => id})["snapshot"]

    assert %{"status" => "invalid", "code" => "invalid_name"} =
             action(view, c.path, page, "duplicate", 3, %{"dashboard_id" => id, "name" => " "})[
               "snapshot"
             ]

    assert %{"status" => "ok", "result" => %{"dashboard_id" => copy}, "page" => duplicated} =
             action(view, c.path, page, "duplicate", 4, %{
               "dashboard_id" => id,
               "name" => "Power copy"
             })[
               "snapshot"
             ]

    assert Enum.any?(
             duplicated["data"]["model"]["rows"],
             &(&1["id"] == copy and &1["name"] == "Power copy")
           )

    foreign = TestFixtures.persist_org!()
    outsider = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(outsider, foreign)

    other =
      Scope.new(%{
        user: outsider,
        organization_id: foreign.organization_id,
        organization_membership: membership
      })

    for {event, command} <- [
          {"archive", %{"dashboard_id" => id}},
          {"duplicate", %{"dashboard_id" => id, "name" => "Mine"}}
        ] do
      assert {:error, _} = DirectoryActions.execute(other, mission(c), event, command)
    end

    assert {:error, _} =
             DirectoryActions.execute(other, mission(c), "star", %{
               "dashboard_id" => id,
               "starred" => true
             })

    assert {:ok, %{starred: true}} =
             DirectoryActions.execute(member_scope(c), mission(c), "star", %{
               "dashboard_id" => id,
               "starred" => true
             })
  end

  test "the directory follows dashboards created and archived by other sessions", c do
    {:ok, view, _} = live(c.conn, c.path)
    assert length(page(view)["data"]["model"]["rows"]) == 2

    create(c, "Conjunction watch", "Close approaches", ["fdyn"])
    eventually(fn -> length(page(view)["data"]["model"]["rows"]) == 3 end)

    :ok = Dashboards.archive_document(org(c), mission(c), c.flight.dashboard_id)

    eventually(fn ->
      not Enum.any?(page(view)["data"]["model"]["rows"], &(&1["name"] == "Flight board"))
    end)
  end

  test "a revoked authenticated session cannot star a dashboard", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    action_request(view, c.path, original, "star", 1, %{
      "dashboard_id" => c.flight.dashboard_id,
      "starred" => true
    })

    assert_redirect(view, "/sign-in")
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

  defp render_check(models) do
    node = System.find_executable("node") || flunk("Node is required for the directory contract")
    pages = Enum.map(models, &%{model: &1, sequence: 0})

    {output, status} =
      System.cmd(node, ["--no-warnings", @renderer, Jason.encode!(pages)], stderr_to_stdout: true)

    assert status == 0, output
  end

  defp eventually(check, attempts \\ 40) do
    cond do
      check.() -> :ok
      attempts == 0 -> flunk("The directory did not follow the change")
      true -> retry(check, attempts)
    end
  end

  defp retry(check, attempts) do
    Process.sleep(25)
    eventually(check, attempts - 1)
  end

  defp org(c), do: c.org.organization_id
  defp mission(c), do: c.mission.mission_id

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp refresh(view, path) do
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
  end

  defp action(view, path, page, event, sequence, command) do
    action_request(view, path, page, event, sequence, command)
    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end

  defp action_request(view, path, page, event, sequence, command) do
    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => page["id"],
      "token" => page["token"],
      "event" => event,
      "input" => %{"sequence" => sequence, "command" => command}
    })
  end
end
