defmodule Cadence.Management.Contacts.Store.AutomationGrantRow do
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
    field(:validity_seconds, :integer)
    field(:proposed_by, :string)
    field(:proposed_at, :utc_datetime_usec)
    field(:proposal_expires_at, :utc_datetime_usec)
    field(:approval_policy, :map)
    field(:rejected_by, :string)
    field(:rejected_at, :utc_datetime_usec)
    field(:rejection_reason, :string)
    field(:withdrawn_by, :string)
    field(:withdrawn_at, :utc_datetime_usec)
    field(:replaces_grant_id, :string)
    field(:legacy_issue, :boolean, default: false)
    # #499: a suspension (who, when, the settings revision) and the resume.
    field(:suspended_by, :string)
    field(:suspended_at, :utc_datetime_usec)
    field(:suspension_revision, :string)
    field(:suspension_level, :string)
    field(:resumed_by, :string)
    field(:resumed_at, :utc_datetime_usec)

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
    :revocation_reason,
    :validity_seconds,
    :proposed_by,
    :proposed_at,
    :proposal_expires_at,
    :approval_policy,
    :rejected_by,
    :rejected_at,
    :rejection_reason,
    :withdrawn_by,
    :withdrawn_at,
    :replaces_grant_id,
    :suspended_by,
    :suspended_at,
    :suspension_revision,
    :suspension_level,
    :resumed_by,
    :resumed_at
  ]

  # Always present; the rest depends on the state (AutomationGrant's shape checks, #283).
  @required [
    :automation_grant_id,
    :organization_id,
    :mission_id,
    :service_identity_id,
    :fleet_planning_policy_id,
    :fleet_planning_policy_version,
    :allowed_actions,
    :maximum_horizon_seconds,
    :maximum_contacts,
    :maximum_execution_concurrency,
    :validity_seconds,
    :lifecycle_state,
    :proposed_by,
    :proposed_at,
    :proposal_expires_at,
    :approval_reason,
    :content_sha256
  ]

  # The state-changing fields a decision writes onto the projection row; every change is built
  # from a validated AutomationGrant (`transition_changeset/2`), never from caller params.
  @transition_fields [
    :lifecycle_state,
    :approved_by,
    :approved_at,
    :approval_policy,
    :valid_from,
    :valid_until,
    :rejected_by,
    :rejected_at,
    :rejection_reason,
    :withdrawn_by,
    :withdrawn_at,
    :revoked_by,
    :revoked_at,
    :revocation_reason,
    :allowed_actions,
    :maximum_horizon_seconds,
    :maximum_contacts,
    :maximum_estimated_cost_micros,
    :currency,
    :maximum_execution_concurrency,
    :validity_seconds,
    :content_sha256,
    :suspended_by,
    :suspended_at,
    :suspension_revision,
    :suspension_level,
    :resumed_by,
    :resumed_at
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

  @doc """
  The row moved to `grant`'s state (approve, reject, withdraw, revoke, narrow). `grant` is the
  row's own grant after the transition, built and shape-checked by AutomationGrant.new/1, so the
  row can only hold a valid state; the identity and scope fields never change.
  """
  @spec transition_changeset(struct(), AutomationGrant.t()) :: Ecto.Changeset.t()
  def transition_changeset(%__MODULE__{} = row, %AutomationGrant{} = grant) do
    row
    |> cast(Map.take(domain_attrs(grant), @transition_fields), @transition_fields)
    |> common_validations()
    |> unique_constraint(
      [:organization_id, :mission_id, :service_identity_id],
      name: :automation_grants_one_active_per_service_idx
    )
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
      ending: ending(row),
      validity_seconds: row.validity_seconds,
      proposed_by: row.proposed_by,
      proposed_at: row.proposed_at,
      proposal_expires_at: row.proposal_expires_at,
      approval_policy: row.approval_policy,
      replaces_grant_id: row.replaces_grant_id,
      legacy_issue: row.legacy_issue == true,
      suspension: suspension(row),
      resumed_by: row.resumed_by,
      resumed_at: row.resumed_at,
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
    |> validate_inclusion(
      :lifecycle_state,
      ~w(proposed active suspended rejected revoked withdrawn)
    )
    |> validate_number(:validity_seconds, greater_than: 0)
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
    grant
    |> base_attrs()
    |> Map.merge(ending_columns(grant.lifecycle_state, grant.ending))
  end

  # The domain's one `ending` lives in the state's own columns (#283).
  defp ending(%{lifecycle_state: "revoked"} = row),
    do: %{by: row.revoked_by, at: row.revoked_at, reason: row.revocation_reason}

  defp ending(%{lifecycle_state: "rejected"} = row),
    do: %{by: row.rejected_by, at: row.rejected_at, reason: row.rejection_reason}

  defp ending(%{lifecycle_state: "withdrawn"} = row),
    do: %{by: row.withdrawn_by, at: row.withdrawn_at, reason: nil}

  defp ending(_row), do: nil

  defp suspension(%{suspended_by: by} = row) when is_binary(by),
    do: %{
      by: by,
      at: row.suspended_at,
      revision: row.suspension_revision,
      level: row.suspension_level
    }

  defp suspension(_row), do: nil

  @no_ending %{
    revoked_by: nil,
    revoked_at: nil,
    revocation_reason: "",
    rejected_by: nil,
    rejected_at: nil,
    rejection_reason: nil,
    withdrawn_by: nil,
    withdrawn_at: nil
  }

  defp ending_columns(:revoked, e),
    do: %{@no_ending | revoked_by: e.by, revoked_at: e.at, revocation_reason: e.reason || ""}

  defp ending_columns(:rejected, e),
    do: %{@no_ending | rejected_by: e.by, rejected_at: e.at, rejection_reason: e.reason}

  defp ending_columns(:withdrawn, e), do: %{@no_ending | withdrawn_by: e.by, withdrawn_at: e.at}
  defp ending_columns(_state, _ending), do: @no_ending

  defp base_attrs(grant) do
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
      validity_seconds: grant.validity_seconds,
      proposed_by: grant.proposed_by,
      proposed_at: grant.proposed_at,
      proposal_expires_at: grant.proposal_expires_at,
      approval_policy: grant.approval_policy,
      replaces_grant_id: grant.replaces_grant_id,
      suspended_by: grant.suspension && grant.suspension.by,
      suspended_at: grant.suspension && grant.suspension.at,
      suspension_revision: grant.suspension && grant.suspension.revision,
      suspension_level: grant.suspension && grant.suspension.level,
      resumed_by: grant.resumed_by,
      resumed_at: grant.resumed_at
    }
  end
end
