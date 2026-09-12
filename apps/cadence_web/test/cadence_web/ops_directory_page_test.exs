defmodule CadenceWeb.OpsDirectoryPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Auth.Scope
  alias Cadence.Dashboards
  alias Cadence.Dashboards.{DirectoryActions, Document, Documents}
  alias Cadence.Reads.Dashboards.{Directory, Workspace}
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

    base = Dashboards.load_document!(@fixture)

    context = %{
      org: org,
      user: user,
      scope: scope,
      mission: mission,
      base: base,
      conn: TestFixtures.member_conn(user),
      path: "/missions/#{mission.mission_id}/ops/dashboards"
    }

    active = persist(context, "active", "Flight board", "Thermal monitoring", ["flight"])
    archived = persist(context, "archived", "Archived board", "Old telemetry", ["old"])

    :ok =
      Dashboards.archive_document(org.organization_id, mission.mission_id, archived.dashboard_id,
        expected_version: 1
      )

    Map.merge(context, %{active: active, archived: archived})
  end

  test "reads actual lifecycle, description and tag search, personal stars and name ordering",
       c do
    {:ok, _} =
      DirectoryActions.execute(c.scope, c.mission.mission_id, "star", %{
        "dashboard_id" => c.active.dashboard_id,
        "starred" => true
      })

    assert {:ok, model} = Directory.load(c.scope, c.mission.mission_id)
    assert [%{id: id, starred: true, widget_count: count, published_version: nil}] = model.rows
    assert id == c.active.dashboard_id
    assert count == length(c.active.placements)
    assert model.available_tags == ["flight", "old"]

    assert {:ok, %{rows: [_]}} =
             Directory.load(c.scope, c.mission.mission_id, %{"query" => "thermal"})

    assert {:ok, %{rows: [_]}} =
             Directory.load(c.scope, c.mission.mission_id, %{
               "query" => "flight",
               "tag" => "flight"
             })

    assert {:ok, %{rows: [], total: 0}} =
             Directory.load(c.scope, c.mission.mission_id, %{"tag" => "missing"})

    assert {:ok, %{rows: [row]}} =
             Directory.load(c.scope, c.mission.mission_id, %{"lifecycle" => "archived"})

    assert row.id == c.archived.dashboard_id
    assert row.lifecycle == "archived"

    assert {:ok, %{rows: [first, second]}} =
             Directory.load(c.scope, c.mission.mission_id, %{
               "lifecycle" => "all",
               "sort" => "name"
             })

    assert [first.name, second.name] == ["Archived board", "Flight board"]
    {:ok, all} = Directory.load(c.scope, c.mission.mission_id, %{"lifecycle" => "all"})
    {:ok, empty} = Directory.load(c.scope, c.mission.mission_id, %{"query" => "nothing-matches"})

    node =
      System.find_executable("node") || flunk("Node is required for the directory DTO contract")

    {output, status} =
      System.cmd(node, ["--no-warnings", @renderer, Jason.encode!([model, all, empty])],
        stderr_to_stdout: true
      )

    assert status == 0, output
    other_user = TestFixtures.persist_user!()
    other_membership = TestFixtures.grant_membership!(other_user, c.org)

    other =
      Scope.new(%{
        user: other_user,
        organization_id: c.org.organization_id,
        organization_membership: other_membership
      })

    assert {:ok, %{rows: [%{starred: false}]}} = Directory.load(other, c.mission.mission_id)
  end

  test "directory distinguishes unpublished drafts from published dashboards", c do
    assert {:ok, %{rows: [%{published_version: nil}]}} =
             Directory.load(c.scope, c.mission.mission_id)

    assert {:ok, requirement} =
             Workspace.publication_requirement(
               c.scope,
               c.mission.mission_id,
               c.active.dashboard_id
             )

    assert requirement.author
    refute Map.has_key?(requirement, :name)

    assert {:error, :unavailable} =
             Workspace.publication_requirement(
               c.scope,
               c.mission.mission_id,
               c.archived.dashboard_id
             )

    assert {:error, :unavailable} =
             Workspace.publication_requirement(
               c.scope,
               c.mission.mission_id,
               "missing"
             )

    assert {:ok, _} =
             Documents.publish(
               c.org.organization_id,
               c.mission.mission_id,
               c.active.dashboard_id,
               1,
               expected_version: 1
             )

    assert {:ok, %{rows: [%{published_version: 1}]}} =
             Directory.load(c.scope, c.mission.mission_id)

    assert {:error, :unavailable} =
             Workspace.publication_requirement(
               c.scope,
               c.mission.mission_id,
               c.active.dashboard_id
             )
  end

  test "bounds pagination and rejects malformed input and foreign scopes", c do
    for n <- 1..51,
        do: persist(c, "page-#{n}", "Board #{String.pad_leading(to_string(n), 2, "0")}", nil, [])

    assert {:ok, %{rows: first, total: 52, pages: 2}} =
             Directory.load(c.scope, c.mission.mission_id, %{"sort" => "name"})

    assert length(first) == 50

    assert {:ok, %{rows: last, filters: %{"page" => 2}}} =
             Directory.load(c.scope, c.mission.mission_id, %{"sort" => "name", "page" => "2"})

    assert length(last) == 2
    refute Enum.any?(last, fn row -> Enum.any?(first, &(&1.id == row.id)) end)

    for params <- [
          %{"page" => "0"},
          %{"page" => "1.5"},
          %{"query" => %{}},
          %{"lifecycle" => "deleted"},
          %{"unknown" => "x"}
        ] do
      assert {:error, _} = Directory.load(c.scope, c.mission.mission_id, params)
    end

    for scope <- [
          %{c.scope | user: nil},
          %{c.scope | organization_membership: nil},
          %{c.scope | mission_id: "foreign"}
        ] do
      assert {:error, _} = Directory.load(scope, c.mission.mission_id)

      assert {:error, _} =
               DirectoryActions.execute(scope, c.mission.mission_id, "star", %{
                 "dashboard_id" => c.active.dashboard_id,
                 "starred" => true
               })
    end
  end

  test "host loads without a frontend release, binds URL filters and consumes ordered star actions",
       c do
    path = c.path <> "?query=thermal&tag=flight"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    assert original["id"] == "dashboards.directory"
    assert original["slot"] == "ops.page"
    assert original["status"] == "ready"
    assert original["data"]["model"]["filters"]["query"] == "thermal"

    input = %{
      "sequence" => 1,
      "dashboard_id" => c.active.dashboard_id,
      "expected_version" => 1,
      "starred" => true
    }

    for invalid <- [
          Map.put(input, "sequence", 1.0),
          Map.put(input, "expected_version", 999),
          Map.put(input, "dashboard_id", c.archived.dashboard_id),
          Map.put(input, "extra", true)
        ] do
      assert action(view, path, original, "star", invalid)["snapshot"]["status"] == "rejected"
    end

    assert action(view, path, %{original | "token" => Ecto.UUID.generate()}, "star", input)["ok"] ==
             false

    assert action(view, path, original, "star", input)["snapshot"]["status"] == "ok"
    assert action(view, path, original, "star", input)["snapshot"]["status"] == "rejected"
    refresh(view, path)
    assert page(view)["token"] == original["token"]
    assert page(view)["data"]["sequence"] == 1
    assert [%{"starred" => true}] = page(view)["data"]["model"]["rows"]
    refresh(view, c.path)
    assert action(view, path, original, "star", Map.put(input, "sequence", 2))["ok"] == false
  end

  test "restores the displayed archived version and keeps uncertain effects locked across refresh",
       c do
    path = c.path <> "?lifecycle=archived"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    [row] = original["data"]["model"]["rows"]
    input = %{"sequence" => 1, "dashboard_id" => row["id"], "expected_version" => row["version"]}
    # Another authorized session changes the lifecycle after this page observed it.
    :ok =
      Dashboards.restore_document(c.org.organization_id, c.mission.mission_id, row["id"],
        expected_version: row["version"]
      )

    %Document{} = document = c.archived

    {:ok, _} =
      Dashboards.update_document(
        c.org.organization_id,
        c.mission.mission_id,
        row["id"],
        %Document{document | name: "Changed elsewhere"}
      )

    assert action(view, path, original, "restore", input)["snapshot"]["status"] == "unknown"
    refresh(view, path)
    assert page(view)["data"]["phase"] == "submitted"
    assert page(view)["token"] == original["token"]

    assert action(view, path, original, "restore", Map.put(input, "sequence", 2))["snapshot"][
             "status"
           ] == "rejected"
  end

  test "restores an admitted archived dashboard using its observed version", c do
    path = c.path <> "?lifecycle=archived"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    [row] = original["data"]["model"]["rows"]
    input = %{"sequence" => 1, "dashboard_id" => row["id"], "expected_version" => row["version"]}
    assert action(view, path, original, "restore", input)["snapshot"]["status"] == "ok"
    refresh(view, path)
    assert page(view)["data"]["model"]["rows"] == []
    assert page(view)["data"]["phase"] == "editing"

    assert Enum.any?(
             Dashboards.list_dashboard_summaries(c.org.organization_id, c.mission.mission_id),
             &(&1.dashboard_id == row["id"])
           )
  end

  test "a revoked authenticated session cannot star a dashboard", c do
    {:ok, view, _} = live(c.conn, c.path)
    original = page(view)
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    render_hook(view, "host:ops-page", %{
      "path" => c.path,
      "id" => original["id"],
      "token" => original["token"],
      "event" => "star",
      "input" => %{
        "sequence" => 1,
        "dashboard_id" => c.active.dashboard_id,
        "expected_version" => 1,
        "starred" => true
      }
    })

    assert_redirect(view, "/sign-in")
  end

  defp persist(c, suffix, name, description, tags) do
    %Document{} = base = c.base

    document = %Document{
      base
      | organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id,
        dashboard_id: "directory-#{suffix}-#{System.unique_integer([:positive])}",
        name: name,
        description: description,
        metadata: Map.put(c.base.metadata, :tags, tags)
    }

    {:ok, persisted} = Dashboards.persist_document(c.org.organization_id, document)
    persisted
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp refresh(view, path) do
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
  end

  defp action(view, path, page, event, input) do
    render_hook(view, "host:ops-page", %{
      "path" => path,
      "id" => page["id"],
      "token" => page["token"],
      "event" => event,
      "input" => input
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end
end
