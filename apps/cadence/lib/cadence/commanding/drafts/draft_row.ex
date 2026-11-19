defmodule Cadence.Commanding.Drafts.DraftRow do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "command_drafts" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:user_id, :string)
    field(:revision, :integer)
    field(:document, :map)
    field(:catalog_revision_id, :string)
    field(:saved_at, :utc_datetime_usec)
  end
end
