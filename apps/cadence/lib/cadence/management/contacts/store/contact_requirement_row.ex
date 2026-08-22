defmodule Cadence.Management.Contacts.Store.ContactRequirementRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.ContactRequirement

  @primary_key {:contact_requirement_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "contact_requirements" do
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

  @spec changeset(ContactRequirement.t()) :: Ecto.Changeset.t()
  def changeset(%ContactRequirement{} = requirement) do
    %__MODULE__{}
    |> cast(domain_attrs(requirement), fields())
    |> validate_required(fields())
    |> validate_number(:current_version, greater_than: 0)
    |> validate_inclusion(:lifecycle_state, ~w(active closed canceled))
    |> unique_constraint(:contact_requirement_id)
    |> unique_constraint(
      [:organization_id, :mission_id, :contact_requirement_id],
      name: :contact_requirements_scope_uniq
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
    |> validate_inclusion(:lifecycle_state, ~w(active closed canceled))
  end

  @spec to_domain(struct()) :: ContactRequirement.t()
  def to_domain(%__MODULE__{} = row) do
    ContactRequirement.new(%{
      contact_requirement_id: row.contact_requirement_id,
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

  defp domain_attrs(%ContactRequirement{} = requirement) do
    %{
      contact_requirement_id: requirement.contact_requirement_id,
      organization_id: requirement.organization_id,
      mission_id: requirement.mission_id,
      current_version: requirement.current_version,
      lifecycle_state: Atom.to_string(requirement.lifecycle_state),
      created_by: requirement.created_by,
      lifecycle_changed_by: requirement.lifecycle_changed_by,
      lifecycle_changed_at: requirement.lifecycle_changed_at,
      lifecycle_reason: requirement.lifecycle_reason
    }
  end

  defp fields do
    [
      :contact_requirement_id,
      :organization_id,
      :mission_id,
      :current_version,
      :lifecycle_state,
      :created_by,
      :lifecycle_changed_by,
      :lifecycle_changed_at,
      :lifecycle_reason
    ]
  end
end
