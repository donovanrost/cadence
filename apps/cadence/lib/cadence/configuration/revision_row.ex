defmodule Cadence.Configuration.RevisionRow do
  @moduledoc "One applied, immutable mission configuration revision (`rN`)."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @kinds ~w(baseline change_set rollback legacy_activation)

  @primary_key {:revision_id, :string, autogenerate: false}
  schema "mission_config_revisions" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:revision_number, :integer)
    field(:kind, :string)
    field(:change_set_id, :string)
    field(:rolls_back_to, :integer)
    field(:applied_by, :map)
    field(:submitted_by, :map)
    field(:applied_at, :utc_datetime_usec)
    field(:reason, :string)
    field(:approvals, {:array, :map}, default: [])
    field(:summary, :string)
    field(:entry_count, :integer, default: 0)
    field(:activation_id, :string)
    field(:generation, :integer)
    field(:content_sha256, :string)
  end

  def kinds, do: @kinds
end
