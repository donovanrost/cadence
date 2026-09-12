defmodule CadenceWeb.OpsActivityPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Auth.Scope
  alias Cadence.Dashboards.{Document, DocumentCodec, Documents, VersionAuthoring}
  alias Cadence.Reads.Dashboards.Activity
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )
  @renderer Path.expand(
              "../../../../frontend/modules/dashboards-and-exploration/src/features/activity/producer-render-check.mjs",
              __DIR__
            )

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    base = DocumentCodec.load!(@fixture)

    document = %{
      base
      | organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: "activity-" <> Ecto.UUID.generate()
    }

    {:ok, document} = Documents.persist(org.organization_id, document)

    %{
      org: org,
      user: user,
      mission: mission,
      scope: scope,
      document: document,
      conn: TestFixtures.member_conn(user),
      path:
        "/missions/#{mission.mission_id}/ops/dashboards/#{document.dashboard_id}/activity?version=1"
    }
  end

  test "real producer metadata renders in the feature without raw documents or event payloads",
       c do
    {:ok, first} = read(c)
    assert first.document_version == 1
    assert first.selected.widget_count == length(c.document.placements)
    assert {:ok, _} = execute(c, "publish_version", first)
    {:ok, published} = read(c)
    assert published.published_version == 1
    assert [%{event_type: "published", actor_id: actor}] = published.events
    assert actor == c.user.user_id
    refute Map.has_key?(published.selected, :document)
    refute Map.has_key?(hd(published.events), :payload)

    :ok =
      Documents.archive(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id,
        actor_id: actor
      )

    {:ok, archived} = read(c)
    assert archived.archived

    node =
      System.find_executable("node") || flunk("Node is required for activity DTO verification")

    {output, status} =
      System.cmd(node, ["--no-warnings", @renderer, Jason.encode!([first, published, archived])],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  test "publication revision rejects stale history even when the latest draft has not changed",
       c do
    {:ok, _} =
      Documents.update(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id,
        %{c.document | name: "New draft"},
        expected_version: 1
      )

    {:ok, observed} = read(c)
    assert observed.document_version == 2
    assert {:ok, receipt} = execute(c, "publish_version", observed)
    assert receipt.document_version == 2
    assert receipt.revision == observed.revision + 1
    assert {:error, :conflict} = execute(c, "restore_version", observed)

    {:ok, latest} =
      Documents.fetch(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id)

    assert latest.name == "New draft"

    {:ok, published} =
      Documents.fetch_published(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id
      )

    assert Document.version(published) == 1
    assert published.name == c.document.name
  end

  test "restore appends an attributed snapshot and preserves old content and publication", c do
    {:ok, first} = read(c)
    assert {:ok, _} = execute(c, "publish_version", first)

    {:ok, _} =
      Documents.update(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id,
        %{c.document | name: "Different"},
        expected_version: 1
      )

    {:ok, observed} = read(c)
    assert {:ok, %{document_version: 3}} = execute(c, "restore_version", observed)
    {:ok, restored} = read(c)
    assert restored.document_version == 3
    assert restored.published_version == 1
    [third, second, first] = restored.versions
    assert third.kind == "revert"
    assert third.parent_version == 2
    assert third.based_on_version == 1
    assert third.actor_id == c.user.user_id
    assert second.version == 2
    assert first.version == 1

    {:ok, saved} =
      Documents.fetch(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id)

    assert saved.name == c.document.name

    {:ok, old} =
      Documents.fetch_version(
        c.org.organization_id,
        c.mission.mission_id,
        c.document.dashboard_id,
        2
      )

    assert old.document.name == "Different"
  end

  test "bounded history pages have scoped cursors and no duplicates", c do
    for _ <- 1..27 do
      {:ok, current} = read(c)
      assert {:ok, _} = execute(c, "restore_version", current)
    end

    {:ok, first} = read(c)
    assert length(first.versions) == 25
    assert length(first.events) == 25
    assert first.next_version == 4

    {:ok, second} =
      read(c, %{
        "version" => "1",
        "before_version" => to_string(first.next_version),
        "before_event" => first.next_event
      })

    assert Enum.map(second.versions, & &1.version) == [3, 2, 1]
    assert length(second.events) == 2
    assert second.next_version == nil
    assert second.next_event == nil
    assert MapSet.disjoint?(MapSet.new(first.events, & &1.id), MapSet.new(second.events, & &1.id))
    assert {:error, :unavailable} = read(c, %{"before_event" => "missing"})
    other = %{c.document | dashboard_id: "other-" <> Ecto.UUID.generate()}
    {:ok, _} = Documents.persist(c.org.organization_id, other)

    assert {:error, :unavailable} =
             Activity.load(c.scope, c.mission.mission_id, other.dashboard_id, %{
               "before_event" => first.next_event
             })
  end

  test "invalid queries and foreign or unauthenticated scopes cannot read or mutate history", c do
    for query <- [
          %{"version" => "01"},
          %{"version" => "2"},
          %{"version" => 1},
          %{"before_version" => "0"},
          %{"extra" => "x"},
          %{"before_event" => []}
        ] do
      assert {:error, :unavailable} = read(c, query)
    end

    {:ok, model} = read(c)

    for scope <- [
          %{c.scope | user: nil},
          %{c.scope | organization_membership: nil},
          %{c.scope | mission_id: "foreign"},
          %{c.scope | organization_id: "foreign"}
        ] do
      assert {:error, _} = Activity.load(scope, c.mission.mission_id, c.document.dashboard_id)

      assert {:error, _} =
               VersionAuthoring.execute(
                 scope,
                 c.mission.mission_id,
                 c.document.dashboard_id,
                 "restore_version",
                 command(model)
               )
    end

    for command <- [
          Map.put(command(model), "actor_id", "forged"),
          Map.put(command(model), "version", 1.0),
          Map.put(command(model), "expected_revision", 0)
        ] do
      assert {:error, :invalid_input} =
               VersionAuthoring.execute(
                 c.scope,
                 c.mission.mission_id,
                 c.document.dashboard_id,
                 "restore_version",
                 command
               )
    end

    :ok =
      Documents.archive(c.org.organization_id, c.mission.mission_id, c.document.dashboard_id, [])

    assert {:error, :unavailable} = execute(c, "restore_version", model)
    {:ok, current} = read(c)
    assert current.document_version == 1
  end

  test "host binds selected version, token and sequence without an installation", c do
    {:ok, view, _} = live(c.conn, c.path)
    page = page(view)
    assert page["id"] == "dashboards.activity"
    assert page["status"] == "ready"
    input = %{"sequence" => 1, "command" => command(page["data"]["model"])}

    assert action(view, c.path, %{page | "token" => "wrong"}, "restore_version", input)["ok"] ==
             false

    invalid = put_in(input, ["command", "version"], 2)

    assert action(view, c.path, page, "restore_version", invalid)["snapshot"]["status"] ==
             "rejected"

    assert action(view, c.path, page, "restore_version", input)["snapshot"]["status"] == "ok"

    assert action(view, c.path, page, "restore_version", input)["snapshot"]["status"] ==
             "rejected"

    refresh(view, c.path)
    assert page(view)["token"] == page["token"]
    assert page(view)["data"]["model"]["document_version"] == 2
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    render_hook(view, "host:ops-page", %{
      "id" => page["id"],
      "token" => page["token"],
      "path" => c.path,
      "event" => "reload_activity",
      "input" => %{"sequence" => 2, "command" => %{}}
    })

    assert_redirect(view, "/sign-in")
  end

  test "stale publication locks history until an explicit reload, not an ordinary refresh", c do
    {:ok, view, _} = live(c.conn, c.path)
    page = page(view)
    {:ok, model} = read(c)
    assert {:ok, _} = execute(c, "publish_version", model)
    input = %{"sequence" => 1, "command" => command(model)}

    assert action(view, c.path, page, "restore_version", input)["snapshot"]["status"] ==
             "conflict"

    refresh(view, c.path)
    current = page(view)
    assert current["data"]["phase"] == "review"
    next = %{"sequence" => 2, "command" => command(current["data"]["model"])}
    assert action(view, c.path, page, "restore_version", next)["snapshot"]["status"] == "rejected"

    assert action(view, c.path, page, "reload_activity", %{"sequence" => 2, "command" => %{}})[
             "snapshot"
           ]["status"] == "ok"

    assert action(view, c.path, page, "restore_version", %{next | "sequence" => 3})["snapshot"][
             "status"
           ] == "ok"
  end

  defp read(c, params \\ %{"version" => "1"}),
    do: Activity.load(c.scope, c.mission.mission_id, c.document.dashboard_id, params)

  defp command(%{"selected" => selected} = model),
    do: %{
      "version" => selected["version"],
      "expected_version" => model["document_version"],
      "expected_revision" => model["revision"]
    }

  defp command(model),
    do: %{
      "version" => model.selected.version,
      "expected_version" => model.document_version,
      "expected_revision" => model.revision
    }

  defp execute(c, event, model),
    do:
      VersionAuthoring.execute(
        c.scope,
        c.mission.mission_id,
        c.document.dashboard_id,
        event,
        command(model)
      )

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp refresh(view, path) do
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
  end

  defp action(view, path, page, event, input) do
    render_hook(view, "host:ops-page", %{
      "id" => page["id"],
      "token" => page["token"],
      "path" => path,
      "event" => event,
      "input" => input
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end
end
