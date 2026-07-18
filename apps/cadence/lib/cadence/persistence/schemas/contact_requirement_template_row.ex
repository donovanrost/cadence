defmodule Cadence.Persistence.Schemas.ContactRequirementTemplateRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.ContactRequirementTemplate

  @primary_key {:contact_requirement_template_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "contact_requirement_templates" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:current_version, :integer)
    field(:lifecycle_state, :string)
    field(:created_by, :string)
    field(:lifecycle_changed_by, :string)
    field(:lifecycle_changed_at, :utc_datetime_usec)
    field(:lifecycle_reason, :string)

    timestamps()
  end

  @fields [
    :contact_requirement_template_id,
    :organization_id,
    :mission_id,
    :current_version,
    :lifecycle_state,
    :created_by,
    :lifecycle_changed_by,
    :lifecycle_changed_at,
    :lifecycle_reason
  ]

  @spec changeset(ContactRequirementTemplate.t()) :: Ecto.Changeset.t()
  def changeset(%ContactRequirementTemplate{} = template) do
    %__MODULE__{}
    |> cast(domain_attrs(template), @fields)
    |> validate_required(@fields)
    |> validate_number(:current_version, greater_than: 0)
    |> validate_inclusion(:lifecycle_state, ~w(active paused closed))
    |> unique_constraint(:contact_requirement_template_id)
    |> unique_constraint(
      [:organization_id, :mission_id, :contact_requirement_template_id],
      name: :contact_requirement_templates_scope_uniq
    )
  end

  @spec projection_changeset(struct(), map()) :: Ecto.Changeset.t()
  def projection_changeset(%__MODULE__{} = row, attrs) when is_map(attrs) do
    row
    |> cast(attrs, [
      :current_version,
      :lifecycle_state,
      :lifecycle_changed_by,
      :lifecycle_changed_at,
      :lifecycle_reason
    ])
    |> validate_required([
      :current_version,
      :lifecycle_state,
      :lifecycle_changed_by,
      :lifecycle_changed_at,
      :lifecycle_reason
    ])
    |> validate_number(:current_version, greater_than: 0)
    |> validate_inclusion(:lifecycle_state, ~w(active paused closed))
  end

  @spec to_domain(struct()) :: ContactRequirementTemplate.t()
  def to_domain(%__MODULE__{} = row) do
    ContactRequirementTemplate.new(%{
      contact_requirement_template_id: row.contact_requirement_template_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      current_version: row.current_version,
      lifecycle_state: row.lifecycle_state,
      created_by: row.created_by,
      lifecycle_changed_by: row.lifecycle_changed_by,
      lifecycle_changed_at: row.lifecycle_changed_at,
      lifecycle_reason: row.lifecycle_reason,
      inserted_at: row.inserted_at,
      updated_at: row.updated_at
    })
  end

  defp domain_attrs(template) do
    %{
      contact_requirement_template_id: template.contact_requirement_template_id,
      organization_id: template.organization_id,
      mission_id: template.mission_id,
      current_version: template.current_version,
      lifecycle_state: Atom.to_string(template.lifecycle_state),
      created_by: template.created_by,
      lifecycle_changed_by: template.lifecycle_changed_by,
      lifecycle_changed_at: template.lifecycle_changed_at,
      lifecycle_reason: template.lifecycle_reason
    }
  end
end
