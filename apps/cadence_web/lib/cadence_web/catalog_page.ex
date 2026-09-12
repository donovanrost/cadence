defmodule CadenceWeb.CatalogPage do
  @moduledoc "Host-owned Catalog route composition. Resource identity comes from matched paths."

  alias Cadence.Reads.Catalog.Pages

  @external_resource Path.expand("../../../../frontend/apps/host/src/routes.json", __DIR__)
  @routes @external_resource
          |> File.read!()
          |> Jason.decode!()
          |> Enum.filter(&(&1["kind"] == "catalog"))
          |> Map.new(&{&1["path"], {&1["catalogPage"], &1["queryKeys"]}})

  def load(scope, %{route: route, params: params}) do
    case Map.fetch(@routes, route) do
      {:ok, {page, keys}} ->
        snapshot(scope, params["mission_id"], page, Map.take(params, keys))

      :error ->
        nil
    end
  end

  defp snapshot(scope, mission_id, page, params) do
    case Pages.load(scope, mission_id, page, params) do
      {:ok, data} -> %{version: 1, page: page, status: "ready", data: data}
      {:error, _reason} -> %{version: 1, page: page, status: "unavailable"}
    end
  rescue
    _exception -> %{version: 1, page: page, status: "unavailable"}
  end
end
