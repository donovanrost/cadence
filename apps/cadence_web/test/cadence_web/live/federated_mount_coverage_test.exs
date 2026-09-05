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
    assert app =~ "MutationObserver"
    assert app =~ "/assets/application-host/host/host.js"
  end
end
