defmodule Cadence.Accounts.MemberNames do
  @moduledoc """
  Display names of people, only as members of one organization (mms-security 11-19, #146): a
  read that names who did something shows a person's name to that organization only while they
  hold an active membership in it, checked at read time. Someone from another organization (a
  platform admin acting as support) or who has since left gets no name. There's no fallback to
  email or id.
  """

  import Ecto.Query

  alias Cadence.Accounts.{OrganizationMembershipRow, UserRow}
  alias Cadence.Repo

  @doc "`%{user_id => display_name}` for the ids with an active membership and a display name."
  @spec display_names(binary(), [binary()]) :: %{binary() => binary()}
  def display_names(_organization_id, []), do: %{}

  def display_names(organization_id, user_ids)
      when is_binary(organization_id) and is_list(user_ids) do
    OrganizationMembershipRow
    |> join(:inner, [m], u in UserRow, on: m.user_id == u.user_id)
    |> where(
      [m, u],
      m.organization_id == ^organization_id and m.lifecycle_state == "active" and
        m.user_id in ^Enum.uniq(user_ids) and not is_nil(u.display_name) and
        u.display_name != ""
    )
    |> select([_m, u], {u.user_id, u.display_name})
    |> Repo.all()
    |> Map.new()
  end
end
