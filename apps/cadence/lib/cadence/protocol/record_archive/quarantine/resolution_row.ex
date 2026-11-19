defmodule Cadence.Protocol.RecordArchive.Quarantine.ResolutionRow do
  @moduledoc false
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:resolution_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "protocol_archive_quarantine_resolutions" do
    field(:mission_id, :string)
    field(:item_id, :string)
    field(:realized_contact_id, :string)
    field(:spacecraft_id, :string)
    field(:error_code, :string)
    field(:action, :string)
    field(:actor, :map)
    field(:note, :string)
    field(:counts, :map)
    field(:resolved_at, :utc_datetime_usec)

    timestamps()
  end
end
