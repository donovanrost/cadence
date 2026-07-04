defmodule Cadence.Dashboards.InvestigationPresets do
  @moduledoc """
  Durable store for dashboard investigation presets.
  """

  import Ecto.Query

  alias Cadence.Dashboards.InvestigationPreset
  alias Cadence.Persistence.Schemas.{DashboardInvestigationPresetRow, OpsDashboardRow}
  alias Cadence.Repo

  @spec save(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, InvestigationPreset.t()}
          | {:error, :dashboard_not_found | :dashboard_archived | Ecto.Changeset.t()}
  def save(organization_id, mission_id, dashboard_id, attrs, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_map(attrs) do
    with %OpsDashboardRow{} = dashboard <-
           get_dashboard(organization_id, mission_id, dashboard_id),
         :ok <- reject_archived(dashboard) do
      attrs
      |> Map.merge(%{
        organization_id: organization_id,
        mission_id: mission_id,
        dashboard_id: dashboard_id,
        created_by: Keyword.get(opts, :actor_id) || map_value(attrs, :created_by),
        updated_by: Keyword.get(opts, :actor_id) || map_value(attrs, :updated_by)
      })
      |> InvestigationPreset.new()
      |> DashboardInvestigationPresetRow.changeset()
      |> Repo.insert()
      |> case do
        {:ok, row} -> {:ok, DashboardInvestigationPresetRow.to_domain(row)}
        {:error, changeset} -> {:error, changeset}
      end
    else
      nil -> {:error, :dashboard_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec list(binary(), binary(), binary(), keyword()) :: [InvestigationPreset.t()]
  def list(organization_id, mission_id, dashboard_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_list(opts) do
    DashboardInvestigationPresetRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.dashboard_id == ^dashboard_id
    )
    |> maybe_filter_kind(Keyword.get(opts, :preset_kind))
    |> order_by([row], desc: row.inserted_at, asc: row.name)
    |> limit(^result_limit(opts))
    |> Repo.all()
    |> Enum.map(&DashboardInvestigationPresetRow.to_domain/1)
  end

  @spec fetch(binary(), binary(), binary(), binary()) ::
          {:ok, InvestigationPreset.t()} | {:error, :investigation_preset_not_found}
  def fetch(organization_id, mission_id, dashboard_id, preset_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_binary(preset_id) do
    case Repo.get_by(DashboardInvestigationPresetRow,
           organization_id: organization_id,
           mission_id: mission_id,
           dashboard_id: dashboard_id,
           dashboard_investigation_preset_id: preset_id
         ) do
      nil ->
        {:error, :investigation_preset_not_found}

      %DashboardInvestigationPresetRow{} = row ->
        {:ok, DashboardInvestigationPresetRow.to_domain(row)}
    end
  end

  @spec delete(binary(), binary(), binary(), binary()) ::
          :ok | {:error, :investigation_preset_not_found}
  def delete(organization_id, mission_id, dashboard_id, preset_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(dashboard_id) and
             is_binary(preset_id) do
    case Repo.get_by(DashboardInvestigationPresetRow,
           organization_id: organization_id,
           mission_id: mission_id,
           dashboard_id: dashboard_id,
           dashboard_investigation_preset_id: preset_id
         ) do
      nil ->
        {:error, :investigation_preset_not_found}

      %DashboardInvestigationPresetRow{} = row ->
        Repo.delete!(row)
        :ok
    end
  end

  defp get_dashboard(organization_id, mission_id, dashboard_id) do
    Repo.get_by(OpsDashboardRow,
      organization_id: organization_id,
      mission_id: mission_id,
      dashboard_id: dashboard_id
    )
  end

  defp reject_archived(%OpsDashboardRow{} = row) do
    if OpsDashboardRow.archived?(row), do: {:error, :dashboard_archived}, else: :ok
  end

  defp maybe_filter_kind(query, nil), do: query

  defp maybe_filter_kind(query, kind) do
    kind = enum_string(kind)
    where(query, [row], row.preset_kind == ^kind)
  end

  defp result_limit(opts) do
    opts
    |> Keyword.get(:limit, 100)
    |> min(500)
    |> max(1)
  end

  defp map_value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value
end
