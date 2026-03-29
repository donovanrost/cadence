defmodule Cadence.Persistence.Schemas.ProtocolArchiveRecordEntryRow do
  use Ecto.Schema

  @primary_key {:entry_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "protocol_archive_record_entries" do
    field(:record_kind, :string)
    field(:record_id, :string)
    field(:segment_id, :string)
    field(:object_key, :string)
    field(:archive_backend, :string)
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:evidence_id, :string)
    field(:source_endpoint_ref, :string)
    field(:spacecraft_id, :string)
    field(:protocol_family, :string)
    field(:direction, :string)
    field(:source_time, :utc_datetime_usec)
    field(:receipt_time, :utc_datetime_usec)
    field(:source_ref, :string)
    field(:realized_contact_id, :string)
    field(:path_id, :string)
    field(:provider_binding_id, :string)
    field(:apid, :integer)
    field(:packet_kind, :string)
    field(:scid, :integer)
    field(:vcid, :integer)
    field(:map_id, :integer)
    field(:frame_seq, :integer)
    field(:metadata, :map, default: %{})

    timestamps()
  end
end
