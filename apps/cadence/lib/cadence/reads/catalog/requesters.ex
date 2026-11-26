defmodule Cadence.Reads.Catalog.Requesters do
  @moduledoc """
  `requested_by` on catalog import runs (#146, ux U103; mms-security 11-19): who started each run,
  as `null | %{kind: "user" | "service" | "system", name: binary() | nil, run_by}`. `run_by` (#513)
  is `%{name}` for a system run that names the person who ran it ("by Cadence, run by Mira K.")
  and null otherwise. The console words
  decide what to show ("by Mira K.", "by Cadence", or the time alone).

  - A person keeps `kind: "user"`, named only while they're an active member of the mission's
    organization, checked at read time (`Accounts.MemberNames`). Someone from another organization
    or who has left reads with `name: nil`, never as system: the act stays a person's.
  - A service identity is named only when it belongs to the mission's organization.
  - Cadence itself (a seed or a task) carries the stored system name, which is never a person.
  - No email or id is ever sent. A run stored without an actor (`%{}`) reads as `nil`.

  Names come from two batched queries per table, whatever its length.
  """

  alias Cadence.Accounts.MemberNames
  alias Cadence.Auth

  @type requester ::
          %{kind: binary(), name: binary() | nil, run_by: %{name: binary() | nil} | nil} | nil

  @doc "A `requested_by` resolver for these runs' actors: call `requested_by/2` with its result."
  @spec names(binary(), [map()]) :: %{users: map(), services: map()}
  def names(organization_id, actors) do
    %{
      # People: a person who started a run, and a seed's runner (#513's run_by).
      users:
        MemberNames.display_names(
          organization_id,
          ids(actors, "user_id") ++ ids(actors, "run_by")
        ),
      services: Auth.service_identity_names(organization_id, ids(actors, "service_identity_id"))
    }
  end

  @doc "One run's `requested_by`, given `names/2` over the same table."
  @spec requested_by(map() | nil, %{users: map(), services: map()}) :: requester()
  def requested_by(actor, names) do
    case kind(actor) do
      "user" ->
        %{kind: "user", name: Map.get(names.users, actor["user_id"]), run_by: nil}

      "service" ->
        %{
          kind: "service",
          name: Map.get(names.services, actor["service_identity_id"]),
          run_by: nil
        }

      "system" ->
        %{kind: "system", name: present(actor["name"]), run_by: runner(actor, names)}

      nil ->
        nil
    end
  end

  # Matched on the ids, so the REST API's actor document (ControlPlaneAccess) reads the same way.
  defp kind(%{"actor_kind" => "system", "system_id" => id}) when is_binary(id) and id != "",
    do: "system"

  defp kind(%{"user_id" => id}) when is_binary(id) and id != "", do: "user"
  defp kind(%{"service_identity_id" => id}) when is_binary(id) and id != "", do: "service"
  defp kind(_not_recorded), do: nil

  # #513 (ux on #516): the person who ran a seed or task, named by the same rule (an active member,
  # never by email or id): `%{name}`, with a null name when it can't be read; nil with no runner.
  defp runner(%{"run_by" => id}, names) when is_binary(id) and id != "",
    do: %{name: Map.get(names.users, id)}

  defp runner(_actor, _names), do: nil

  defp ids(actors, key) do
    for %{} = actor <- actors, id = actor[key], is_binary(id) and id != "", uniq: true, do: id
  end

  defp present(name) when is_binary(name) and name != "", do: name
  defp present(_none), do: nil
end
