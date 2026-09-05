defmodule CadenceWeb.FederatedMountCoverageTest do
  use ExUnit.Case, async: true

  @web_root Path.expand("../../../", __DIR__)
  @live_root Path.join(@web_root, "lib/cadence_web/live")
  @components_root Path.join(@web_root, "lib/cadence_web/components")
  @allowlist_path Path.join(@web_root, "assets/federation-host-owned-surfaces.json")

  @ops_route_mounts [
    {"ops_activation_requests_live.ex", "activation_requests"},
    {"ops_alarms_live.ex", "alarms"},
    {"ops_commands_live.ex", "commands"},
    {"ops_contact_detail_live.ex", "contact_detail"},
    {"ops_contact_plan_show_live.ex", "contact_plan_show"},
    {"ops_contact_record_live.ex", "contact_record"},
    {"ops_contact_requirement_list_live.ex", "contact_requirement_list"},
    {"ops_contact_requirement_new_live.ex", "contact_requirement_new"},
    {"ops_contact_requirement_show_live.ex", "contact_requirement_show"},
    {"ops_contact_requirement_template_live.ex", "contact_requirement_template"},
    {"ops_contact_schedule_live.ex", "contact_schedule"},
    {"ops_dashboard_diagnostics_live.ex", "dashboard_diagnostics"},
    {"ops_dashboard_library_live.ex", "dashboard_library"},
    {"ops_dashboard_list_live.ex", "dashboard_directory"},
    {"ops_dashboard_new_live.ex", "dashboard_new"},
    {"ops_dashboard_playlist_present_live.ex", "dashboard_playlist_present"},
    {"ops_dashboard_playlists_live.ex", "dashboard_playlists"},
    {"ops_dashboard_settings_live.ex", "dashboard_settings"},
    {"ops_dashboard_share_live.ex", "dashboard_share"},
    {"ops_dashboard_snapshot_live.ex", "dashboard_snapshot"},
    {"ops_data_operations_live.ex", "data_operations"},
    {"ops_data_sources_live/page.ex", "data_sources"},
    {"ops_fleet_planning_live.ex", "fleet_planning"},
    {"ops_fleet_planning_new_live.ex", "fleet_planning_new"},
    {"ops_fleet_planning_policy_live.ex", "fleet_planning_policy"},
    {"ops_fleet_planning_run_live.ex", "fleet_planning_run"},
    {"ops_telemetry_explore_components.ex", "telemetry_explore"},
    {"ops_timeline_live.ex", "timeline"}
  ]

  test "every production LiveVue mount is federated or explicitly allowlisted" do
    allowlist = @allowlist_path |> File.read!() |> Jason.decode!()
    allowed = MapSet.new(allowlist["local_fallbacks"], & &1["component"])
    federated = allowlist["federated_component"]

    mounts =
      [@live_root, @components_root]
      |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.{ex,heex}")))
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> then(&Regex.scan(~r/v-component="([A-Za-z0-9_]+)"/, &1, capture: :all_but_first))
        |> Enum.map(fn [component] -> {path, component} end)
      end)

    assert mounts != []

    uncovered =
      mounts
      |> Enum.reject(fn {_path, component} ->
        component == federated or MapSet.member?(allowed, component)
      end)

    assert uncovered == [],
           Enum.map_join(uncovered, "\n", fn {path, component} ->
             "#{path}: #{component}"
           end)
  end

  test "federated page resolver and host boot are present" do
    vue = File.read!(Path.join(@web_root, "assets/vue.ts"))
    app = File.read!(Path.join(@web_root, "assets/js/app.js"))

    assert vue =~ "FederatedFullPageSurface"
    assert vue =~ "createLiveVue"
    assert vue =~ "data-catalog-url"
    assert app =~ "MutationObserver"
    assert app =~ "/assets/application-host/host/host.js"
  end

  test "non-Ops federated full pages pass descriptors without legacy renderer bindings" do
    mounts =
      @live_root
      |> Path.join("**/*.{ex,heex}")
      |> Path.wildcard()
      |> Enum.reject(&String.contains?(&1, "/ops_"))
      |> Enum.filter(fn path ->
        File.read!(path) =~ "v-component=\"FederatedFullPageSurface\""
      end)

    assert mounts != []

    Enum.each(mounts, fn path ->
      source = File.read!(path)
      [mount] = Regex.run(~r/v-component="FederatedFullPageSurface"[\s\S]*?\/>/, source)

      assert mount =~ ~r/\bapplication_key=/, path
      assert mount =~ ~r/\bsurface_id=/, path
      assert mount =~ ~r/\bhost_scope=/, path
      assert mount =~ "v-ssr={false}"
      refute mount =~ ~r/\bv-on:/, path
      refute mount =~ ~r/\b(presentation|page|form|navigation|overview|actions)=/, path
    end)
  end

  test "the owned Ops route cohort has descriptor-only mission mounts" do
    assert length(@ops_route_mounts) == 28

    Enum.each(@ops_route_mounts, fn {relative_path, surface_id} ->
      source = File.read!(Path.join(@live_root, relative_path))

      assert source =~ "application_key=\"ops_console\"", relative_path
      assert source =~ "surface_id=\"#{surface_id}\"", relative_path
      assert source =~ "host_scope=\"mission\"", relative_path
      assert source =~ "mission_id={@current_mission.mission_id}", relative_path
      assert source =~ "query_params=", relative_path
      assert source =~ "v-ssr={false}", relative_path
      refute source =~ "v-on:", relative_path
    end)
  end
end
