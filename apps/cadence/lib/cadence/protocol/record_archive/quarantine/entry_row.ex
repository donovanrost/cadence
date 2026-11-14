defmodule Cadence.Protocol.RecordArchive.Quarantine.EntryRow do
  @moduledoc false
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:quarantine_entry_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "protocol_archive_quarantine" do
    field(:mission_id, :string)
    field(:organization_id, :string)
    field(:realized_contact_id, :string)
    field(:spacecraft_id, :string)
    field(:record_kind, :string)
    field(:record_id, :string)
    field(:error_code, :string)
    field(:error, :string)
    field(:entry, :binary)
    field(:receipt_time, :utc_datetime_usec)
    field(:first_seen_at, :utc_datetime_usec)
    field(:last_seen_at, :utc_datetime_usec)
    field(:last_retry, :map)

    timestamps()
  end
end
