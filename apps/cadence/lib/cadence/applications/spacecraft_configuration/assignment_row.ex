defmodule Cadence.Applications.SpacecraftConfiguration.AssignmentRow do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:configuration_revision_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "spacecraft_configuration_assignments" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:spacecraft_id, :string)
    field(:version, :integer)
    field(:artifact_sha256, :string)
    field(:source_endpoint_id, :string)
    field(:application_basis, :string)
    field(:created_by, :string)
    field(:change_set_id, :string)
    field(:change_set_revision, :integer)
    field(:catalog_revision_id, :string, virtual: true)
    field(:composition_id, :string, virtual: true)
    field(:effective_revision_id, :string, virtual: true)
    field(:document, :map, virtual: true)
    field(:content_sha256, :string, virtual: true)
    timestamps()
  end
end
