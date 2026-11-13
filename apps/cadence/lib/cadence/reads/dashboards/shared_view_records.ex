defmodule Cadence.Reads.Dashboards.SharedViewRecords do
  @moduledoc """
  The facts behind a shared view (D20): who made a share or snapshot and when, and why its link
  no longer opens (revoked, expired, deleted). `SharedViews.load/5` answers only the view, so a
  link that stopped working can say what happened instead of a bare not-found.
  """

  alias Cadence.Accounts
  alias Cadence.Dashboards.{DashboardShare, DashboardSnapshot}
  alias Cadence.Repo

  @spec fetch(binary(), binary(), :share | :snapshot, binary()) :: {:ok, map()} | :error
  def fetch(organization_id, mission_id, :share, id) do
    case Repo.get_by(DashboardShare,
           dashboard_share_id: id,
           organization_id: organization_id,
           mission_id: mission_id
         ) do
      nil ->
        :error

      share ->
        {:ok,
         %{
           id: id,
           dashboard_id: share.dashboard_id,
           data_visibility: share.data_visibility,
           created_at: share.inserted_at,
           created_by: person(share.created_by),
           expires_at: share.expires_at,
           revoked_at: share.revoked_at,
           revoked_by: person(share.revoked_by)
         }}
    end
  end

  def fetch(organization_id, mission_id, :snapshot, id) do
    case Repo.get_by(DashboardSnapshot,
           dashboard_snapshot_id: id,
           organization_id: organization_id,
           mission_id: mission_id
         ) do
      nil ->
        :error

      snapshot ->
        context = snapshot.runtime_context || %{}

        {:ok,
         %{
           id: id,
           dashboard_id: snapshot.dashboard_id,
           version: snapshot.dashboard_version,
           data_visibility: snapshot.data_visibility,
           window: window(snapshot.data_semantics, context),
           created_at: snapshot.inserted_at,
           created_by: person(snapshot.created_by),
           deleted_at: snapshot.deleted_at,
           deleted_by: person(snapshot.deleted_by)
         }}
    end
  end

  defp window("frozen_time_window", %{"from" => from, "to" => to})
       when is_binary(from) and is_binary(to),
       do: %{from: from, to: to}

  defp window(_semantics, _context), do: nil

  defp person(id) when is_binary(id) do
    case Accounts.fetch_user(id) do
      {:ok, user} -> %{id: id, name: user.display_name || user.email, kind: "user"}
      _not_a_user -> %{id: id, name: nil, kind: "user"}
    end
  end

  defp person(_none), do: nil
end
