defmodule Cadence.Management.Contacts.Store.FleetPlanningPolicyRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.FleetPlanningPolicy

  @primary_key {:fleet_planning_policy_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "fleet_planning_policies" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:current_version, :integer)
    field(:active_version, :integer)
    field(:lifecycle_state, :string)
    field(:created_by, :string)
    field(:lifecycle_changed_by, :string)
    field(:lifecycle_changed_at, :utc_datetime_usec)
    field(:lifecycle_reason, :string)

    timestamps()
  end

  @fields [
    :fleet_planning_policy_id,
    :organization_id,
    :mission_id,
    :current_version,
    :active_version,
    :lifecycle_state,
    :created_by,
    :lifecycle_changed_by,
    :lifecycle_changed_at,
    :lifecycle_reason
  ]

  @required_fields @fields -- [:active_version]

  @spec changeset(FleetPlanningPolicy.t()) :: Ecto.Changeset.t()
  def changeset(%FleetPlanningPolicy{} = policy) do
    %__MODULE__{}
    |> cast(domain_attrs(policy), @fields)
    |> validate_required(@required_fields)
    |> validate_number(:current_version, greater_than: 0)
    |> validate_optional_positive(:active_version)
    |> validate_inclusion(:lifecycle_state, ~w(draft active retired))
    |> unique_constraint([:organization_id, :mission_id],
      name: :fleet_planning_policies_mission_uniq
    )
  end

  @spec projection_changeset(struct(), map()) :: Ecto.Changeset.t()
  def projection_changeset(%__MODULE__{} = row, attrs) when is_map(attrs) do
    row
    |> cast(attrs, [
      :current_version,
      :active_version,
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
    |> validate_optional_positive(:active_version)
    |> validate_inclusion(:lifecycle_state, ~w(draft active retired))
  end

  @spec to_domain(struct()) :: FleetPlanningPolicy.t()
  def to_domain(%__MODULE__{} = row) do
    FleetPlanningPolicy.new(%{
      fleet_planning_policy_id: row.fleet_planning_policy_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      current_version: row.current_version,
      active_version: row.active_version,
      lifecycle_state: row.lifecycle_state,
      created_by: row.created_by,
      lifecycle_changed_by: row.lifecycle_changed_by,
      lifecycle_changed_at: row.lifecycle_changed_at,
      lifecycle_reason: row.lifecycle_reason,
      inserted_at: row.inserted_at,
      updated_at: row.updated_at
    })
  end

  defp domain_attrs(policy) do
    %{
      fleet_planning_policy_id: policy.fleet_planning_policy_id,
      organization_id: policy.organization_id,
      mission_id: policy.mission_id,
      current_version: policy.current_version,
      active_version: policy.active_version,
      lifecycle_state: Atom.to_string(policy.lifecycle_state),
      created_by: policy.created_by,
      lifecycle_changed_by: policy.lifecycle_changed_by,
      lifecycle_changed_at: policy.lifecycle_changed_at,
      lifecycle_reason: policy.lifecycle_reason
    }
  end

  defp validate_optional_positive(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      _value -> validate_number(changeset, field, greater_than: 0)
    end
  end
end
