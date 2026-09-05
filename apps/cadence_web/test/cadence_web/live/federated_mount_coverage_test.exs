defmodule CadenceWeb.FederatedMountCoverageTest do
  use ExUnit.Case, async: true

  @web_root Path.expand("../../../", __DIR__)
  @live_root Path.join(@web_root, "lib/cadence_web/live")
  @components_root Path.join(@web_root, "lib/cadence_web/components")
  @allowlist_path Path.join(@web_root, "assets/federation-host-owned-surfaces.json")

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
    refute vue =~ "surfaceForPath"
    refute vue =~ "location.pathname"
    assert app =~ "MutationObserver"
    assert app =~ "/assets/application-host/host/host.js"
    assert app =~ "phx:page-loading-stop"
    assert app =~ "mounted.unmount()"
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
      refute path =~ ~r{/(admin_home|admin_organization_list|admin_organization_new|admin_runtime|notifications)_live\.ex$} and
               mount !~ ~r/\bquery_params=/
      refute mount =~ ~r/\bv-on:/, path
      refute mount =~ ~r/\b(presentation|page|form|navigation|overview|actions)=/, path
    end)
  end

  test "route-owned ids are passed as bounded query parameters" do
    contracts = [
      {"catalog/catalog_artifact_show_live.ex", ~w(mission_id artifact_id)},
      {"catalog/catalog_database_show_live.ex", ~w(mission_id catalog_database_id)},
      {"catalog/catalog_revision_show_live.ex", ~w(mission_id catalog_revision_id)},
      {"catalog/catalog_import_run_show_live.ex", ~w(mission_id import_run_id)},
      {"provider_account_show_live.ex", ~w(organization_id provider_account_id)},
      {"spacecraft_applications_live.ex", ~w(mission_id spacecraft_id)},
      {"comms_ground_station_show_live.ex", ~w(mission_id ground_station_id)},
      {"comms_routing_show_live.ex", ~w(mission_id routing_rule_id)}
    ]

    Enum.each(contracts, fn {relative_path, keys} ->
      source = File.read!(Path.join(@live_root, relative_path))
      [mount] = Regex.run(~r/v-component="FederatedFullPageSurface"[\s\S]*?\/>/, source)

      assert mount =~ ~r/\bquery_params=/, relative_path

      Enum.each(keys, fn key ->
        assert mount =~ ~r/#{key}: /, "#{relative_path} omits #{key}"
      end)
    end)
  end
end
