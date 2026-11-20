defmodule Cadence.Reads.StationWindowActors do
  @moduledoc """
  Names who reported a station availability window (#468, #146 rule C1), for the console's
  reads over `Cadence.Comms.StationAvailability`. A stored operator actor (`reported_by`,
  `created_by`) is named at read time through `Cadence.Control.ActorRef`: an active member of the
  organization by their display name (or `nil`), anyone else with id and name `nil`. Its stored
  name, and any email an older window still holds, is never shown. A provider's or the
  simulator's report keeps its stored actor (not a person).

  One lookup per read, over every status and window given. Comms is the management plane, so
  the naming lives here (projections), not in `StationAvailability` (ADR-015).
  """

  alias Cadence.Control.ActorRef

  @doc "`views` (a status, a window, or a list of either) with their actors named."
  @spec named(map() | [map()], binary() | nil) :: map() | [map()]
  def named(views, organization_id) do
    names = ActorRef.names(organization_id, documents(views))
    name_actors(views, names)
  end

  defp documents(views) when is_list(views), do: Enum.flat_map(views, &documents/1)

  # Both actors are looked up, never assuming created_by == reported_by (api on #558).
  defp documents(%{} = view),
    do: [
      Map.get(view, :reported_by),
      Map.get(view, :created_by) | documents(Map.get(view, :windows, []))
    ]

  defp name_actors(views, names) when is_list(views),
    do: Enum.map(views, &name_actors(&1, names))

  defp name_actors(%{} = view, names) do
    view
    |> update_present(:reported_by, &actor(&1, names))
    |> update_present(:created_by, &actor(&1, names))
    |> update_present(:windows, &name_actors(&1, names))
  end

  defp update_present(map, key, fun),
    do: if(Map.has_key?(map, key), do: Map.update!(map, key, fun), else: map)

  defp actor(nil, _names), do: nil

  defp actor(%{"kind" => kind} = document, _names) when kind in ["provider", "simulator"],
    do: document

  defp actor(document, names), do: ActorRef.document(document, names)
end
