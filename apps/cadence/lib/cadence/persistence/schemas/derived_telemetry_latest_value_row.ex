defmodule Cadence.Persistence.Schemas.DerivedTelemetryLatestValueRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.DerivedTelemetry.Sample
  alias Cadence.Persistence.JsonDocument

  @mission_scope_key "__mission__"
  @timestamps_opts [type: :utc_datetime_usec]

  schema "derived_telemetry_latest_values" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:spacecraft_scope_id, :string)
    field(:spacecraft_id, :string)
    field(:point_id, :string)
    field(:point_name, :string)
    field(:derived_sample_id, :string)
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
    :mission_id,
    :spacecraft_scope_id,
    :point_id,
    :point_name,
    :derived_sample_id,
    :derived_definition_id,
    :derived_definition_version,
    :trigger_sample_id,
    :value,
    :quality_state,
    :receipt_time
  ]

  @spec changeset(struct(), Sample.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = latest_value_row, %Sample{} = sample) do
    latest_value_row
    |> cast(domain_attrs(sample), all_fields())
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:derived_sample_id)
    |> unique_constraint([:mission_id, :spacecraft_scope_id, :point_id],
      name: :derived_telemetry_latest_values_scope_idx
    )
  end

  @spec to_domain(struct()) :: Sample.t()
  def to_domain(%__MODULE__{} = latest_value_row) do
    %Sample{
      derived_sample_id: latest_value_row.derived_sample_id,
      mission_id: latest_value_row.mission_id,
      spacecraft_id: latest_value_row.spacecraft_id,
      point_id: latest_value_row.point_id,
      point_name: latest_value_row.point_name,
      derived_definition_id: latest_value_row.derived_definition_id,
      derived_definition_version: latest_value_row.derived_definition_version,
      trigger_sample_id: latest_value_row.trigger_sample_id,
      value: JsonDocument.unwrap_value(latest_value_row.value),
      quality_state: quality_state(latest_value_row.quality_state),
      generation_time: latest_value_row.generation_time,
      receipt_time: latest_value_row.receipt_time,
      provenance: latest_value_row.provenance
    }
  end

  defp domain_attrs(%Sample{} = sample) do
    %{
      mission_id: sample.mission_id,
      spacecraft_scope_id: sample.spacecraft_id || @mission_scope_key,
      spacecraft_id: sample.spacecraft_id,
      point_id: sample.point_id,
      point_name: sample.point_name,
      derived_sample_id: sample.derived_sample_id,
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
      :mission_id,
      :spacecraft_scope_id,
      :spacecraft_id,
      :point_id,
      :point_name,
      :derived_sample_id,
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
