defmodule CadenceWeb.HostTransportTestSupport do
  @moduledoc false
  import ExUnit.Assertions
  import Phoenix.LiveViewTest
  alias Plug.Conn.Query

  @external_resource Path.expand("../../../../frontend/apps/host/src/routes.json", __DIR__)
  @routes @external_resource
          |> File.read!()
          |> Jason.decode!()
          |> Map.new(&{&1["path"], &1})

  def assert_context(view, expected) do
    assert has_element?(view, "#application-shell")
    vue = LiveVue.Test.get_vue(view, id: "application-shell")
    assert vue.component == "BrowserHost"
    assert vue.ssr == false
    assert Map.keys(vue.props) == ["snapshot"]
    snapshot = vue.props["snapshot"]
    assert is_binary(snapshot["path"])
    context = snapshot["context"]
    assert is_map(context["user"])
    refute Map.has_key?(context, "user_session_token")

    for {key, resource} <- [
          {"organization_id", "organization"},
          {"user_id", "user"},
          {"mission_id", "mission"},
          {"spacecraft_id", "spacecraft"}
        ],
        Map.has_key?(expected, key) do
      assert get_in(context, [resource, key]) == expected[key]
    end

    assert_frontend_route(snapshot["path"], expected)
    snapshot
  end

  # The bootstrap URL must still match the independently asserted frontend
  # surface/query contract. These are frontend catalog facts, not server props.
  defp assert_frontend_route(path, expected) do
    uri = URI.parse(path)
    info = Phoenix.Router.route_info(CadenceWeb.Router, "GET", uri.path, "localhost")
    route = Map.fetch!(@routes, info.route)

    for {key, field} <- [
          {"application_key", "application"},
          {"surface_id", "surface"},
          {"host_scope", "scope"}
        ],
        Map.has_key?(expected, key) do
      assert route[field] == expected[key]
    end

    if Map.has_key?(expected, "query_params") do
      params = Map.merge(Query.decode(uri.query || ""), info.path_params)

      query = query_for(route, params)

      assert query == expected["query_params"]
    end
  end

  defp query_for(route, params) do
    Enum.reduce(route["queryKeys"], %{}, fn key, query ->
      source = Map.get(route["queryAliases"], key, key)

      case Map.fetch(params, source) do
        {:ok, value} -> Map.put(query, key, value)
        :error -> query
      end
    end)
  end
end
