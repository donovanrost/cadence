defmodule Cadence.ContactPlanning.AutomationGrantDecisions do
  @moduledoc """
  The append-only decisions on automation grants (#283; Governance.DecisionRecord, api-ops
  11-19): proposed, not_required (direct mode), approved, rejected, revoked, narrowed, withdrawn.
  Each is written in the same transaction as the change it records; refusals write nothing.
  """

  @behaviour Cadence.Governance.DecisionRecord

  import Ecto.Query

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.AutomationGrant
  alias Cadence.Governance.DecisionRecord
  alias Cadence.Management.Contacts.Store.AutomationGrantDecisionRow
  alias Cadence.Repo

  @doc """
  Records `decision` by `scope` on `grant` (its state after the act). `attrs`: `reason`,
  `policy`, `separated_from`, `previous_digest`, `decided_at`.
  """
  @spec record(Scope.t(), atom(), AutomationGrant.t(), map()) :: :ok | {:error, term()}
  def record(%Scope{} = scope, decision, %AutomationGrant{} = grant, attrs \\ %{}) do
    subject = %{
      kind: "automation_grant",
      id: grant.automation_grant_id,
      digest: grant.content_sha256,
      previous_digest: Map.get(attrs, :previous_digest)
    }

    with {:ok, record} <-
           DecisionRecord.new(
             scope,
             attrs
             |> Map.take([:reason, :policy, :separated_from, :decided_at])
             |> Map.merge(%{decision: decision, subject: subject})
           ),
         {:ok, _row} <-
           record
           |> AutomationGrantDecisionRow.changeset(grant.organization_id, grant.mission_id)
           |> Repo.insert() do
      :ok
    end
  end

  @doc "A grant's decisions, oldest first (its audit, U105)."
  @spec list(binary(), binary(), binary()) :: [DecisionRecord.t()]
  def list(organization_id, mission_id, grant_id) do
    AutomationGrantDecisionRow
    |> where(
      [d],
      d.organization_id == ^organization_id and d.mission_id == ^mission_id and
        d.automation_grant_id == ^grant_id
    )
    |> order_by([d], asc: d.decided_at, asc: d.automation_grant_decision_id)
    |> Repo.all()
    |> Enum.map(&to_record/1)
  end

  @impl true
  def decisions(organization_id, opts \\ []) do
    AutomationGrantDecisionRow
    |> where([d], d.organization_id == ^organization_id)
    |> order_by([d], desc: d.decided_at)
    |> limit(^Keyword.get(opts, :limit, 200))
    |> Repo.all()
    |> Enum.map(&to_record/1)
  end

  defp to_record(row) do
    %DecisionRecord{
      actor: %{"kind" => row.actor_kind, "id" => row.actor_id},
      decision: String.to_existing_atom(row.decision),
      reason: row.reason,
      decided_at: row.decided_at,
      subject: %{
        kind: "automation_grant",
        id: row.automation_grant_id,
        version: nil,
        digest: row.digest,
        previous_digest: row.previous_digest
      },
      policy: row.policy_document,
      admin_mode: row.admin_mode,
      separated_from: row.separated_from
    }
  end
end
