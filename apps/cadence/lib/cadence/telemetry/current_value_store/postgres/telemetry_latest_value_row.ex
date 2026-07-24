defmodule Cadence.Telemetry.CurrentValueStore.Postgres.TelemetryLatestValueRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Telemetry.{Sample, SourceFilters}

  @mission_scope_key "__mission__"
  @timestamps_opts [type: :utc_datetime_usec]

  schema "telemetry_latest_values" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:spacecraft_scope_id, :string)
    field(:spacecraft_id, :string)
    field(:point_id, :string)
    field(:point_name, :string)
    field(:realm, :string)
    field(:data_source_id, :string)
    field(:binding_id, :string)
    field(:sample_id, :string)
    field(:packet_id, :string)
    field(:evidence_id, :string)
    field(:packet_definition_id, :string)
    field(:packet_definition_version, :integer)
    field(:raw_value, :map)
    field(:engineering_value, :map)
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
    :realm,
    :data_source_id,
    :binding_id,
    :sample_id,
    :packet_id,
    :evidence_id,
    :packet_definition_id,
    :packet_definition_version,
    :raw_value,
    :engineering_value,
    :quality_state,
    :receipt_time
  ]

  @spec changeset(struct(), Sample.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = latest_value_row, %Sample{} = sample) do
    latest_value_row
    |> cast(row_attrs(sample), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:packet_id)
    |> foreign_key_constraint(:evidence_id)
    |> unique_constraint(
      [:mission_id, :spacecraft_scope_id, :point_id, :realm, :data_source_id, :binding_id],
      name: :telemetry_latest_values_scope_idx
    )
  end

  @spec insert_attrs(Sample.t(), DateTime.t()) :: map()
  def insert_attrs(%Sample{} = sample, %DateTime{} = now) do
    sample
    |> row_attrs()
    |> Map.merge(%{inserted_at: now, updated_at: now})
  end

  @spec to_domain(struct()) :: Sample.t()
  def to_domain(%__MODULE__{} = latest_value_row) do
    %Sample{
      sample_id: latest_value_row.sample_id,
      mission_id: latest_value_row.mission_id,
      spacecraft_id: latest_value_row.spacecraft_id,
      point_id: latest_value_row.point_id,
      point_name: latest_value_row.point_name,
      packet_definition_id: latest_value_row.packet_definition_id,
      packet_definition_version: latest_value_row.packet_definition_version,
      packet_id: latest_value_row.packet_id,
      evidence_id: latest_value_row.evidence_id,
      raw_value: JsonDocument.unwrap_value(latest_value_row.raw_value),
      engineering_value: JsonDocument.unwrap_value(latest_value_row.engineering_value),
      quality_state: quality_state(latest_value_row.quality_state),
      generation_time: latest_value_row.generation_time,
      receipt_time: latest_value_row.receipt_time,
      provenance: latest_value_row.provenance
    }
  end

  @spec row_attrs(Sample.t()) :: map()
  def row_attrs(%Sample{} = sample) do
    source_identity = SourceFilters.sample_identity(sample)

    %{
      mission_id: sample.mission_id,
      spacecraft_scope_id: sample.spacecraft_id || @mission_scope_key,
      spacecraft_id: sample.spacecraft_id,
      point_id: sample.point_id,
      point_name: sample.point_name,
      realm: source_identity.realm,
      data_source_id: source_identity.data_source_id,
      binding_id: source_identity.binding_id,
      sample_id: sample.sample_id,
      packet_id: sample.packet_id,
      evidence_id: sample.evidence_id,
      packet_definition_id: sample.packet_definition_id,
      packet_definition_version: sample.packet_definition_version,
      raw_value: JsonDocument.wrap_value(sample.raw_value),
      engineering_value: JsonDocument.wrap_value(sample.engineering_value),
      quality_state: Atom.to_string(sample.quality_state),
      generation_time: truncate_datetime(sample.generation_time),
      receipt_time: truncate_datetime(sample.receipt_time),
      provenance: JsonDocument.encode(sample.provenance)
    }
  end

  defp truncate_datetime(nil), do: nil

  defp truncate_datetime(%DateTime{} = datetime) do
    {microsecond, _precision} = datetime.microsecond
    %{datetime | microsecond: {microsecond, 6}}
  end

  defp all_fields do
    [
      :mission_id,
      :spacecraft_scope_id,
      :spacecraft_id,
      :point_id,
      :point_name,
      :realm,
      :data_source_id,
      :binding_id,
      :sample_id,
      :packet_id,
      :evidence_id,
      :packet_definition_id,
      :packet_definition_version,
      :raw_value,
      :engineering_value,
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
