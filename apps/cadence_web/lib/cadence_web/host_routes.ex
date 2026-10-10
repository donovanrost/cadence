defmodule CadenceWeb.HostRoutes do
  @moduledoc """
  Places application surfaces in the host's route catalog.

  A surface's fallback path names the host page it stands in for. Matching it
  against the catalog by shape (literal segments equal, parameters in the same
  positions) lets a federated surface use that route's title and header policy.
  """

  @external_resource Path.expand("../../../../frontend/apps/host/src/routes.json", __DIR__)
  @paths @external_resource |> File.read!() |> Jason.decode!() |> Enum.map(& &1["path"])

  @scope_bases %{
    mission: "/missions/:mission_id",
    spacecraft: "/missions/:mission_id/spacecraft/:spacecraft_id",
    organization: "",
    user: "/account",
    admin: "/admin"
  }

  @doc "The catalog route a surface stands in for, or nil when the host has no such page."
  @spec for_surface(atom(), map()) :: String.t() | nil
  def for_surface(scope, navigation) do
    with {:ok, base} <- Map.fetch(@scope_bases, scope),
         fallback when is_binary(fallback) <- Map.get(navigation, :fallback_path) do
      shape = shape(base <> fallback)
      Enum.find(@paths, &(shape(&1) == shape))
    else
      _no_route -> nil
    end
  end

  defp shape(path) do
    path
    |> String.split("/")
    |> Enum.map(&if(String.starts_with?(&1, ":"), do: :param, else: &1))
  end
end
