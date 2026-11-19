defmodule CadenceWeb.Console.DashboardDirectoryAPITest do
  @moduledoc "Dashboards D1-D4, D6 (docs/apogee/api/dashboards.md)."
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.OpsDashboardPageTestSupport

  alias Cadence.Dashboards.{Document, Documents, Placement, PlaylistStore, WidgetDef}
  alias Cadence.Reads.Dashboards.BindingSummary
  alias CadenceWeb.TestFixtures

  setup do: dashboard_page_setup()

  defp base(c), do: "/api/console/v1/missions/#{c.mission.mission_id}/dashboards"
  defp conn(c), do: TestFixtures.member_conn(c.user)
  defp list(c, query \\ ""), do: c |> conn() |> get(base(c) <> query) |> json_response(200)
  defp path(c, suffix), do: base(c) <> "/#{c.document.dashboard_id}" <> suffix

  test "D1 lists rows with updated_by, current_version and the spacecraft summary", c do
    data = list(c)["data"]

    assert %{"total" => 1, "page" => 1, "pages" => 1, "can_create" => true} = data
    assert [row] = data["dashboards"]

    assert %{
             "id" => id,
             "archived" => false,
             "starred" => false,
             "current_version" => 1,
             "viewed_at" => nil
           } = row

    assert id == c.document.dashboard_id
    assert Map.has_key?(row, "updated_by") and Map.has_key?(row, "spacecraft")
    assert data["shortcuts"] == %{"starred" => [], "recent" => []}

    assert list(c, "?q=no-such-dashboard")["data"]["dashboards"] == []

    assert %{"error" => %{"code" => "invalid_params"}} =
             c |> conn() |> get(base(c) <> "?sort=widgets_desc") |> json_response(422)
  end

  test "D2 star and D6 views feed the shortcuts", c do
    assert c |> conn() |> put(path(c, "/star")) |> response(204)
    assert c |> conn() |> post(path(c, "/views")) |> response(204)

    shortcuts = list(c)["data"]["shortcuts"]
    assert [%{"starred" => true}] = shortcuts["starred"]
    assert [%{"viewed_at" => viewed_at}] = shortcuts["recent"]
    assert is_binary(viewed_at)

    assert c |> conn() |> delete(path(c, "/star")) |> response(204)
    assert list(c)["data"]["shortcuts"]["starred"] == []

    assert %{"error" => %{"code" => "not_found"}} =
             c |> conn() |> put(base(c) <> "/dashboard-nope/star") |> json_response(404)
  end

  test "D3 archive needs confirm while a playlist shows it; archive and restore are audited",
       c do
    {:ok, playlist} =
      PlaylistStore.create(
        c.org.organization_id,
        c.mission.mission_id,
        %{
          "name" => "Wallboard",
          "description" => "",
          "dashboard_ids" => [c.document.dashboard_id],
          "dwell_seconds" => 30,
          "wallboard_mode" => false
        },
        c.user.user_id
      )

    assert %{"error" => %{"code" => "dashboard_in_use", "details" => details}} =
             c |> conn() |> post(path(c, "/archive"), %{}) |> json_response(409)

    assert details["used_by"]["playlists"] == [
             %{"id" => playlist.dashboard_playlist_id, "name" => "Wallboard"}
           ]

    assert %{"data" => %{"archived" => true}} =
             c |> conn() |> post(path(c, "/archive"), %{"confirm" => true}) |> json_response(200)

    assert list(c, "?archived=true")["data"]["dashboards"] |> Enum.all?(& &1["archived"])

    assert %{"data" => %{"archived" => false}} =
             c |> conn() |> post(path(c, "/restore"), %{}) |> json_response(200)

    admin = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(admin, c.org, role: :organization_admin)

    actions =
      admin
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/organizations/#{c.org.organization_id}/audit?kinds=config")
      |> json_response(200)
      |> get_in(["data", "events"])
      |> Enum.filter(&(get_in(&1, ["target", "kind"]) == "dashboard"))
      |> Enum.map(& &1["action"])

    name = c.document.name
    assert "Archived dashboard #{name}" in actions
    assert "Restored dashboard #{name}" in actions
  end

  # Moved from the legacy ops_directory_page_test (L8 cutover): the cross-organization and
  # revoked-session refusals it checked through the old page, now through the console API.
  test "another organization's member can't star, archive or duplicate; a revoked session can't",
       c do
    outsider = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(outsider, TestFixtures.persist_org!())
    foreign = TestFixtures.member_conn(outsider)

    for request <- [
          &put(&1, path(c, "/star")),
          &post(&1, path(c, "/archive"), %{"confirm" => true}),
          &post(&1, path(c, "/duplicate"), %{"name" => "Mine"})
        ] do
      assert request.(foreign).status in [403, 404]
    end

    assert [%{"archived" => false, "starred" => false}] = list(c)["data"]["dashboards"]
    assert length(list(c)["data"]["dashboards"]) == 1

    revoked = conn(c)
    :ok = Cadence.Auth.revoke_user_session(get_session(revoked, :user_session_token))
    assert revoked |> put(path(c, "/star")) |> json_response(401)
    assert list(c)["data"]["shortcuts"]["starred"] == []
  end

  test "D4 creates a blank dashboard with tags, and duplicates one", c do
    assert %{"data" => %{"id" => id, "version" => 1}} =
             c
             |> conn()
             |> post(base(c), %{"name" => "Bus overview", "tags" => ["power"]})
             |> json_response(201)

    created = Enum.find(list(c)["data"]["dashboards"], &(&1["id"] == id))
    assert created["tags"] == ["power"]
    assert created["spacecraft"] == nil

    assert %{"error" => %{"code" => "invalid_params"}} =
             c |> conn() |> post(base(c), %{"name" => " "}) |> json_response(422)

    assert %{"data" => %{"id" => copy, "version" => 1}} =
             c
             |> conn()
             |> post(path(c, "/duplicate"), %{"name" => "Copy"})
             |> json_response(201)

    assert copy != c.document.dashboard_id
  end

  test "D4 sets a fixed spacecraft as the default scope; context and fleet set none", c do
    craft = TestFixtures.persist_spacecraft!(c.mission)
    fixed = %{"mode" => "fixed", "spacecraft_id" => craft.spacecraft_id}

    assert %{"data" => %{"id" => id}} =
             c
             |> conn()
             |> post(base(c), %{"name" => "SC view", "spacecraft" => fixed})
             |> json_response(201)

    {:ok, document} =
      Documents.fetch_published(
        c.org.organization_id,
        c.mission.mission_id,
        id
      )

    assert get_in(document.defaults, ["scope", "spacecraft_id"]) == craft.spacecraft_id

    assert %{"data" => %{"id" => context_id}} =
             c
             |> conn()
             |> post(base(c), %{"name" => "Pick one", "spacecraft" => %{"mode" => "context"}})
             |> json_response(201)

    {:ok, context} =
      Documents.fetch_published(
        c.org.organization_id,
        c.mission.mission_id,
        context_id
      )

    assert context.defaults == %{}

    for bad <- [
          %{"mode" => "fixed", "spacecraft_id" => "someone-elses"},
          %{"mode" => "fixed"},
          %{"mode" => "orbit"}
        ] do
      assert %{"error" => %{"code" => "invalid_params", "details" => %{"field" => field}}} =
               c
               |> conn()
               |> post(base(c), %{"name" => "Bad", "spacecraft" => bad})
               |> json_response(422)

      assert field in ["spacecraft", "name"]
    end
  end

  test "duplicating a dashboard that isn't publish-ready says what to fix (422, not 503)", c do
    # A placement scoped to a kind no resolver knows: the readiness plan can't build its request.
    [placement | rest] = c.document.placements

    scoped = %{
      placement
      | scope_override: %{
          "primary" => %{"kind" => "not_a_scope", "mode" => "one", "ids" => ["x"]}
        }
    }

    unready = %{
      c.document
      | dashboard_id: "dashboard-unready-#{System.unique_integer([:positive])}",
        placements: [scoped | rest]
    }

    {:ok, unready} = Documents.persist(c.org.organization_id, unready)

    assert %{
             "error" => %{
               "code" => "dashboard_not_ready",
               "details" => %{"placements" => [_ | _]}
             }
           } =
             c
             |> conn()
             |> post(base(c) <> "/#{unready.dashboard_id}/duplicate", %{"name" => "Copy"})
             |> json_response(422)
  end

  test "D4 takes null for optional fields and names the field that's wrong", c do
    assert %{"data" => %{"id" => _}} =
             c
             |> conn()
             |> post(base(c), %{
               "name" => "Blank",
               "description" => nil,
               "tags" => [],
               "spacecraft" => %{"mode" => "context"}
             })
             |> json_response(201)

    for {body, field} <- [
          {%{"name" => " "}, "name"},
          {%{"name" => "X", "description" => 7}, "description"},
          {%{"name" => "X", "tags" => ["ok", ""]}, "tags"},
          {%{"name" => "X", "spacecraft" => %{"mode" => "orbit"}}, "spacecraft"}
        ] do
      assert %{"error" => %{"details" => %{"field" => ^field}}} =
               c |> conn() |> post(base(c), body) |> json_response(422)
    end
  end

  describe "BindingSummary.summarize/2" do
    defp placement(type, scope \\ nil),
      do: %Placement{
        widget_def: %WidgetDef{widget_type_id: type},
        scope_override: scope
      }

    defp doc(placements, defaults \\ %{}),
      do: %Document{placements: placements, defaults: defaults}

    test "derives fixed, context, fleet, mixed and none" do
      names = %{"sc-1" => "SC-1"}
      fleet = placement("cadence.constellation_health")
      chart = placement("cadence.time_series")
      sc1 = placement("cadence.time_series", %{"spacecraft_id" => "sc-1"})
      sc2 = placement("cadence.time_series", %{spacecraft_id: "sc-2"})

      assert BindingSummary.summarize(doc([]), names) == nil
      assert BindingSummary.summarize(doc([fleet]), names) == %{mode: "fleet"}
      assert BindingSummary.summarize(doc([chart, fleet]), names) == %{mode: "context"}

      assert BindingSummary.summarize(doc([sc1, fleet]), names) ==
               %{mode: "fixed", spacecraft: %{id: "sc-1", name: "SC-1"}}

      assert BindingSummary.summarize(
               doc([chart], %{"scope" => %{"spacecraft_id" => "sc-1"}}),
               names
             ) ==
               %{mode: "fixed", spacecraft: %{id: "sc-1", name: "SC-1"}}

      assert BindingSummary.summarize(doc([sc1, sc2]), names) == %{mode: "mixed"}
      assert BindingSummary.summarize(doc([sc1, chart]), names) == %{mode: "mixed"}
    end
  end
end
