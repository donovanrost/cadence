defmodule CadenceWeb.FederatedMountCoverageTest do
  use ExUnit.Case, async: true
  @routes Path.expand("../../../../../frontend/apps/host/src/routes.json", __DIR__)

  test "the frontend route catalog and authenticated Phoenix routes agree" do
    catalog = @routes |> File.read!() |> Jason.decode!()
    phoenix_routes = CadenceWeb.Router.__routes__()
    host_routes = Enum.filter(phoenix_routes, &(&1.plug_opts == CadenceWeb.HostPageLive))
    # LiveView route metadata is authoritative across Phoenix versions.
    host_routes =
      if host_routes == [],
        do:
          Enum.filter(phoenix_routes, fn route ->
            case route.metadata[:phoenix_live_view] do
              {CadenceWeb.HostPageLive, _, _, _} -> true
              _ -> false
            end
          end),
        else: host_routes

    # Application surfaces are catalogued for typed headers; ApplicationHostLive serves them.
    {surfaces, catalog} = Enum.split_with(catalog, &(&1["kind"] == "application_surface"))

    for %{"path" => path} <- surfaces do
      example = Regex.replace(~r/:[a-z_]+/, path, "example")
      info = Phoenix.Router.route_info(CadenceWeb.Router, "GET", example, "localhost")
      assert {CadenceWeb.ApplicationHostLive, _, _, _} = info.phoenix_live_view
    end

    assert Enum.sort(Enum.map(host_routes, & &1.path)) ==
             Enum.sort(Enum.map(catalog, & &1["path"]))

    for route <- host_routes do
      path = Regex.replace(~r/:[a-z_]+/, route.path, "example")
      info = Phoenix.Router.route_info(CadenceWeb.Router, "GET", path, "localhost")
      assert {CadenceWeb.HostPageLive, _, _, %{name: :application}} = info.phoenix_live_view
      assert is_atom(info.host_policy)
      assert :browser in info.pipe_through
      assert :require_authenticated_scope in info.pipe_through
    end
  end

  test "route query contracts exclude host authority fields" do
    for route <- @routes |> File.read!() |> Jason.decode!() do
      refute "application_key" in route["queryKeys"]
      refute "host_scope" in route["queryKeys"]
      assert Enum.all?(Map.keys(route["queryAliases"]), &(&1 in route["queryKeys"]))
    end
  end
end
