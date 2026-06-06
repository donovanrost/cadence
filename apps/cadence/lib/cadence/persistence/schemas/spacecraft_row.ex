defmodule Cadence.Persistence.Schemas.SpacecraftRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Spacecraft

  @primary_key {:spacecraft_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "mission_spacecraft" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:display_name, :string)
    field(:scid, :integer)
    field(:spacecraft_type_id, :string)
    field(:spacecraft_type_version, :integer)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [:spacecraft_id, :mission_id, :display_name, :metadata]

  @spec changeset(Spacecraft.t()) :: Ecto.Changeset.t()
  def changeset(%Spacecraft{} = spacecraft) do
    %__MODULE__{}
    |> cast(domain_attrs(spacecraft), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_number(:scid, greater_than_or_equal_to: 0, less_than_or_equal_to: 1023)
    |> validate_type_binding()
    |> unique_constraint([:mission_id, :spacecraft_id], name: :mission_spacecraft_scope_idx)
    |> unique_constraint(:scid, name: :mission_spacecraft_org_mission_scid_idx)
  end

  @spec update_changeset(struct(), Spacecraft.t()) :: Ecto.Changeset.t()
  def update_changeset(%__MODULE__{} = row, %Spacecraft{} = spacecraft) do
    row
    |> cast(domain_attrs(spacecraft), [
      :display_name,
      :scid,
      :spacecraft_type_id,
      :spacecraft_type_version,
      :metadata
    ])
    |> validate_required([:display_name, :metadata])
    |> validate_number(:scid, greater_than_or_equal_to: 0, less_than_or_equal_to: 1023)
    |> validate_type_binding()
    |> unique_constraint(:scid, name: :mission_spacecraft_org_mission_scid_idx)
  end

  @spec to_domain(struct()) :: Spacecraft.t()
  def to_domain(%__MODULE__{} = row) do
    Spacecraft.new(%{
      spacecraft_id: row.spacecraft_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      display_name: row.display_name,
      scid: row.scid,
      spacecraft_type_id: row.spacecraft_type_id,
      spacecraft_type_version: row.spacecraft_type_version,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%Spacecraft{} = spacecraft) do
    %{
      spacecraft_id: spacecraft.spacecraft_id,
      organization_id: spacecraft.organization_id,
      mission_id: spacecraft.mission_id,
      display_name: spacecraft.display_name,
      scid: spacecraft.scid,
      spacecraft_type_id: spacecraft.spacecraft_type_id,
      spacecraft_type_version: spacecraft.spacecraft_type_version,
      metadata: JsonDocument.wrap_value(spacecraft.metadata)
    }
  end

  defp all_fields do
    [
      :spacecraft_id,
      :organization_id,
      :mission_id,
      :display_name,
      :scid,
      :spacecraft_type_id,
      :spacecraft_type_version,
      :metadata
    ]
  end

  defp validate_type_binding(changeset) do
    type_id = Ecto.Changeset.get_field(changeset, :spacecraft_type_id)
    type_version = Ecto.Changeset.get_field(changeset, :spacecraft_type_version)

    case {type_id, type_version} do
      {nil, nil} -> changeset
      {_id, version} when is_integer(version) and version > 0 -> changeset
      _ -> Ecto.Changeset.add_error(changeset, :spacecraft_type_version, "must be set with type")
    end
  end
end
