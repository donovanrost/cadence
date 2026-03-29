defmodule Cadence.Persistence.Schemas.ProtocolAnomalyRow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Protocol.ProtocolAnomaly

  @primary_key {:anomaly_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "protocol_anomalies" do
    field(:evidence_id, :string)
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:source_endpoint_ref, :string)
    field(:spacecraft_id, :string)
    field(:protocol_family, :string)
    field(:direction, :string)
    field(:anomaly_kind, :string)
    field(:scid, :integer)
    field(:vcid, :integer)
    field(:map_id, :integer)
    field(:frame_seq, :integer)
    field(:raw_frame_offset_bytes, :integer)
    field(:raw_frame_length_bytes, :integer)
    field(:recorded_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :anomaly_id,
    :evidence_id,
    :mission_id,
    :protocol_family,
    :direction,
    :anomaly_kind,
    :recorded_at
  ]

  @spec changeset(ProtocolAnomaly.t()) :: Ecto.Changeset.t()
  def changeset(%ProtocolAnomaly{} = anomaly) do
    %__MODULE__{}
    |> cast(row_attrs(anomaly), all_fields())
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec row_attrs(ProtocolAnomaly.t(), keyword()) :: map()
  def row_attrs(%ProtocolAnomaly{} = anomaly, opts \\ []) do
    inserted_at = Keyword.get(opts, :inserted_at)
    organization_id = Keyword.get(opts, :organization_id)

    %{
      anomaly_id: anomaly.anomaly_id,
      evidence_id: anomaly.evidence_id,
      mission_id: anomaly.mission_id,
      organization_id: organization_id,
      source_endpoint_ref: anomaly.source_endpoint_ref,
      spacecraft_id: anomaly.spacecraft_id,
      protocol_family: Atom.to_string(anomaly.protocol_family),
      direction: Atom.to_string(anomaly.direction),
      anomaly_kind: Atom.to_string(anomaly.anomaly_kind),
      scid: anomaly.scid,
      vcid: anomaly.vcid,
      map_id: anomaly.map_id,
      frame_seq: anomaly.frame_seq,
      raw_frame_offset_bytes: anomaly.raw_frame_offset_bytes,
      raw_frame_length_bytes: anomaly.raw_frame_length_bytes,
      recorded_at: anomaly.recorded_at,
      metadata: JsonDocument.encode(anomaly.metadata)
    }
    |> maybe_put_inserted_at(inserted_at)
  end

  defp all_fields do
    [
      :anomaly_id,
      :evidence_id,
      :mission_id,
      :source_endpoint_ref,
      :spacecraft_id,
      :protocol_family,
      :direction,
      :anomaly_kind,
      :scid,
      :vcid,
      :map_id,
      :frame_seq,
      :raw_frame_offset_bytes,
      :raw_frame_length_bytes,
      :recorded_at,
      :metadata
    ]
  end

  defp maybe_put_inserted_at(attrs, nil), do: attrs
  defp maybe_put_inserted_at(attrs, inserted_at), do: Map.put(attrs, :inserted_at, inserted_at)
end
