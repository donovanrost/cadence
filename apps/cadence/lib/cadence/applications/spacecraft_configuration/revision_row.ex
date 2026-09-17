defmodule Cadence.Applications.SpacecraftConfiguration.RevisionRow do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:configuration_revision_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "spacecraft_configuration_revisions" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:spacecraft_id, :string)
    field(:version, :integer)
    field(:catalog_revision_id, :string)
    field(:document, :map)
    field(:content_sha256, :string)
    field(:application_basis, :string)
    field(:created_by, :string)
    timestamps()
  end

  def changeset(attrs) do
    # All identity and actor fields are constructed by the authorized service.
    %__MODULE__{}
    |> change(attrs)
    |> validate_required([
      :configuration_revision_id,
      :organization_id,
      :mission_id,
      :spacecraft_id,
      :version,
      :document,
      :content_sha256,
      :application_basis,
      :created_by
    ])
    |> validate_number(:version, greater_than: 0)
    |> unique_constraint([:organization_id, :mission_id, :spacecraft_id, :version],
      name: :spacecraft_configuration_revisions_version_idx
    )
  end
end
