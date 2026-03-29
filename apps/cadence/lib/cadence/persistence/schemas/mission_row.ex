defmodule Cadence.Persistence.Schemas.MissionRow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Missions.Mission
  alias Cadence.Persistence.JsonDocument

  @primary_key {:mission_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "missions" do
    field(:organization_id, :string)
    field(:slug, :string)
    field(:display_name, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [:mission_id, :organization_id, :slug, :display_name, :metadata]

  @spec changeset(Mission.t()) :: Ecto.Changeset.t()
  def changeset(%Mission{} = mission) do
    %__MODULE__{}
    |> cast(domain_attrs(mission), all_fields())
    |> validate_required(@required_fields)
    |> unique_constraint([:organization_id, :slug], name: :missions_org_slug_idx)
  end

  @spec to_domain(struct()) :: Mission.t()
  def to_domain(%__MODULE__{} = row) do
    Mission.new(%{
      mission_id: row.mission_id,
      organization_id: row.organization_id,
      slug: row.slug,
      display_name: row.display_name,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%Mission{} = mission) do
    %{
      mission_id: mission.mission_id,
      organization_id: mission.organization_id,
      slug: mission.slug,
      display_name: mission.display_name,
      metadata: JsonDocument.wrap_value(mission.metadata)
    }
  end

  defp all_fields do
    [:mission_id, :organization_id, :slug, :display_name, :metadata]
  end
end
