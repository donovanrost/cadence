defmodule Cadence.Configuration.ActorNames do
  @moduledoc """
  Names the actors in a configuration read model (`Status`, the pipeline's `changed_by`) by #146's
  rule (#471, mms-security): a person is named only while they hold an active membership in the
  mission's organization, checked at read time, and never by email; a service only when it
  belongs to that organization; Cadence by its stored system name.

  The `name` stored in a change set's or revision's actor document is never used for a person or
  a service. Records written before #471 stored `display_name || email`, so the stored name can
  be an email (lead 11-19: old rows read through this, no reset). Actors are `%{kind, id, name}`
  (`Status`'s shape); every actor in a view is named with one batched lookup per kind. A person
  or service outside the organization gets `id: nil` too, keeping `kind`, so their id doesn't
  reach the organization (ca-security, api-ops on #487). An active member without a display name
  keeps their id with `name: nil`, so the console still knows their own changes (mms-engineer).

  Guard: any map in the view with exactly the keys `kind`, `id` and `name` is treated as an
  actor. Only `kind` "user" and "service" are looked up; any other kind (Cadence's "system", or
  an entity shaped like an actor) passes through unchanged. A read model must not use that exact
  three-key shape with kind "user" or "service" for anything but an actor.
  """

  import Ecto.Query

  alias Cadence.Accounts.MemberNames
  alias Cadence.Auth
  alias Cadence.Configuration.HeadRow
  alias Cadence.Repo

  @doc "`view` with every actor's `name` resolved under the mission's organization."
  @spec named(term(), String.t()) :: term()
  def named(view, mission_id) when is_binary(mission_id) do
    actors = collect(view, [])
    names = lookup(organization(mission_id), actors)
    replace(view, names)
  end

  defp organization(mission_id) do
    HeadRow
    |> where([head], head.mission_id == ^mission_id)
    |> select([head], head.organization_id)
    |> Repo.one()
  end

  # No head (and so no organization) to name anyone under: nobody is named (fails closed).
  defp lookup(nil, _actors), do: %{users: %{}, services: %{}}

  defp lookup(organization_id, actors) do
    %{
      users: MemberNames.members(organization_id, ids(actors, "user")),
      services: Auth.organization_service_identities(organization_id, ids(actors, "service"))
    }
  end

  defp ids(actors, kind), do: for({^kind, id} <- actors, uniq: true, do: id)

  defp collect(%{kind: kind, id: id, name: _name} = actor, acc) when map_size(actor) == 3,
    do: [{kind, id} | acc]

  defp collect(%_struct{}, acc), do: acc
  defp collect(%{} = map, acc), do: Enum.reduce(Map.values(map), acc, &collect/2)
  defp collect(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect/2)
  defp collect(_other, acc), do: acc

  defp replace(%{kind: kind, id: id, name: name} = actor, names) when map_size(actor) == 3 do
    {id, name} = name_for(kind, id, name, names)
    %{actor | id: id, name: name}
  end

  defp replace(%_struct{} = struct, _names), do: struct
  defp replace(%{} = map, names), do: Map.new(map, fn {k, v} -> {k, replace(v, names)} end)
  defp replace(list, names) when is_list(list), do: Enum.map(list, &replace(&1, names))
  defp replace(other, _names), do: other

  # `{id, name}`. An active member or the organization's own service keeps their id, with their
  # name or nil when they have none: the console compares ids for "mine" (mms-engineer on #487).
  # Anyone else (a platform admin, someone who has left, another organization's service) keeps
  # neither, so their id doesn't reach the organization (ca-security on #487, as #474 does).
  defp name_for("user", id, _stored, names), do: known(names.users, id)
  defp name_for("service", id, _stored, names), do: known(names.services, id)
  # Cadence's own system actor, and any other `{kind, id, name}` map in a view (an entity named
  # by kind, not an actor), keep their id and name: only people and services are looked up.
  defp name_for(_other, id, stored, _names), do: {id, stored}

  defp known(found, id) do
    case Map.fetch(found, id) do
      {:ok, name} -> {id, name}
      :error -> {nil, nil}
    end
  end
end
