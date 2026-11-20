defmodule Cadence.Control.ActorRef do
  @moduledoc """
  The console's actor for a stored actor id or document: `%{kind, id, name}` with the console's
  actor kinds (`user | service | system`). The shared helper for #146's rule C1 (#472, #462, as
  settled on #487):

  - A person holding an active membership in `organization_id` (checked at read time,
    `Accounts.MemberNames.members/2`) keeps their id and is named by their display name, or
    `name: nil` if they have none. Anyone outside the organization (a platform admin from
    another organization, someone who left) reads `%{kind: "user", id: nil, name: nil}`; their
    id isn't sent either.
  - A service identity of `organization_id` keeps its id and is named from its live row
    (`nil` without a name). Another organization's reads `%{kind: "service", id: nil, name: nil}`.
  - Anything else is Cadence's own: `system`, with its stored name for a document.
  - A person's name never comes from a stored document: `display_name`, `email` and
    `user_email` in it are ignored. A document form it can't read is `nil`, never system.

  `organization_id` is the organization of the record's mission, or of the scope the read was
  authorized for, never a request parameter. A nil organization names nobody. There's no
  platform-wide variant here (api-ops).

  For lists, `names/2` loads everything in four queries, and `ref/2` and `document/2` then
  answer without a query.
  """

  alias Cadence.Accounts.MemberNames
  alias Cadence.Auth

  @type t :: %{kind: binary(), id: binary() | nil, name: binary() | nil}
  @type names :: %{
          users: %{binary() => binary() | nil},
          user_ids: MapSet.t(binary()),
          services: %{binary() => binary() | nil},
          service_ids: MapSet.t(binary())
        }

  @doc "One actor id. For many, use `names/2` and `ref/2`."
  @spec resolve(binary() | nil, binary()) :: t()
  def resolve(organization_id, id) when is_binary(id),
    do: ref(id, names(organization_id, [id]))

  @doc """
  What `ref/2` and `document/2` need for `refs` (actor ids, stored actor documents, or both):
  who among them is a person or a service at all, and the names this organization may see.
  """
  @spec names(binary() | nil, [binary() | map() | nil]) :: names()
  def names(organization_id, refs) when is_list(refs) do
    ids = refs |> Enum.flat_map(&ids/1) |> Enum.uniq()
    user_ids = existing_users(ids)
    {service_ids, services} = existing_services(organization_id, ids)

    %{
      users: member_names(organization_id, MapSet.to_list(user_ids)),
      user_ids: user_ids,
      services: services,
      service_ids: service_ids
    }
  end

  @doc "One actor id, given `names/2` over the same ids. The same answer as `resolve/2`."
  @spec ref(binary(), names()) :: t()
  def ref(id, names) when is_binary(id) do
    cond do
      MapSet.member?(names.user_ids, id) -> user(id, names)
      MapSet.member?(names.service_ids, id) -> service(id, names)
      true -> %{kind: "system", id: id, name: nil}
    end
  end

  @doc """
  One stored actor document, given `names/2` over the same documents. Reads the forms Cadence
  has stored: `{kind, id}`, `{kind, user_id}`, the REST `{actor_kind, user_id |
  service_identity_id}` and the system `{actor_kind: "system", system_id, name}`. Anything else
  is `nil`.
  """
  @spec document(term(), names()) :: t() | nil
  def document(document, names) do
    case form(document) do
      {:user, id} -> user(id, names)
      {:service, id} -> service(id, names)
      {:system, id, name} -> %{kind: "system", id: id, name: name}
      :unknown -> nil
    end
  end

  defp user(id, names) do
    case Map.fetch(names.users, id) do
      {:ok, name} -> %{kind: "user", id: id, name: name}
      :error -> %{kind: "user", id: nil, name: nil}
    end
  end

  defp service(id, names) do
    case Map.fetch(names.services, id) do
      {:ok, name} -> %{kind: "service", id: id, name: name}
      :error -> %{kind: "service", id: nil, name: nil}
    end
  end

  # A document's kind and id. Only the keys that say who acted are read.
  defp form(%{} = document) when not is_struct(document) do
    document = Map.new(document, fn {key, value} -> {to_string(key), value} end)
    kind = to_string(document["kind"] || document["actor_kind"])

    case kind do
      "user" -> present(document["id"] || document["user_id"], :user)
      "service" -> present(document["id"] || document["service_identity_id"], :service)
      "system" -> {:system, text(document["id"] || document["system_id"]), text(document["name"])}
      _other -> :unknown
    end
  end

  defp form(_not_a_document), do: :unknown

  defp present(id, kind) when is_binary(id) and id != "", do: {kind, id}
  defp present(_missing, _kind), do: :unknown

  defp text(value) when is_binary(value) and value != "", do: value
  defp text(_none), do: nil

  defp ids(id) when is_binary(id), do: [id]

  defp ids(document) do
    case form(document) do
      {kind, id} when kind in [:user, :service] -> [id]
      _no_lookup -> []
    end
  end

  defp existing_users(ids), do: MemberNames.people(ids)

  # Every service among the ids (any organization, so a foreign one still reads as a service),
  # and the names of this organization's own.
  defp existing_services(organization_id, ids) do
    own =
      if is_binary(organization_id),
        do: Auth.organization_service_identities(organization_id, ids),
        else: %{}

    {Auth.service_identity_ids(ids), own}
  end

  defp member_names(organization_id, user_ids) when is_binary(organization_id),
    do: MemberNames.members(organization_id, user_ids)

  defp member_names(_no_organization, _user_ids), do: %{}
end
