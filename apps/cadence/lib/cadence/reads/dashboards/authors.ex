defmodule Cadence.Reads.Dashboards.Authors do
  @moduledoc """
  The people who saved, shared, published or changed dashboards (#469, #146), checked against the
  dashboard's organization at read time (`Accounts.MemberNames`):
    * an active member is `%{id, name}`, `name` null when they have no display name (a nameless
      member keeps their id, so the console can still tell "mine", #471);
    * anyone else (who has left, or a platform admin from another organization) is
      `%{id: nil, name: nil}`: never their email, never their id (ca-security, as #474/#487).
  """
  alias Cadence.Accounts.MemberNames

  @doc "`%{user_id => display_name | nil}` for the ids that are active members; others absent."
  @spec members(binary(), [binary() | nil]) :: %{binary() => binary() | nil}
  def members(organization_id, ids),
    do: MemberNames.members(organization_id, Enum.filter(ids, &is_binary/1))

  @doc "`%{user_id => display_name}` for the members that have a name (a name alone, no id)."
  @spec names(binary(), [binary() | nil]) :: %{binary() => binary()}
  def names(organization_id, ids),
    do: MemberNames.display_names(organization_id, Enum.filter(ids, &is_binary/1))

  @doc "The person object for `id` from `members/2`'s map; nil when there's no id."
  @spec person(%{binary() => binary() | nil}, binary() | nil) ::
          %{id: binary() | nil, name: binary() | nil} | nil
  def person(_members, nil), do: nil

  def person(members, id) when is_binary(id) do
    case Map.fetch(members, id) do
      {:ok, name} -> %{id: id, name: name}
      :error -> %{id: nil, name: nil}
    end
  end
end
