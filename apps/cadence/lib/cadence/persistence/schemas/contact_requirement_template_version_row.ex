defmodule Cadence.Persistence.Schemas.ContactRequirementTemplateVersionRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.ContactRequirementTemplateVersion
  alias Cadence.Persistence.JsonDocument

  @primary_key {:contact_requirement_template_version_id, :string, autogenerate: false}

  schema "contact_requirement_template_versions" do
    field(:contact_requirement_template_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:version, :integer)
    field(:spacecraft_id, :string)
    field(:schedule_document, :map)
    field(:requirement_document, :map)
    field(:catch_up_policy_document, :map)
    field(:content_sha256, :string)
    field(:created_by, :string)
    field(:created_at, :utc_datetime_usec)
  end

  @fields [
    :contact_requirement_template_version_id,
    :contact_requirement_template_id,
    :organization_id,
    :mission_id,
    :version,
    :spacecraft_id,
    :schedule_document,
    :requirement_document,
    :catch_up_policy_document,
    :content_sha256,
    :created_by,
    :created_at
  ]

  @spec changeset(ContactRequirementTemplateVersion.t()) :: Ecto.Changeset.t()
  def changeset(%ContactRequirementTemplateVersion{} = version) do
    %__MODULE__{}
    |> cast(domain_attrs(version), @fields)
    |> validate_required(@fields)
    |> validate_number(:version, greater_than: 0)
    |> validate_format(:content_sha256, ~r/\A[0-9a-f]{64}\z/)
    |> unique_constraint(
      [:organization_id, :mission_id, :contact_requirement_template_id, :version],
      name: :contact_requirement_template_versions_scope_uniq
    )
    |> foreign_key_constraint(:spacecraft_id,
      name: :contact_requirement_template_versions_spacecraft_fk
    )
  end

  @spec to_domain(struct()) :: ContactRequirementTemplateVersion.t()
  def to_domain(%__MODULE__{} = row) do
    ContactRequirementTemplateVersion.new(%{
      contact_requirement_template_version_id: row.contact_requirement_template_version_id,
      contact_requirement_template_id: row.contact_requirement_template_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      version: row.version,
      spacecraft_id: row.spacecraft_id,
      schedule_document: JsonDocument.unwrap_value(row.schedule_document),
      requirement_document: JsonDocument.unwrap_value(row.requirement_document),
      catch_up_policy_document: JsonDocument.unwrap_value(row.catch_up_policy_document),
      content_sha256: row.content_sha256,
      created_by: row.created_by,
      created_at: row.created_at
    })
  end

  defp domain_attrs(version) do
    %{
      contact_requirement_template_version_id: version.contact_requirement_template_version_id,
      contact_requirement_template_id: version.contact_requirement_template_id,
      organization_id: version.organization_id,
      mission_id: version.mission_id,
      version: version.version,
      spacecraft_id: version.spacecraft_id,
      schedule_document: JsonDocument.wrap_value(version.schedule_document),
      requirement_document: JsonDocument.wrap_value(version.requirement_document),
      catch_up_policy_document: JsonDocument.wrap_value(version.catch_up_policy_document),
      content_sha256: version.content_sha256,
      created_by: version.created_by,
      created_at: version.created_at
    }
  end
end
