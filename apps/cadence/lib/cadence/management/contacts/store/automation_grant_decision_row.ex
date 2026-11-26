defmodule Cadence.Management.Contacts.Store.AutomationGrantDecisionRow do
  @moduledoc false
  # One append-only decision on an automation grant (#283): built from a
  # Governance.DecisionRecord, never updated or deleted (the table's triggers refuse it).

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Governance.DecisionRecord

  @primary_key {:automation_grant_decision_id, :string, autogenerate: false}

  schema "automation_grant_decisions" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:automation_grant_id, :string)
    field(:decision, :string)
    field(:actor_kind, :string)
    field(:actor_id, :string)
    field(:reason, :string)
    field(:decided_at, :utc_datetime_usec)
    field(:digest, :string)
    field(:previous_digest, :string)
    field(:policy_document, :map)
    field(:separated_from, {:array, :string}, default: [])
    field(:admin_mode, :boolean, default: false)
  end

  @fields ~w(automation_grant_decision_id organization_id mission_id automation_grant_id decision
             actor_kind actor_id reason decided_at digest previous_digest policy_document
             separated_from admin_mode)a

  @spec changeset(DecisionRecord.t(), binary(), binary()) :: Ecto.Changeset.t()
  def changeset(%DecisionRecord{} = record, organization_id, mission_id) do
    %__MODULE__{}
    |> cast(
      %{
        automation_grant_decision_id: Cadence.Ids.new("automation_grant_decision"),
        organization_id: organization_id,
        mission_id: mission_id,
        automation_grant_id: record.subject.id,
        decision: Atom.to_string(record.decision),
        actor_kind: record.actor["kind"],
        actor_id: record.actor["id"],
        reason: record.reason,
        decided_at: record.decided_at,
        digest: record.subject.digest,
        previous_digest: record.subject.previous_digest,
        policy_document: policy(record.policy),
        separated_from: record.separated_from,
        admin_mode: record.admin_mode
      },
      @fields
    )
    |> validate_required(
      ~w(automation_grant_decision_id organization_id mission_id automation_grant_id decision
         actor_kind actor_id decided_at)a
    )
  end

  defp policy(%{} = policy), do: policy
  defp policy(nil), do: nil
  defp policy(token), do: %{"token" => token}
end
