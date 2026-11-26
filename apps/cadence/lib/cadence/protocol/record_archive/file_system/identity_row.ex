defmodule Cadence.Protocol.RecordArchive.FileSystem.IdentityRow do
  @moduledoc false

  use Ecto.Schema

  @primary_key false

  schema "protocol_archive_record_identities" do
    field(:record_kind, :string, primary_key: true)
    field(:record_id, :string, primary_key: true)
    field(:content_sha256, :binary)
    field(:segment_id, :integer)
  end
end
