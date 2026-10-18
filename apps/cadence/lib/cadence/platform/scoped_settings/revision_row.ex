defmodule Cadence.Platform.ScopedSettings.RevisionRow do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:revision_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "scoped_settings_revisions" do
    field(:organization_id, :string)
    field(:scope_key, :string)
    field(:section_id, :string)
    field(:version, :integer)
    field(:document, :map)
    field(:actor_id, :string)
    field(:actor_name, :string)
    timestamps()
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> change(attrs)
    |> validate_required([
      :revision_id,
      :organization_id,
      :scope_key,
      :section_id,
      :version,
      :document,
      :actor_id,
      :actor_name
    ])
    |> unique_constraint([:organization_id, :scope_key, :section_id, :version],
      name: :scoped_settings_revisions_version_idx
    )
  end
end
