defmodule Cadence.Reads.SpacecraftRouteDocument do
  @moduledoc """
  One extra route's document for the console's KindEditor (ux U79): `{id, document}`, exactly
  what the `spacecraft_route` kind loads, which is the route as it was staged (domain 01ad846e7:
  an empty transport stays empty, a name template stays a template). Scoped to the spacecraft in
  the URL: a route of another spacecraft, or an id that isn't an extra route, is not found.
  Callers authorize first.
  """

  alias Cadence.Comms.ConfigKinds.SpacecraftRoute

  @spec load(binary(), binary(), binary(), binary()) ::
          {:ok, %{id: binary(), document: map()}} | {:error, :spacecraft_route_not_found}
  def load(organization_id, mission_id, spacecraft_id, route_id) do
    case SpacecraftRoute.load(organization_id, mission_id, [route_id]) do
      %{^route_id => %{"spacecraft_id" => ^spacecraft_id} = document} ->
        {:ok, %{id: route_id, document: document}}

      _missing_or_other_spacecraft ->
        {:error, :spacecraft_route_not_found}
    end
  end
end
