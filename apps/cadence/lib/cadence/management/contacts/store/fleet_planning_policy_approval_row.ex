defmodule Cadence.Management.Contacts.Store.FleetPlanningPolicyApprovalRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ContactPlanning.FleetPlanningPolicyApproval
  alias Cadence.Persistence.JsonDocument

  @primary_key {:fleet_planning_policy_approval_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "fleet_planning_policy_approvals" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:fleet_planning_policy_id, :string)
    field(:fleet_planning_policy_version, :integer)
    field(:decision, :string)
    field(:content_sha256, :string)
    field(:reason, :string)
    field(:actor_user_id, :string)
    field(:actor_document, :map)
    field(:decided_at, :utc_datetime_usec)

    timestamps(updated_at: false)
  end

  @fields [
    :fleet_planning_policy_approval_id,
    :organization_id,
    :mission_id,
    :fleet_planning_policy_id,
    :fleet_planning_policy_version,
    :decision,
    :content_sha256,
    :reason,
    :actor_user_id,
    :actor_document,
    :decided_at
  ]

  @spec changeset(FleetPlanningPolicyApproval.t()) :: Ecto.Changeset.t()
  def changeset(%FleetPlanningPolicyApproval{} = approval) do
    %__MODULE__{}
    |> cast(domain_attrs(approval), @fields)
    |> validate_required(@fields)
    |> validate_number(:fleet_planning_policy_version, greater_than: 0)
    |> validate_inclusion(:decision, ~w(approved rejected))
    |> validate_length(:reason, max: 2_000)
    |> validate_format(:content_sha256, ~r/\A[0-9a-f]{64}\z/)
    |> unique_constraint(
      [
        :organization_id,
        :mission_id,
        :fleet_planning_policy_id,
        :fleet_planning_policy_version
      ],
      name: :fleet_planning_policy_approvals_version_uniq
    )
  end

  @spec to_domain(struct()) :: FleetPlanningPolicyApproval.t()
  def to_domain(%__MODULE__{} = row) do
    FleetPlanningPolicyApproval.new(%{
      fleet_planning_policy_approval_id: row.fleet_planning_policy_approval_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      fleet_planning_policy_id: row.fleet_planning_policy_id,
      fleet_planning_policy_version: row.fleet_planning_policy_version,
      decision: row.decision,
      content_sha256: row.content_sha256,
      reason: row.reason,
      actor_user_id: row.actor_user_id,
      actor_document: JsonDocument.unwrap_value(row.actor_document),
      decided_at: row.decided_at,
      inserted_at: row.inserted_at
    })
  end

  defp domain_attrs(approval) do
    %{
      fleet_planning_policy_approval_id: approval.fleet_planning_policy_approval_id,
      organization_id: approval.organization_id,
      mission_id: approval.mission_id,
      fleet_planning_policy_id: approval.fleet_planning_policy_id,
      fleet_planning_policy_version: approval.fleet_planning_policy_version,
      decision: Atom.to_string(approval.decision),
      content_sha256: approval.content_sha256,
      reason: approval.reason,
      actor_user_id: approval.actor_user_id,
      actor_document: JsonDocument.wrap_value(approval.actor_document),
      decided_at: approval.decided_at
    }
  end
end
