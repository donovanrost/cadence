defmodule CadenceWeb.OpsDashboardShowLive.HealthSnapshotEvents do
  @moduledoc false

  alias Cadence.Dashboards
  alias CadenceWeb.OpsDashboardShowLive.DashboardActionContext

  @snapshot_schema "dashboard_health_snapshot.v1"

  def capture_dashboard_health_snapshot(socket, params, opts \\ []) when is_map(params) do
    # authz pending: Gate dashboard health snapshot capture once RBAC exists.
    with {:ok, snapshot} <- snapshot_payload(params),
         {:ok, event} <- record_health_snapshot(socket, snapshot, opts) do
      socket
      |> DashboardActionContext.refresh_lifecycle_events(opts)
      |> DashboardActionContext.target_activity(:health_snapshots, event, opts)
      |> flash(:info, "Dashboard health snapshot captured.", opts)
    else
      {:error, :missing_health_snapshot} ->
        flash(socket, :error, "Dashboard health snapshot is no longer available.", opts)

      {:error, :invalid_health_snapshot} ->
        flash(socket, :error, "Dashboard health snapshot is invalid.", opts)

      {:error, :dashboard_not_found} ->
        flash(socket, :error, "Dashboard no longer exists.", opts)

      {:error, :dashboard_archived} ->
        flash(socket, :error, "Archived dashboards cannot capture health snapshots.", opts)

      {:error, _reason} ->
        flash(socket, :error, "Failed to capture dashboard health snapshot.", opts)
    end
  end

  defp snapshot_payload(params) do
    params
    |> Map.get("snapshot")
    |> decode_snapshot()
  end

  defp decode_snapshot(value) when is_binary(value) and value != "" do
    with {:ok, snapshot} <- Jason.decode(value),
         true <- Map.get(snapshot, "schema") == @snapshot_schema,
         snapshot_id when is_binary(snapshot_id) and snapshot_id != "" <-
           Map.get(snapshot, "snapshot_id") do
      {:ok, snapshot}
    else
      _invalid -> {:error, :invalid_health_snapshot}
    end
  end

  defp decode_snapshot(_value), do: {:error, :missing_health_snapshot}

  defp record_health_snapshot(socket, snapshot, opts) do
    {organization_id, mission_id, dashboard_id} = DashboardActionContext.scoped_ids(socket)

    record_health_snapshot_fn(opts).(
      organization_id,
      mission_id,
      dashboard_id,
      snapshot,
      DashboardActionContext.actor_opts(socket)
    )
  end

  defp record_health_snapshot_fn(opts) do
    Keyword.get(
      opts,
      :record_dashboard_health_snapshot,
      &Dashboards.record_dashboard_health_snapshot/5
    )
  end

  defp flash(socket, kind, message, opts) do
    DashboardActionContext.flash(socket, kind, message, opts)
  end
end
