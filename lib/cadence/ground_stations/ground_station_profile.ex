defmodule Cadence.GroundStations.GroundStationProfile do
  @moduledoc """
  Minimal ground station profile used for contact transport resolution.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ground_station_profiles" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission

    field :ground_station_target_id, :binary_id

    field :name, :string
    field :enabled, :boolean, default: true
    field :resources, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :ground_station_target_id,
      :name,
      :enabled,
      :resources
    ])
    |> validate_required([
      :organization_id,
      :mission_id,
      :ground_station_target_id,
      :name,
      :resources
    ])
    |> validate_resources()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:mission_id)
    |> foreign_key_constraint(:ground_station_target_id)
  end

  defp validate_resources(changeset) do
    resources = get_field(changeset, :resources)

    cond do
      is_nil(resources) ->
        add_error(changeset, :resources, "must be a map")

      is_map(resources) ->
        antennas = Map.get(resources, "antennas")

        if is_nil(antennas) or is_list(antennas) do
          changeset
        else
          add_error(changeset, :resources, "antennas must be a list")
        end

      true ->
        add_error(changeset, :resources, "must be a map")
    end
  end
end
