defmodule Cadence.Reads.AlarmEpisodes.People do
  @moduledoc """
  Names the people on alarm episodes at read time (#469, #146): an episode's assignee, who
  acknowledged it and each event's person actor are named only while they hold an active
  membership in the mission's organization, checked now, through `Accounts.MemberNames`.
  Otherwise the name is null: the name stored when they acted is never shown, nor an email or an
  id. A service or the system actor keeps the name it was stored with.
  """

  alias Cadence.Accounts.MemberNames

  @spec put(binary(), [map()]) :: [map()]
  def put(organization_id, episodes) do
    names = MemberNames.display_names(organization_id, user_ids(episodes))
    Enum.map(episodes, &name(&1, names))
  end

  defp user_ids(episodes) do
    episodes
    |> Enum.flat_map(&people/1)
    |> Enum.flat_map(fn
      %{kind: "user", id: id} when is_binary(id) -> [id]
      %{id: id} = person when is_binary(id) and not is_map_key(person, :kind) -> [id]
      _other -> []
    end)
  end

  defp people(episode) do
    [episode[:assignee], episode[:acknowledged_by]] ++
      Enum.map(Map.get(episode, :events, []), & &1[:actor])
  end

  defp name(episode, names) do
    episode
    |> rename(:assignee, names)
    |> rename(:acknowledged_by, names)
    |> then(fn
      %{events: events} = episode ->
        %{episode | events: Enum.map(events, &rename(&1, :actor, names))}

      episode ->
        episode
    end)
  end

  defp rename(map, key, names) do
    case Map.get(map, key) do
      # The assignee is always a person (it has no kind); an actor says its kind.
      %{kind: "user", id: id} = person ->
        %{map | key => %{person | name: Map.get(names, id)}}

      %{id: id} = person when not is_map_key(person, :kind) ->
        %{map | key => %{person | name: Map.get(names, id)}}

      _other ->
        map
    end
  end
end
