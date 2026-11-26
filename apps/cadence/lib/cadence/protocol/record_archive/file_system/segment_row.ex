defmodule Cadence.Protocol.RecordArchive.FileSystem.SegmentRow do
  @moduledoc false

  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "protocol_archive_segments" do
    field(:archive_backend, :string)
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:object_key, :string)
    field(:packet_count, :integer)
    field(:frame_count, :integer)
    field(:first_receipt_time, :utc_datetime_usec)
    field(:last_receipt_time, :utc_datetime_usec)
    field(:spacecraft_ids, {:array, :string}, default: [])
    field(:realized_contact_ids, {:array, :string}, default: [])
    field(:source_refs, {:array, :string}, default: [])
    field(:evidence_ids, {:array, :string}, default: [])
    field(:frames_by_contact, :map, default: %{})

    timestamps()
  end
end
