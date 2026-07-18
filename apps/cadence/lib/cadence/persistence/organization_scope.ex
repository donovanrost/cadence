defmodule Cadence.Persistence.OrganizationScope do
  @moduledoc """
  Persistence helper for propagating `organization_id` onto mission-owned row
  schemas.

  This keeps the shared-schema backfill usable while the wider domain/runtime
  model still carries `mission_id` more broadly than `organization_id`.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias Cadence.Missions.MissionRow
  alias Cadence.Repo

  @spec put_organization_id(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def put_organization_id(%Ecto.Changeset{} = changeset) do
    case {organization_id(changeset), mission_id(changeset)} do
      {organization_id, _mission_id} when is_binary(organization_id) and organization_id != "" ->
        changeset

      {nil, mission_id} when is_binary(mission_id) and mission_id != "" ->
        case fetch_organization_id(mission_id) do
          nil -> changeset
          organization_id -> put_change(changeset, :organization_id, organization_id)
        end

      _other ->
        changeset
    end
  end

  @spec organization_id_for_mission(binary()) :: binary() | nil
  def organization_id_for_mission(mission_id) when is_binary(mission_id) do
    fetch_organization_id(mission_id)
  end

  defp organization_id(changeset), do: get_field(changeset, :organization_id)
  defp mission_id(changeset), do: get_field(changeset, :mission_id)

  defp fetch_organization_id(mission_id) do
    MissionRow
    |> where([mission], mission.mission_id == ^mission_id)
    |> select([mission], mission.organization_id)
    |> Repo.one()
  end
end
