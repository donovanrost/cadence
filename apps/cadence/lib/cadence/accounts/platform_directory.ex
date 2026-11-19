defmodule Cadence.Accounts.PlatformDirectory do
  @moduledoc """
  Cross-organization queries for the platform admin area (console L7), over the identity
  context's own rows. No authorization here: callers (`Cadence.Administration.Console*`) admit
  a platform administrator in admin mode first.
  """

  import Ecto.Query

  alias Cadence.Accounts.{OrganizationInvitationRow, OrganizationMembershipRow, UserRow}
  alias Cadence.Auth.{ServiceAccountableRow, ServiceIdentityRow}
  alias Cadence.Missions.MissionRow
  alias Cadence.Organizations.OrganizationRow
  alias Cadence.Repo

  @doc "Organizations by slug after `after_id`, optionally matching `q` in name or slug."
  def organizations(q, after_id, limit) do
    OrganizationRow
    |> search(q)
    |> after_org(after_id)
    |> order_by([o], asc: o.slug, asc: o.organization_id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&organization_view/1)
  end

  def organization(id) do
    case Repo.get(OrganizationRow, id) do
      nil -> nil
      row -> organization_view(row)
    end
  end

  def organization_names(ids) do
    OrganizationRow
    |> where([o], o.organization_id in ^ids)
    |> select([o], {o.organization_id, o.display_name})
    |> Repo.all()
    |> Map.new()
  end

  def slug_taken?(slug), do: Repo.exists?(where(OrganizationRow, [o], o.slug == ^slug))

  @doc "Active members per organization: `%{organization_id => count}`."
  def member_counts(ids) do
    OrganizationMembershipRow
    |> join(:inner, [m], u in UserRow, on: u.user_id == m.user_id)
    |> where([m], m.organization_id in ^ids and m.lifecycle_state == "active")
    |> group_by([m], m.organization_id)
    |> select([m], {m.organization_id, count()})
    |> Repo.all()
    |> Map.new()
  end

  def mission_counts(ids) do
    MissionRow
    |> where([m], m.organization_id in ^ids)
    |> group_by([m], m.organization_id)
    |> select([m], {m.organization_id, count()})
    |> Repo.all()
    |> Map.new()
  end

  def members(organization_id, limit) do
    OrganizationMembershipRow
    |> join(:inner, [m], u in UserRow, on: u.user_id == m.user_id)
    |> where([m], m.organization_id == ^organization_id and m.lifecycle_state == "active")
    |> order_by([_m, u], asc: u.display_name, asc: u.email)
    |> limit(^limit)
    |> select([m, u], %{user_id: u.user_id, name: u.display_name, email: u.email, role: m.role})
    |> Repo.all()
  end

  def pending_invitations(organization_id, limit) do
    OrganizationInvitationRow
    |> join(:left, [i], u in UserRow, on: u.user_id == i.invited_by_user_id)
    |> where([i], i.organization_id == ^organization_id and i.status == "pending")
    |> order_by([i], desc: i.inserted_at)
    |> limit(^limit)
    |> select([i, u], %{
      id: i.organization_invitation_id,
      email: i.email,
      role: i.membership_role,
      inviter: coalesce(u.display_name, u.email),
      invited_at: i.inserted_at,
      expires_at: i.expires_at
    })
    |> Repo.all()
  end

  def missions(organization_id, limit) do
    MissionRow
    |> where([m], m.organization_id == ^organization_id)
    |> order_by([m], asc: m.display_name)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(
      &%{id: &1.mission_id, name: &1.display_name, slug: &1.slug, created_at: &1.inserted_at}
    )
  end

  @doc "Every mission with its organization, by organization then mission slug."
  def all_missions(limit) do
    MissionRow
    |> join(:inner, [m], o in OrganizationRow, on: o.organization_id == m.organization_id)
    |> order_by([m, o], asc: o.slug, asc: m.slug)
    |> limit(^limit)
    |> select([m, o], %{
      organization: %{id: o.organization_id, name: o.display_name, slug: o.slug},
      mission: %{id: m.mission_id, name: m.display_name, slug: m.slug}
    })
    |> Repo.all()
  end

  @doc "Active service identities, newest first, optionally for one organization."
  def service_identities(organization_id, limit) do
    organization_id
    |> service_identity_query()
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&service_identity_view/1)
  end

  @doc "One active service identity of the organization, in the same shape as the list, or nil."
  def service_identity(organization_id, id)
      when is_binary(organization_id) and organization_id != "" and is_binary(id) do
    organization_id
    |> service_identity_query()
    |> where([s], s.service_identity_id == ^id)
    |> Repo.one()
    |> then(&(&1 && service_identity_view(&1)))
  end

  def service_identity(_organization_id, _id), do: nil

  defp service_identity_query(organization_id) do
    ServiceIdentityRow
    |> where([s], s.lifecycle_state == "active")
    |> for_organization(organization_id)
    |> join(:inner, [s], o in OrganizationRow, on: o.organization_id == s.organization_id)
    |> join(:left, [s], m in MissionRow, on: m.mission_id == s.mission_id)
    # The issuer the server recorded (#280), never the client-writable metadata.
    |> join(:left, [s], a in ServiceAccountableRow,
      on:
        a.organization_id == s.organization_id and
          a.service_identity_id == s.service_identity_id and a.event == "issued" and
          a.actor_kind == "user"
    )
    |> order_by([s], desc: s.inserted_at, desc: s.service_identity_id)
    |> select([s, o, m, a], %{
      row: s,
      organization: %{id: o.organization_id, name: o.display_name},
      mission: %{id: m.mission_id, name: m.display_name},
      issued_by: a.user_id
    })
  end

  defp service_identity_view(%{row: s} = found),
    do: %{
      id: s.service_identity_id,
      name: s.display_name,
      organization: found.organization,
      capabilities: s.capabilities,
      mission: found.mission.id && found.mission,
      created_at: s.inserted_at,
      created_by_id: found.issued_by
    }

  defp organization_view(row),
    do: %{
      id: row.organization_id,
      name: row.display_name,
      slug: row.slug,
      created_at: row.inserted_at
    }

  defp for_organization(query, id) when is_binary(id) and id != "",
    do: where(query, [s], s.organization_id == ^id)

  defp for_organization(query, _id), do: query

  defp search(query, q) when is_binary(q) and q != "" do
    pattern = "%" <> String.replace(String.trim(q), ~w(% _ \\), &("\\" <> &1)) <> "%"
    where(query, [o], ilike(o.display_name, ^pattern) or ilike(o.slug, ^pattern))
  end

  defp search(query, _q), do: query

  defp after_org(query, id) when is_binary(id) do
    case Repo.get(OrganizationRow, id) do
      nil ->
        query

      last ->
        where(
          query,
          [o],
          o.slug > ^last.slug or
            (o.slug == ^last.slug and o.organization_id > ^last.organization_id)
        )
    end
  end

  defp after_org(query, _id), do: query
end
