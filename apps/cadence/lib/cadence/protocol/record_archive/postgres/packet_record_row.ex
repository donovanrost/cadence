defmodule Cadence.Protocol.RecordArchive.Postgres.PacketRecordRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope
  alias Cadence.Protocol.PacketRecord

  @primary_key {:packet_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "protocol_packet_records" do
    field(:evidence_id, :string)
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:source_endpoint_ref, :string)
    field(:spacecraft_id, :string)
    field(:protocol_family, :string)
    field(:packet_kind, :string)
    field(:apid, :integer)
    field(:sequence_flags, :integer)
    field(:sequence_count, :integer)
    field(:secondary_header, :boolean)
    field(:packet_data, :binary)
    field(:source_time, :utc_datetime_usec)
    field(:receipt_time, :utc_datetime_usec)
    field(:provenance, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :packet_id,
    :evidence_id,
    :mission_id,
    :protocol_family,
    :packet_kind,
    :apid,
    :sequence_flags,
    :sequence_count,
    :secondary_header,
    :packet_data,
    :receipt_time
  ]

  @spec changeset(PacketRecord.t()) :: Ecto.Changeset.t()
  def changeset(%PacketRecord{} = packet_record) do
    %__MODULE__{}
    |> cast(domain_attrs(packet_record), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:evidence_id)
  end

  defp domain_attrs(%PacketRecord{} = packet_record) do
    %{
      packet_id: packet_record.packet_id,
      evidence_id: packet_record.evidence_id,
      mission_id: packet_record.mission_id,
      source_endpoint_ref: packet_record.source_endpoint_ref,
      spacecraft_id: packet_record.spacecraft_id,
      protocol_family: Atom.to_string(packet_record.protocol_family),
      packet_kind: Atom.to_string(packet_record.packet_kind),
      apid: packet_record.apid,
      sequence_flags: packet_record.sequence_flags,
      sequence_count: packet_record.sequence_count,
      secondary_header: packet_record.secondary_header?,
      packet_data: packet_record.packet_data,
      source_time: packet_record.source_time,
      receipt_time: packet_record.receipt_time,
      provenance: JsonDocument.encode(packet_record.provenance)
    }
  end

  defp all_fields do
    [
      :packet_id,
      :evidence_id,
      :mission_id,
      :source_endpoint_ref,
      :spacecraft_id,
      :protocol_family,
      :packet_kind,
      :apid,
      :sequence_flags,
      :sequence_count,
      :secondary_header,
      :packet_data,
      :source_time,
      :receipt_time,
      :provenance
    ]
  end
end
