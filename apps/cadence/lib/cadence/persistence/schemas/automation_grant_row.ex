defmodule Cadence.Persistence.Schemas.AutomationGrantRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.AutomationGrant

  @primary_key {:automation_grant_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "automation_grants" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:service_identity_id, :string)
    field(:fleet_planning_policy_id, :string)
    field(:fleet_planning_policy_version, :integer)
    field(:allowed_actions, {:array, :string}, default: [])
    field(:maximum_horizon_seconds, :integer)
    field(:maximum_contacts, :integer)
    field(:maximum_estimated_cost_micros, :integer)
    field(:currency, :string)
    field(:maximum_execution_concurrency, :integer)
    field(:valid_from, :utc_datetime_usec)
    field(:valid_until, :utc_datetime_usec)
    field(:lifecycle_state, :string)
    field(:approved_by, :string)
    field(:approved_at, :utc_datetime_usec)
    field(:approval_reason, :string)
    field(:content_sha256, :string)
    field(:revoked_by, :string)
    field(:revoked_at, :utc_datetime_usec)
    field(:revocation_reason, :string, default: "")

    timestamps()
  end

  @fields [
    :automation_grant_id,
    :organization_id,
    :mission_id,
    :service_identity_id,
    :fleet_planning_policy_id,
    :fleet_planning_policy_version,
    :allowed_actions,
    :maximum_horizon_seconds,
    :maximum_contacts,
    :maximum_estimated_cost_micros,
    :currency,
    :maximum_execution_concurrency,
    :valid_from,
    :valid_until,
    :lifecycle_state,
    :approved_by,
    :approved_at,
    :approval_reason,
    :content_sha256,
    :revoked_by,
    :revoked_at,
    :revocation_reason
  ]

  @required @fields --
              [
                :maximum_estimated_cost_micros,
                :currency,
                :revoked_by,
                :revoked_at,
                :revocation_reason
              ]

  @spec changeset(AutomationGrant.t()) :: Ecto.Changeset.t()
  def changeset(%AutomationGrant{} = grant) do
    %__MODULE__{}
    |> cast(domain_attrs(grant), @fields)
    |> validate_required(@required)
    |> common_validations()
    |> unique_constraint(:automation_grant_id)
    |> unique_constraint(
      [:organization_id, :mission_id, :service_identity_id],
      name: :automation_grants_one_active_per_service_idx
    )
  end

  @spec revocation_changeset(struct(), map()) :: Ecto.Changeset.t()
  def revocation_changeset(%__MODULE__{} = row, attrs) do
    row
    |> cast(attrs, [:lifecycle_state, :revoked_by, :revoked_at, :revocation_reason])
    |> validate_required([:lifecycle_state, :revoked_by, :revoked_at, :revocation_reason])
    |> common_validations()
  end

  @spec to_domain(struct()) :: AutomationGrant.t()
  def to_domain(%__MODULE__{} = row) do
    AutomationGrant.new(%{
      automation_grant_id: row.automation_grant_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      service_identity_id: row.service_identity_id,
      fleet_planning_policy_id: row.fleet_planning_policy_id,
      fleet_planning_policy_version: row.fleet_planning_policy_version,
      allowed_actions: row.allowed_actions,
      maximum_horizon_seconds: row.maximum_horizon_seconds,
      maximum_contacts: row.maximum_contacts,
      maximum_estimated_cost_micros: row.maximum_estimated_cost_micros,
      currency: row.currency,
      maximum_execution_concurrency: row.maximum_execution_concurrency,
      valid_from: row.valid_from,
      valid_until: row.valid_until,
      lifecycle_state: row.lifecycle_state,
      approved_by: row.approved_by,
      approved_at: row.approved_at,
      approval_reason: row.approval_reason,
      content_sha256: row.content_sha256,
      revoked_by: row.revoked_by,
      revoked_at: row.revoked_at,
      revocation_reason: row.revocation_reason,
      inserted_at: row.inserted_at,
      updated_at: row.updated_at
    })
  end

  defp common_validations(changeset) do
    changeset
    |> validate_number(:fleet_planning_policy_version, greater_than: 0)
    |> validate_number(:maximum_horizon_seconds, greater_than: 0)
    |> validate_number(:maximum_contacts, greater_than: 0)
    |> validate_optional_non_negative(:maximum_estimated_cost_micros)
    |> validate_number(:maximum_execution_concurrency, greater_than: 0)
    |> validate_inclusion(:lifecycle_state, ~w(active revoked))
    |> validate_subset(:allowed_actions, ~w(plan repair submit approve execute))
    |> validate_length(:allowed_actions, min: 1)
    |> validate_validity()
    |> validate_cost_currency()
  end

  defp validate_validity(changeset) do
    case {get_field(changeset, :valid_from), get_field(changeset, :valid_until)} do
      {%DateTime{} = from, %DateTime{} = until} ->
        if DateTime.before?(from, until),
          do: changeset,
          else: add_error(changeset, :valid_until, "must be after valid_from")

      _values ->
        changeset
    end
  end

  defp validate_cost_currency(changeset) do
    if is_nil(get_field(changeset, :maximum_estimated_cost_micros)) ==
         is_nil(get_field(changeset, :currency)),
       do: changeset,
       else: add_error(changeset, :currency, "must be set with cost")
  end

  defp validate_optional_non_negative(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      _value -> validate_number(changeset, field, greater_than_or_equal_to: 0)
    end
  end

  defp domain_attrs(grant) do
    %{
      automation_grant_id: grant.automation_grant_id,
      organization_id: grant.organization_id,
      mission_id: grant.mission_id,
      service_identity_id: grant.service_identity_id,
      fleet_planning_policy_id: grant.fleet_planning_policy_id,
      fleet_planning_policy_version: grant.fleet_planning_policy_version,
      allowed_actions: Enum.map(grant.allowed_actions, &Atom.to_string/1),
      maximum_horizon_seconds: grant.maximum_horizon_seconds,
      maximum_contacts: grant.maximum_contacts,
      maximum_estimated_cost_micros: grant.maximum_estimated_cost_micros,
      currency: grant.currency,
      maximum_execution_concurrency: grant.maximum_execution_concurrency,
      valid_from: grant.valid_from,
      valid_until: grant.valid_until,
      lifecycle_state: Atom.to_string(grant.lifecycle_state),
      approved_by: grant.approved_by,
      approved_at: grant.approved_at,
      approval_reason: grant.approval_reason,
      content_sha256: grant.content_sha256,
      revoked_by: grant.revoked_by,
      revoked_at: grant.revoked_at,
      revocation_reason: grant.revocation_reason
    }
  end
end
