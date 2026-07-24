defmodule Cadence.Protocol.RecordArchive.Postgres.TransferFrameRecordRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Protocol.TransferFrameRecord

  @primary_key {:frame_record_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "protocol_transfer_frame_records" do
    field(:evidence_id, :string)
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:source_endpoint_ref, :string)
    field(:spacecraft_id, :string)
    field(:protocol_family, :string)
    field(:direction, :string)
    field(:scid, :integer)
    field(:vcid, :integer)
    field(:map_id, :integer)
    field(:frame_seq, :integer)
    field(:raw_frame_offset_bytes, :integer)
    field(:raw_frame_length_bytes, :integer)
    field(:payload_length_bytes, :integer)
    field(:first_header_pointer, :integer)
    field(:quality, :string)
    field(:source_time, :utc_datetime_usec)
    field(:receipt_time, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :frame_record_id,
    :evidence_id,
    :mission_id,
    :protocol_family,
    :direction,
    :scid,
    :vcid,
    :frame_seq,
    :raw_frame_offset_bytes,
    :raw_frame_length_bytes,
    :payload_length_bytes,
    :receipt_time
  ]

  @spec changeset(TransferFrameRecord.t()) :: Ecto.Changeset.t()
  def changeset(%TransferFrameRecord{} = frame_record) do
    %__MODULE__{}
    |> cast(domain_attrs(frame_record), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:evidence_id)
  end

  defp domain_attrs(%TransferFrameRecord{} = frame_record) do
    %{
      frame_record_id: frame_record.frame_record_id,
      evidence_id: frame_record.evidence_id,
      mission_id: frame_record.mission_id,
      source_endpoint_ref: frame_record.source_endpoint_ref,
      spacecraft_id: frame_record.spacecraft_id,
      protocol_family: Atom.to_string(frame_record.protocol_family),
      direction: Atom.to_string(frame_record.direction),
      scid: frame_record.scid,
      vcid: frame_record.vcid,
      map_id: frame_record.map_id,
      frame_seq: frame_record.frame_seq,
      raw_frame_offset_bytes: frame_record.raw_frame_offset_bytes,
      raw_frame_length_bytes: frame_record.raw_frame_length_bytes,
      payload_length_bytes: frame_record.payload_length_bytes,
      first_header_pointer: frame_record.first_header_pointer,
      quality: quality(frame_record.quality),
      source_time: frame_record.source_time,
      receipt_time: frame_record.receipt_time,
      metadata: JsonDocument.encode(frame_record.metadata)
    }
  end

  defp quality(nil), do: nil
  defp quality(value) when is_atom(value), do: Atom.to_string(value)

  defp all_fields do
    [
      :frame_record_id,
      :evidence_id,
      :mission_id,
      :source_endpoint_ref,
      :spacecraft_id,
      :protocol_family,
      :direction,
      :scid,
      :vcid,
      :map_id,
      :frame_seq,
      :raw_frame_offset_bytes,
      :raw_frame_length_bytes,
      :payload_length_bytes,
      :first_header_pointer,
      :quality,
      :source_time,
      :receipt_time,
      :metadata
    ]
  end
end
