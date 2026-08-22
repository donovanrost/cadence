defmodule Cadence.Comms.GroundStationRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Comms.GroundStation
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]

  schema "comms_ground_stations" do
    field(:ground_station_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:lifecycle_state, :string)
    field(:display_name, :string)
    field(:provider, :string)
    field(:region, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :ground_station_id,
    :mission_id,
    :lifecycle_state,
    :display_name,
    :metadata
  ]

  @spec changeset(GroundStation.t()) :: Ecto.Changeset.t()
  def changeset(%GroundStation{} = ground_station) do
    %__MODULE__{}
    |> cast(domain_attrs(ground_station), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_format(:ground_station_id, ~r/^[A-Za-z0-9][A-Za-z0-9_.:-]*$/)
    |> validate_length(:ground_station_id, min: 1, max: 120)
    |> validate_length(:display_name, min: 1, max: 200)
    |> unique_constraint([:mission_id, :ground_station_id],
      name: :comms_ground_stations_scope_idx
    )
  end

  @spec to_domain(struct()) :: GroundStation.t()
  def to_domain(%__MODULE__{} = row) do
    GroundStation.new(%{
      ground_station_id: row.ground_station_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      lifecycle_state: row.lifecycle_state,
      display_name: row.display_name,
      provider: row.provider,
      region: row.region,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%GroundStation{} = ground_station) do
    %{
      ground_station_id: ground_station.ground_station_id,
      organization_id: ground_station.organization_id,
      mission_id: ground_station.mission_id,
      lifecycle_state: Atom.to_string(ground_station.lifecycle_state),
      display_name: ground_station.display_name,
      provider: ground_station.provider,
      region: ground_station.region,
      metadata: JsonDocument.wrap_value(ground_station.metadata)
    }
  end

  defp all_fields do
    [
      :ground_station_id,
      :organization_id,
      :mission_id,
      :lifecycle_state,
      :display_name,
      :provider,
      :region,
      :metadata
    ]
  end
end
