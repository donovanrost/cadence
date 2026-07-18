defmodule Cadence.Persistence.Schemas.ContactPlanRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.ContactPlan

  @primary_key {:contact_plan_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "contact_plans" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:current_version, :integer)
    field(:lifecycle_state, :string)
    field(:created_by, :string)
    field(:lifecycle_changed_by, :string)
    field(:lifecycle_changed_at, :utc_datetime_usec)
    field(:lifecycle_reason, :string)
    field(:approved_version, :integer)
    field(:approved_at, :utc_datetime_usec)
    field(:approved_by, :string)

    timestamps()
  end

  @required_fields [
    :contact_plan_id,
    :organization_id,
    :mission_id,
    :current_version,
    :lifecycle_state,
    :created_by,
    :lifecycle_changed_by,
    :lifecycle_changed_at,
    :lifecycle_reason
  ]

  @projection_fields [
    :current_version,
    :lifecycle_state,
    :lifecycle_changed_by,
    :lifecycle_changed_at,
    :lifecycle_reason,
    :approved_version,
    :approved_at,
    :approved_by
  ]

  @spec changeset(ContactPlan.t()) :: Ecto.Changeset.t()
  def changeset(%ContactPlan{} = plan) do
    %__MODULE__{}
    |> cast(domain_attrs(plan), @required_fields ++ approval_fields())
    |> validate_plan()
    |> unique_constraint(:contact_plan_id)
    |> unique_constraint(
      [:organization_id, :mission_id, :contact_plan_id],
      name: :contact_plans_scope_uniq
    )
  end

  @spec projection_changeset(struct(), map()) :: Ecto.Changeset.t()
  def projection_changeset(%__MODULE__{} = row, attrs) when is_map(attrs) do
    row
    |> cast(attrs, @projection_fields)
    |> validate_plan()
  end

  @spec to_domain(struct()) :: ContactPlan.t()
  def to_domain(%__MODULE__{} = row) do
    ContactPlan.new(%{
      contact_plan_id: row.contact_plan_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      current_version: row.current_version,
      lifecycle_state: row.lifecycle_state,
      created_by: row.created_by,
      lifecycle_changed_by: row.lifecycle_changed_by,
      lifecycle_changed_at: row.lifecycle_changed_at,
      lifecycle_reason: row.lifecycle_reason,
      approved_version: row.approved_version,
      approved_at: row.approved_at,
      approved_by: row.approved_by,
      inserted_at: row.inserted_at,
      updated_at: row.updated_at
    })
  end

  defp validate_plan(changeset) do
    changeset
    |> validate_required(@required_fields)
    |> validate_number(:current_version, greater_than: 0)
    |> validate_optional_positive(:approved_version)
    |> validate_inclusion(:lifecycle_state, Enum.map(ContactPlan.states(), &Atom.to_string/1))
    |> validate_approval_shape()
  end

  defp validate_optional_positive(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      _value -> validate_number(changeset, field, greater_than: 0)
    end
  end

  defp validate_approval_shape(changeset) do
    values = Enum.map(approval_fields(), &get_field(changeset, &1))

    if Enum.all?(values, &is_nil/1) or Enum.all?(values, &(not is_nil(&1))),
      do: changeset,
      else: add_error(changeset, :approved_version, "approval fields must be complete")
  end

  defp domain_attrs(plan) do
    %{
      contact_plan_id: plan.contact_plan_id,
      organization_id: plan.organization_id,
      mission_id: plan.mission_id,
      current_version: plan.current_version,
      lifecycle_state: Atom.to_string(plan.lifecycle_state),
      created_by: plan.created_by,
      lifecycle_changed_by: plan.lifecycle_changed_by,
      lifecycle_changed_at: plan.lifecycle_changed_at,
      lifecycle_reason: plan.lifecycle_reason,
      approved_version: plan.approved_version,
      approved_at: plan.approved_at,
      approved_by: plan.approved_by
    }
  end

  defp approval_fields, do: [:approved_version, :approved_at, :approved_by]
end
