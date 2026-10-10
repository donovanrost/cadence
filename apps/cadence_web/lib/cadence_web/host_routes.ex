defmodule CadenceWeb.HostRoutes do
  @moduledoc """
  Places application surfaces in the host's route catalog.

  A surface's fallback path names the host page it stands in for. Matching it
  against the catalog by shape (literal segments equal, parameters in the same
  positions) lets a federated surface use that route's title and header policy.
  """

  @external_resource Path.expand("../../../../frontend/apps/host/src/routes.json", __DIR__)
  @routes @external_resource |> File.read!() |> Jason.decode!()
  @paths for route <- @routes, route["kind"] != "application_surface", do: route["path"]
  @application_surfaces for route <- @routes,
                            route["kind"] == "application_surface",
                            into: %{},
                            do: {String.to_existing_atom(route["scope"]), route["path"]}

  @scope_bases %{
    mission: "/missions/:mission_id",
    spacecraft: "/missions/:mission_id/spacecraft/:spacecraft_id",
    organization: "",
    user: "/account",
    admin: "/admin"
  }

  @doc """
  The catalog route a surface stands in for. A surface with no host page of its
  own is an application page: it takes its scope's generic application route.
  Nil when the host has neither.
  """
  @spec for_surface(atom(), map()) :: String.t() | nil
  def for_surface(scope, navigation) do
    case {Map.fetch(@scope_bases, scope), Map.get(navigation, :fallback_path)} do
      {{:ok, base}, fallback} when is_binary(fallback) ->
        # Applications give fallback paths relative to their scope, or absolute.
        Enum.find_value([join(base, fallback), fallback], &matching/1)

      {_base, nil} ->
        Map.get(@application_surfaces, scope)

      _no_route ->
        nil
    end
  end

  defp join("", path), do: path
  defp join(base, "/"), do: base
  defp join(base, path), do: base <> path

  defp matching(path) do
    shape = shape(path)
    Enum.find(@paths, &(shape(&1) == shape))
  end

  defp shape(path) do
    path
    |> String.split("/")
    |> Enum.map(&if(String.starts_with?(&1, ":"), do: :param, else: &1))
  end
end
