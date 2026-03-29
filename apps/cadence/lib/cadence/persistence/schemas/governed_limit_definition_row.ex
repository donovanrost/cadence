defmodule Cadence.Persistence.Schemas.GovernedLimitDefinitionRow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Limits.Definition
  alias Cadence.Persistence.JsonDocument

  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "governed_limit_definitions" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:limit_definition_id, :string)
    field(:point_id, :string)
    field(:version, :integer)
    field(:limit_set_name, :string)
    field(:thresholds, :map, default: %{})
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :mission_id,
    :limit_definition_id,
    :point_id,
    :version,
    :limit_set_name,
    :thresholds
  ]

  @spec changeset(Definition.t()) :: Ecto.Changeset.t()
  def changeset(%Definition{} = definition) do
    %__MODULE__{}
    |> cast(
      %{
        mission_id: definition.mission_id,
        limit_definition_id: definition.limit_definition_id,
        point_id: definition.point_id,
        version: definition.version,
        limit_set_name: definition.limit_set_name,
        thresholds: JsonDocument.encode(definition.thresholds),
        metadata: JsonDocument.encode(definition.metadata)
      },
      all_fields()
    )
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:mission_id, :limit_definition_id, :version],
      name: :governed_limit_definitions_scope_idx
    )
  end

  @spec to_domain(struct()) :: Definition.t()
  def to_domain(%__MODULE__{} = definition_row) do
    %Definition{
      limit_definition_id: definition_row.limit_definition_id,
      mission_id: definition_row.mission_id,
      point_id: definition_row.point_id,
      version: definition_row.version,
      limit_set_name: definition_row.limit_set_name,
      thresholds: JsonDocument.unwrap_value(definition_row.thresholds),
      metadata: definition_row.metadata
    }
  end

  defp all_fields do
    [
      :mission_id,
      :limit_definition_id,
      :point_id,
      :version,
      :limit_set_name,
      :thresholds,
      :metadata
    ]
  end
end
