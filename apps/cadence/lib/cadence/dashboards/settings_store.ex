defmodule Cadence.Dashboards.SettingsStore do
  @moduledoc false
  import Ecto.Query
  alias Cadence.Dashboards.{DashboardDeployment, DashboardShare, DashboardSnapshot}
  alias Cadence.Dashboards.DocumentStore.DashboardRow
  alias Cadence.Repo

  def dashboard(org, mission, dashboard),
    do: scoped(DashboardRow, org, mission, dashboard) |> Repo.one()

  def with_dashboard(org, mission, dashboard, lock, callback) when lock in [:read, :write] do
    Repo.transaction(fn ->
      row = scoped(DashboardRow, org, mission, dashboard)
      row = if lock == :write, do: lock(row, "FOR UPDATE"), else: lock(row, "FOR SHARE")

      case Repo.one(row) do
        nil -> Repo.rollback(:unavailable)
        row -> callback.(row)
      end
    end)
  end

  @doc "Runs a read projection against plain settings values while holding the dashboard read lock."
  def with_settings_snapshot(org, mission, dashboard, callback) when is_function(callback, 1) do
    with_dashboard(org, mission, dashboard, :read, fn row ->
      snapshot =
        row
        |> Map.take([
          :organization_id,
          :mission_id,
          :dashboard_id,
          :latest_version,
          :lock_version,
          :published_version,
          :lifecycle_state
        ])
        |> Map.put(:document, DashboardRow.to_document(row))

      callback.(snapshot)
    end)
  end

  def shares(org, mission, dashboard, cursor) do
    scoped(DashboardShare, org, mission, dashboard)
    |> select([s], %{
      id: s.dashboard_share_id,
      data_visibility: s.data_visibility,
      expires_at: s.expires_at,
      revoked_at: s.revoked_at,
      created_at: s.inserted_at
    })
    |> page(:dashboard_share_id, cursor)
  end

  def snapshots(org, mission, dashboard, cursor) do
    scoped(DashboardSnapshot, org, mission, dashboard)
    |> select([s], %{
      id: s.dashboard_snapshot_id,
      document_version: s.dashboard_version,
      data_visibility: s.data_visibility,
      data_semantics: s.data_semantics,
      created_at: s.inserted_at
    })
    |> page(:dashboard_snapshot_id, cursor)
  end

  def deployments(org, mission, dashboard, cursor) do
    scoped(DashboardDeployment, org, mission, dashboard)
    |> select([d], %{
      id: d.dashboard_deployment_id,
      document_version: d.dashboard_version,
      environment: fragment("left(?, 121)", d.environment),
      digest: d.artifact_digest,
      status: d.status,
      created_at: d.inserted_at
    })
    |> page(:dashboard_deployment_id, cursor)
  end

  def revoke_share(org, mission, dashboard, id) do
    share =
      scoped(DashboardShare, org, mission, dashboard)
      |> where([s], s.dashboard_share_id == ^id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    case share do
      nil ->
        {:error, :unavailable}

      %DashboardShare{revoked_at: nil} ->
        share |> DashboardShare.changeset(%{revoked_at: DateTime.utc_now()}) |> Repo.update()

      _ ->
        {:error, :conflict}
    end
  end

  defp scoped(schema, org, mission, dashboard),
    do:
      where(
        schema,
        [r],
        r.organization_id == ^org and r.mission_id == ^mission and r.dashboard_id == ^dashboard
      )

  defp page(query, key, cursor) do
    query = if cursor, do: where(query, [r], field(r, ^key) > ^cursor), else: query
    rows = query |> order_by([r], asc: field(r, ^key)) |> limit(26) |> Repo.all()
    visible = Enum.take(rows, 25)
    %{rows: visible, next: if(length(rows) > 25, do: List.last(visible).id, else: nil)}
  end
end
