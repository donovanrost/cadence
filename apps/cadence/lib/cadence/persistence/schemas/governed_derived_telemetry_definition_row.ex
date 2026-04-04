defmodule Cadence.Persistence.Schemas.GovernedDerivedTelemetryDefinitionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.DerivedTelemetry.Definition
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "governed_derived_telemetry_definitions" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:derived_definition_id, :string)
    field(:point_id, :string)
    field(:point_name, :string)
    field(:expression, :string)
    field(:version, :integer)
    field(:source_point_ids, {:array, :string}, default: [])
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :mission_id,
    :derived_definition_id,
    :point_id,
    :point_name,
    :expression,
    :version,
    :source_point_ids
  ]

  @spec changeset(Definition.t()) :: Ecto.Changeset.t()
  def changeset(%Definition{} = definition) do
    %__MODULE__{}
    |> cast(
      %{
        mission_id: definition.mission_id,
        derived_definition_id: definition.derived_definition_id,
        point_id: definition.point_id,
        point_name: definition.point_name,
        expression: definition.expression,
        version: definition.version,
        source_point_ids: definition.source_point_ids,
        metadata: JsonDocument.encode(definition.metadata)
      },
      all_fields()
    )
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:mission_id, :derived_definition_id, :version],
      name: :governed_derived_telemetry_definitions_scope_idx
    )
  end

  @spec to_domain(struct()) :: Definition.t()
  def to_domain(%__MODULE__{} = definition_row) do
    %Definition{
      derived_definition_id: definition_row.derived_definition_id,
      mission_id: definition_row.mission_id,
      point_id: definition_row.point_id,
      point_name: definition_row.point_name,
      expression: definition_row.expression,
      version: definition_row.version,
      source_point_ids: definition_row.source_point_ids,
      metadata: definition_row.metadata
    }
  end

  defp all_fields do
    [
      :mission_id,
      :derived_definition_id,
      :point_id,
      :point_name,
      :expression,
      :version,
      :source_point_ids,
      :metadata
    ]
  end
end
