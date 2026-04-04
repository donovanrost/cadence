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
    |> unique_constraint([:mission_id, :spacecraft_id], name: :mission_spacecraft_scope_idx)
  end

  @spec to_domain(struct()) :: Spacecraft.t()
  def to_domain(%__MODULE__{} = row) do
    Spacecraft.new(%{
      spacecraft_id: row.spacecraft_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      display_name: row.display_name,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%Spacecraft{} = spacecraft) do
    %{
      spacecraft_id: spacecraft.spacecraft_id,
      organization_id: spacecraft.organization_id,
      mission_id: spacecraft.mission_id,
      display_name: spacecraft.display_name,
      metadata: JsonDocument.wrap_value(spacecraft.metadata)
    }
  end

  defp all_fields do
    [:spacecraft_id, :organization_id, :mission_id, :display_name, :metadata]
  end
end
