defmodule Cadence.Dashboards.UserPreferences do
  @moduledoc """
  Durable personal dashboard navigation preferences.

  Stars and recency are scoped to the current user, organization, and mission.
  The store validates that a dashboard belongs to that same scope before
  recording a preference.
  """

  import Ecto.Query

  alias Cadence.Dashboards.DashboardUserPreference
  alias Cadence.Dashboards.DocumentStore.DashboardRow
  alias Cadence.Dashboards.UserPreferences.PreferenceRow
  alias Cadence.Ids
  alias Cadence.Repo

  @conflict_target [:organization_id, :mission_id, :user_id, :dashboard_id]

  @spec list(binary(), binary(), binary()) :: [DashboardUserPreference.t()]
  def list(organization_id, mission_id, user_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(user_id) do
    PreferenceRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.user_id == ^user_id
    )
    |> order_by([row], desc: row.starred, desc_nulls_last: row.last_viewed_at)
    |> Repo.all()
    |> Enum.map(&PreferenceRow.to_domain/1)
  end

  @spec set_starred(binary(), binary(), binary(), binary(), boolean(), keyword()) ::
          {:ok, DashboardUserPreference.t()} | {:error, :dashboard_not_found | Ecto.Changeset.t()}
  def set_starred(organization_id, mission_id, user_id, dashboard_id, starred, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(user_id) and
             is_binary(dashboard_id) and is_boolean(starred) and is_list(opts) do
    upsert_preference(
      organization_id,
      mission_id,
      user_id,
      dashboard_id,
      [starred: starred],
      opts
    )
  end

  @spec record_view(binary(), binary(), binary(), binary(), keyword()) ::
          {:ok, DashboardUserPreference.t()} | {:error, :dashboard_not_found | Ecto.Changeset.t()}
  def record_view(organization_id, mission_id, user_id, dashboard_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(user_id) and
             is_binary(dashboard_id) and is_list(opts) do
    viewed_at = observed_at(opts)

    upsert_preference(
      organization_id,
      mission_id,
      user_id,
      dashboard_id,
      [last_viewed_at: viewed_at],
      opts
    )
  end

  defp upsert_preference(
         organization_id,
         mission_id,
         user_id,
         dashboard_id,
         changes,
         opts
       ) do
    case dashboard(organization_id, mission_id, dashboard_id) do
      %DashboardRow{} ->
        now = observed_at(opts)

        attrs = %{
          dashboard_user_preference_id: Ids.new("dashboard_preference"),
          organization_id: organization_id,
          mission_id: mission_id,
          user_id: user_id,
          dashboard_id: dashboard_id,
          starred: Keyword.get(changes, :starred, false),
          last_viewed_at: Keyword.get(changes, :last_viewed_at)
        }

        update_fields = changes ++ [updated_at: now]

        attrs
        |> PreferenceRow.changeset()
        |> Repo.insert(
          conflict_target: @conflict_target,
          on_conflict: [set: update_fields],
          returning: true
        )
        |> case do
          {:ok, row} -> {:ok, PreferenceRow.to_domain(row)}
          {:error, changeset} -> {:error, changeset}
        end

      nil ->
        {:error, :dashboard_not_found}
    end
  end

  defp dashboard(organization_id, mission_id, dashboard_id) do
    Repo.get_by(DashboardRow,
      organization_id: organization_id,
      mission_id: mission_id,
      dashboard_id: dashboard_id,
      lifecycle_state: "active"
    )
  end

  defp observed_at(opts) do
    case Keyword.get(opts, :observed_at) do
      callback when is_function(callback, 0) -> callback.() |> microsecond_precision()
      %DateTime{} = observed_at -> microsecond_precision(observed_at)
      _missing -> DateTime.utc_now()
    end
  end

  defp microsecond_precision(%DateTime{microsecond: {microsecond, _precision}} = observed_at) do
    %DateTime{observed_at | microsecond: {microsecond, 6}}
  end
end
