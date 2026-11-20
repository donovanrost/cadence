defmodule Cadence.Reads.AlarmEpisodes.People do
  @moduledoc """
  Names the people on alarm episodes at read time (#469, #146): an episode's assignee, who
  acknowledged it and each event's person actor are checked against the mission's organization
  now, through `Accounts.MemberNames.members/2`. An active member keeps their id and is named
  (null without a display name); anyone else (who has left, or a platform admin from another
  organization) gets id and name null (ca-security, as #474/#487). The name stored when they acted
  is never shown, nor an email. A service or the system actor keeps what it was stored with.
  """

  alias Cadence.Accounts.MemberNames

  @spec put(binary(), [map()]) :: [map()]
  def put(organization_id, episodes) do
    names = MemberNames.members(organization_id, user_ids(episodes))
    Enum.map(episodes, &name(&1, names))
  end

  defp user_ids(episodes) do
    episodes
    |> Enum.flat_map(&people/1)
    |> Enum.flat_map(fn
      %{kind: "user", id: id} when is_binary(id) -> [id]
      %{id: id} = person when is_binary(id) and not is_map_key(person, :kind) -> [id]
      %{"id" => id} when is_binary(id) -> [id]
      _other -> []
    end)
  end

  defp people(episode) do
    events = Map.get(episode, :events, [])

    [episode[:assignee], episode[:acknowledged_by]] ++
      Enum.map(events, & &1[:actor]) ++
      Enum.flat_map(events, &[payload_person(&1, "from"), payload_person(&1, "to")])
  end

  defp payload_person(%{payload: %{} = payload}, key), do: payload[key]
  defp payload_person(_event, _key), do: nil

  defp name(episode, names) do
    episode
    |> rename(:assignee, names)
    |> rename(:acknowledged_by, names)
    |> then(fn
      %{events: events} = episode ->
        %{episode | events: Enum.map(events, &(&1 |> rename(:actor, names) |> payload(names)))}

      episode ->
        episode
    end)
  end

  defp rename(map, key, names) do
    case Map.get(map, key) do
      # The assignee is always a person (it has no kind); an actor says its kind.
      %{kind: "user", id: id} = person ->
        %{map | key => checked(person, id, names)}

      %{id: id} = person when not is_map_key(person, :kind) ->
        %{map | key => checked(person, id, names)}

      _other ->
        map
    end
  end

  # An assignment's payload names the assignee before and after (`from`, `to`), stored as the
  # assignee document was (an older row may carry an email): each is rebuilt as `{id, name}`,
  # checked like the assignee, so nothing else stored in it is sent (dashboards' review).
  defp payload(%{payload: %{} = payload} = event, members) do
    %{event | payload: Enum.reduce(["from", "to"], payload, &payload_key(&2, &1, members))}
  end

  defp payload(event, _members), do: event

  defp payload_key(payload, key, members) do
    case payload do
      %{^key => %{"id" => id}} when is_binary(id) ->
        case Map.fetch(members, id) do
          {:ok, name} -> Map.put(payload, key, %{"id" => id, "name" => name})
          :error -> Map.put(payload, key, %{"id" => nil, "name" => nil})
        end

      %{^key => %{}} ->
        Map.put(payload, key, %{"id" => nil, "name" => nil})

      _none ->
        payload
    end
  end

  defp checked(person, id, members) do
    case Map.fetch(members, id) do
      {:ok, name} -> %{person | name: name}
      :error -> %{person | id: nil, name: nil}
    end
  end
end
