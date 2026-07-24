defmodule Cadence.Telemetry.SampleRecords.TelemetrySampleRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Telemetry.Sample

  @primary_key {:sample_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "telemetry_samples" do
    field(:packet_id, :string)
    field(:evidence_id, :string)
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:spacecraft_id, :string)
    field(:point_id, :string)
    field(:point_name, :string)
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
    :sample_id,
    :packet_id,
    :evidence_id,
    :mission_id,
    :point_id,
    :point_name,
    :packet_definition_id,
    :packet_definition_version,
    :raw_value,
    :engineering_value,
    :quality_state,
    :receipt_time
  ]

  @spec changeset(Sample.t()) :: Ecto.Changeset.t()
  def changeset(%Sample{} = sample) do
    %__MODULE__{}
    |> cast(row_attrs(sample), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:packet_id)
    |> foreign_key_constraint(:evidence_id)
  end

  @spec insert_attrs(Sample.t(), DateTime.t()) :: map()
  def insert_attrs(%Sample{} = sample, %DateTime{} = inserted_at) do
    sample
    |> row_attrs()
    |> Map.put(:inserted_at, inserted_at)
  end

  @spec to_domain(struct()) :: Sample.t()
  def to_domain(%__MODULE__{} = sample_row) do
    %Sample{
      sample_id: sample_row.sample_id,
      packet_id: sample_row.packet_id,
      evidence_id: sample_row.evidence_id,
      mission_id: sample_row.mission_id,
      spacecraft_id: sample_row.spacecraft_id,
      point_id: sample_row.point_id,
      point_name: sample_row.point_name,
      packet_definition_id: sample_row.packet_definition_id,
      packet_definition_version: sample_row.packet_definition_version,
      raw_value: JsonDocument.unwrap_value(sample_row.raw_value),
      engineering_value: JsonDocument.unwrap_value(sample_row.engineering_value),
      quality_state: quality_state(sample_row.quality_state),
      generation_time: sample_row.generation_time,
      receipt_time: sample_row.receipt_time,
      provenance: sample_row.provenance
    }
  end

  @spec row_attrs(Sample.t()) :: map()
  def row_attrs(%Sample{} = sample) do
    %{
      sample_id: sample.sample_id,
      packet_id: sample.packet_id,
      evidence_id: sample.evidence_id,
      mission_id: sample.mission_id,
      spacecraft_id: sample.spacecraft_id,
      point_id: sample.point_id,
      point_name: sample.point_name,
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
      :sample_id,
      :packet_id,
      :evidence_id,
      :mission_id,
      :spacecraft_id,
      :point_id,
      :point_name,
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
