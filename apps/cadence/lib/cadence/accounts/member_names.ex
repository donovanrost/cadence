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

  @doc """
  Which of `user_ids` are people at all, whatever their membership (#472: a non-member still
  reads as a person, unnamed, never as Cadence).
  """
  @spec people([binary()]) :: MapSet.t(binary())
  def people([]), do: MapSet.new()

  def people(user_ids) when is_list(user_ids) do
    UserRow
    |> where([u], u.user_id in ^Enum.uniq(user_ids))
    |> select([u], u.user_id)
    |> Repo.all()
    |> MapSet.new()
  end

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

  @doc """
  `%{user_id => display_name | nil}` for every id with an active membership, a member without a
  display name included (nil). Reads that compare ids (the console's "mine") keep a nameless
  member's id; anyone missing from the map isn't a member and gets neither (#471).
  """
  @spec members(binary(), [binary()]) :: %{binary() => binary() | nil}
  def members(_organization_id, []), do: %{}

  def members(organization_id, user_ids)
      when is_binary(organization_id) and is_list(user_ids) do
    OrganizationMembershipRow
    |> join(:inner, [m], u in UserRow, on: m.user_id == u.user_id)
    |> where(
      [m, _u],
      m.organization_id == ^organization_id and m.lifecycle_state == "active" and
        m.user_id in ^Enum.uniq(user_ids)
    )
    |> select([_m, u], {u.user_id, u.display_name})
    |> Repo.all()
    |> Map.new(fn {id, name} -> {id, present(name)} end)
  end

  @doc """
  The organization's own Audit only (`Reads.OrganizationAudit`; setup.md C1's exception, #470,
  OK'd by ca-security, ux and lead): `%{user_id => {display_name | nil, :active | :former}}`
  for every id that has a membership row in `organization_id`, in any state, so the Audit can
  say who its admins removed and name a former member's own past acts. Display name only, never
  the email. The state lets the Audit keep a current member's id and drop a former member's
  (ca-security). Anyone never a member (a platform admin from elsewhere) is missing from the
  map. No other read may use it (guarded in `OrganizationAuditNamesTest`).
  """
  @spec ever_members(binary(), [binary()]) :: %{
          binary() => {binary() | nil, :active | :former}
        }
  def ever_members(_organization_id, []), do: %{}

  def ever_members(organization_id, user_ids)
      when is_binary(organization_id) and is_list(user_ids) do
    OrganizationMembershipRow
    |> join(:inner, [m], u in UserRow, on: m.user_id == u.user_id)
    |> where([m, _u], m.organization_id == ^organization_id and m.user_id in ^Enum.uniq(user_ids))
    |> select([m, u], {u.user_id, u.display_name, m.lifecycle_state})
    |> Repo.all()
    |> Map.new(fn {id, name, state} ->
      {id, {present(name), if(state == "active", do: :active, else: :former)}}
    end)
  end

  defp present(name) when is_binary(name) and name != "", do: name
  defp present(_none), do: nil
end
