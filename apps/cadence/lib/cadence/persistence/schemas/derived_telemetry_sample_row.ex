defmodule Cadence.Persistence.Schemas.DerivedTelemetrySampleRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.DerivedTelemetry.Sample
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:derived_sample_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "derived_telemetry_samples" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:spacecraft_id, :string)
    field(:point_id, :string)
    field(:point_name, :string)
    field(:derived_definition_id, :string)
    field(:derived_definition_version, :integer)
    field(:trigger_sample_id, :string)
    field(:value, :map)
    field(:quality_state, :string)
    field(:generation_time, :utc_datetime_usec)
    field(:receipt_time, :utc_datetime_usec)
    field(:provenance, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :derived_sample_id,
    :mission_id,
    :point_id,
    :point_name,
    :derived_definition_id,
    :derived_definition_version,
    :trigger_sample_id,
    :value,
    :quality_state,
    :receipt_time
  ]

  @spec changeset(Sample.t()) :: Ecto.Changeset.t()
  def changeset(%Sample{} = sample) do
    %__MODULE__{}
    |> cast(domain_attrs(sample), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:trigger_sample_id)
  end

  @spec to_domain(struct()) :: Sample.t()
  def to_domain(%__MODULE__{} = sample_row) do
    %Sample{
      derived_sample_id: sample_row.derived_sample_id,
      mission_id: sample_row.mission_id,
      spacecraft_id: sample_row.spacecraft_id,
      point_id: sample_row.point_id,
      point_name: sample_row.point_name,
      derived_definition_id: sample_row.derived_definition_id,
      derived_definition_version: sample_row.derived_definition_version,
      trigger_sample_id: sample_row.trigger_sample_id,
      value: JsonDocument.unwrap_value(sample_row.value),
      quality_state: quality_state(sample_row.quality_state),
      generation_time: sample_row.generation_time,
      receipt_time: sample_row.receipt_time,
      provenance: sample_row.provenance
    }
  end

  defp domain_attrs(%Sample{} = sample) do
    %{
      derived_sample_id: sample.derived_sample_id,
      mission_id: sample.mission_id,
      spacecraft_id: sample.spacecraft_id,
      point_id: sample.point_id,
      point_name: sample.point_name,
      derived_definition_id: sample.derived_definition_id,
      derived_definition_version: sample.derived_definition_version,
      trigger_sample_id: sample.trigger_sample_id,
      value: JsonDocument.wrap_value(sample.value),
      quality_state: Atom.to_string(sample.quality_state),
      generation_time: sample.generation_time,
      receipt_time: sample.receipt_time,
      provenance: JsonDocument.encode(sample.provenance)
    }
  end

  defp all_fields do
    [
      :derived_sample_id,
      :mission_id,
      :spacecraft_id,
      :point_id,
      :point_name,
      :derived_definition_id,
      :derived_definition_version,
      :trigger_sample_id,
      :value,
      :quality_state,
      :generation_time,
      :receipt_time,
      :provenance
    ]
  end

  defp quality_state("good"), do: :good
  defp quality_state("suspect"), do: :suspect
  defp quality_state("bad"), do: :bad
end
