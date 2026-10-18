defmodule Cadence.Reads.ApplicationSurfaces.DashboardLegacyTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Dashboards.{DocumentCodec, Documents, Management}
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole

  @org "org-dashboard-legacy"
  @mission "mission-dashboard-legacy"
  @fixture Path.expand("../../../fixtures/dashboards/value_tile_latest.v1.json", __DIR__)
  @checker Path.expand(
             "../../../../../../frontend/modules/dashboards-and-exploration/src/test-support/legacy-dashboard-producer-check.mjs",
             __DIR__
           )

  setup do
    persist_mission_scope(@org, @mission)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @org,
      mission_id: @mission,
      user: %{user_id: "dashboard-legacy-reader"},
      organization_membership: %{lifecycle_state: :active}
    }

    base = DocumentCodec.load!(@fixture)

    {:ok, document} =
      Documents.persist(@org, %{
        base
        | organization_id: @org,
          mission_id: @mission,
          dashboard_id: "legacy-dashboard"
      })

    {:ok, playlist} =
      Management.create_playlist(@org, @mission, %{
        name: "Legacy playlist",
        dashboard_ids: [document.dashboard_id, document.dashboard_id]
      })

    %{scope: scope, document: document, playlist: playlist}
  end

  test "all six durable entries produce exact domain-owned destinations through the real remote registry",
       c do
    selected = %{"version" => "1", "selected_publish_issue" => "issue/a?+🌍"}

    viewer = %{
      "time_mode" => "range",
      "from" => "2026-09-10T12:00:00Z",
      "to" => "2026-09-10T13:00:00Z",
      "selected_resource_id" => "resource/a?+🌍"
    }

    models =
      for {surface, component, params, suffix, query} <- [
            {"dashboard_library", "OpsDashboardLibrary", %{}, "library", %{}},
            {"dashboard_playlists", "OpsDashboardPlaylists", %{}, "playlists", %{}},
            {"dashboard_show", "OpsDashboardShow",
             Map.put(viewer, "dashboard_id", c.document.dashboard_id), c.document.dashboard_id,
             viewer},
            {"dashboard_editor", "OpsDashboardShow", %{"dashboard_id" => c.document.dashboard_id},
             "#{c.document.dashboard_id}/edit", %{}},
            {"dashboard_activity", "OpsDashboardActivitySurface",
             Map.put(selected, "dashboard_id", c.document.dashboard_id),
             "#{c.document.dashboard_id}/activity", selected},
            {"dashboard_playlist_present", "OpsDashboardPlaylistPresent",
             %{"playlist_id" => c.playlist.dashboard_playlist_id, "index" => "1"},
             "playlists/#{c.playlist.dashboard_playlist_id}/present", %{"index" => "1"}}
          ] do
        assert {:ok, %{"data" => %{"presentation" => presentation}}} =
                 load(c.scope, surface, params)

        assert presentation["component"] == component
        assert presentation["props"]["mission_id"] == @mission
        assert presentation["props"]["query"] == query

        if surface in ~w(dashboard_show dashboard_editor) do
          assert presentation["props"]["mode"] ==
                   if(surface == "dashboard_show", do: "view", else: "edit")

          refute Map.has_key?(presentation["props"], "canvas")
        end

        %{
          presentation: presentation,
          path: "/missions/#{@mission}/ops/dashboards/#{suffix}",
          query: query
        }
      end

    {output, status} =
      System.cmd(
        System.find_executable("node"),
        ["--no-warnings", @checker, Jason.encode!(models)],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "Legacy dashboard native producer and remote registry consumer passed"
    assert {:ok, unchanged} = Documents.fetch(@org, @mission, c.document.dashboard_id)
    assert unchanged == c.document

    assert {:ok, unchanged_playlist} =
             Management.fetch_playlist(@org, @mission, c.playlist.dashboard_playlist_id)

    assert unchanged_playlist == c.playlist
  end

  test "invalid selections cannot silently become unselected workspace links", c do
    for {surface, params} <- [
          {"dashboard_library", %{"dashboard_id" => c.document.dashboard_id}},
          {"dashboard_playlists", %{"query" => "ignored"}},
          {"dashboard_show",
           %{"dashboard_id" => c.document.dashboard_id, "selected_resource_id" => ["nested"]}},
          {"dashboard_show", %{"dashboard_id" => c.document.dashboard_id, "unknown" => "query"}},
          {"dashboard_editor",
           %{"dashboard_id" => c.document.dashboard_id, "panel" => "history"}},
          {"dashboard_activity", %{"dashboard_id" => c.document.dashboard_id, "version" => "0"}},
          {"dashboard_activity",
           %{"dashboard_id" => c.document.dashboard_id, "version" => "9007199254740991"}},
          {"dashboard_activity",
           %{"dashboard_id" => c.document.dashboard_id, "selected_publish_issue" => "bad\n"}},
          {"dashboard_activity",
           %{"dashboard_id" => c.document.dashboard_id, "selected_publish_issue" => ["nested"]}},
          {"dashboard_playlist_present",
           %{"playlist_id" => c.playlist.dashboard_playlist_id, "index" => "01"}},
          {"dashboard_playlist_present",
           %{"playlist_id" => c.playlist.dashboard_playlist_id, "index" => "100"}}
        ] do
      assert {:error, :unsupported_application_surface_query} = load(c.scope, surface, params)
    end
  end

  test "mission authorization and exact subject admission remain required", c do
    persist_mission_scope(@org, "mission-legacy-foreign")

    {:ok, foreign} =
      Documents.persist(@org, %{
        c.document
        | mission_id: "mission-legacy-foreign",
          dashboard_id: "foreign-dashboard"
      })

    {:ok, playlist} =
      Management.create_playlist(@org, "mission-legacy-foreign", %{
        name: "Foreign",
        dashboard_ids: [foreign.dashboard_id]
      })

    for {surface, key, id} <- [
          {"dashboard_activity", "dashboard_id", foreign.dashboard_id},
          {"dashboard_show", "dashboard_id", foreign.dashboard_id},
          {"dashboard_editor", "dashboard_id", foreign.dashboard_id},
          {"dashboard_playlist_present", "playlist_id", playlist.dashboard_playlist_id}
        ] do
      for params <- [%{}, %{key => id}, %{key => "missing"}] do
        assert {:error, :unsupported_application_surface_query} = load(c.scope, surface, params)
      end
    end

    assert {:error, :unsupported_application_surface_query} =
             load(%{c.scope | mission_id: "mission-legacy-foreign"}, "dashboard_library", %{})

    assert {:error, :unsupported_application_surface_query} =
             load(c.scope, "dashboard_library", %{"mission_id" => "mission-legacy-foreign"})
  end

  defp load(scope, surface, params) do
    OpsConsole.load(scope, HostContext.mission(@mission), %SurfaceQueryRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: surface,
      surface_version: 1,
      query_id: "cadence.ops.#{surface}",
      query_version: 1,
      params: params
    })
  end
end
