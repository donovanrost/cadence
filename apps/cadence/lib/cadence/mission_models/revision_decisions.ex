defmodule Cadence.MissionModels.RevisionDecisions do
  @moduledoc """
  Approving or rejecting a mission-model revision (`MissionModels.approve_revision/5`,
  `reject_revision/5`): the human gate a revision passes before a generation may introduce it
  (DECISIONS #92 (a), director 11-15; `Control.ModelApprovalGate`).

  - Only an organization administrator decides (`:approve_mission_model`), never a service.
  - Approval names the comparison report the approver saw. It must be this revision's and must
    have passed; a report whose replay didn't run (no qualification corpus) passes, and says so.
  - Under 'independent' approval (the mission's governance setting) whoever imported the revision
    can't approve it (`:mission_model_self_approval_forbidden`). A service importer counts as the
    people accountable for it, and a service nobody is accountable for refuses everyone
    (`:mission_model_approver_authors_unknown`, #280). A revision whose importer wasn't recorded at
    all (a seed's system actor, a legacy `%{}`) can be approved by any administrator; the approval
    records that (MM-2).
  - Approval needs a candidate (or already approved) revision whose four runtime plans are ready.
  - Approval needs a mission composition that names the revision (#542, E1; `CompositionApproval`),
    refused as before with `:mission_model_revision_not_in_catalog`; rejecting doesn't. Importers
    are the union across the composition's layers plus its composer, and the evidence names the
    composition and each layer's id, mount and digest.
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Catalog.MissionModel.Revision
  alias Cadence.Governance.{Accountability, ActivationPolicy, DecisionRecord}
  alias Cadence.Ids

  alias Cadence.MissionModels.{
    Comparison,
    CompositionApproval,
    DecisionRow,
    RevisionRow,
    RuntimePlanRow
  }

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @typedoc "A service as a refusal names it (U100): `name` is nil when its row is gone."
  @type service :: %{id: binary(), name: binary() | nil}

  @typedoc """
  Why separation of duties bars a person from approving a revision (U100): `:self` (they imported
  it, or `via_service`, a service identity they're accountable for, did) or `:authors_unknown`
  (`service` imported it and nobody is on record as accountable for it, #280).
  """
  @type refusal :: %{
          reason: :self | :authors_unknown,
          via_service: service() | nil,
          service: service() | nil
        }

  @doc """
  The importer/approver separation (DECISIONS #92 a) for `person_id` on a revision: the check
  approval itself runs, so the approval read and C3 (#119) call it rather than repeat it, and
  #280's service accountability changes it in this one place.

  `{:ok, %{policy, importers, recorded}}` returns the policy in force, the recorded importers
  (people), and whether any importer is on record at all, a service included (#280), which
  approval writes into its evidence as `importer_recorded`. Under 'independent' an importer gets `{:refused, refusal}`.
  Authorization, status and plan readiness are separate checks.
  """
  @spec separation(binary(), binary(), binary(), binary() | nil) ::
          {:ok, %{policy: map(), importers: [binary()], recorded: boolean()}}
          | {:refused, refusal()}
  def separation(organization_id, mission_id, revision_id, person_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(revision_id) do
    policy = ActivationPolicy.evidence(organization_id, mission_id)
    # #280: importers as actors, services included (mms-engineer's review: a service import is
    # still a recorded importer). #542: across the composition's layers, plus its composer.
    actors = CompositionApproval.importer_actors(organization_id, mission_id, revision_id)
    importers = for {:user, id} <- actors, do: id
    checked = %{policy: policy, importers: importers, recorded: actors != []}

    if policy["separation_of_duties"] == true do
      # Every importer counts as people: a service importer is its issuer and rotators
      # (`Governance.Accountability`), and a service nobody is accountable for refuses everyone.
      case separate(organization_id, person_id, actors) do
        :ok ->
          {:ok, checked}

        {:error, {:self, via}} ->
          {:refused, %{reason: :self, via_service: via, service: nil}}

        {:error, {:unknown, svc}} ->
          {:refused, %{reason: :authors_unknown, via_service: nil, service: svc}}
      end
    else
      {:ok, checked}
    end
  end

  # No person can't be told apart from an importer, so it fails closed (#280).
  defp separate(_organization_id, nil, _actors), do: {:error, {:self, nil}}

  defp separate(organization_id, person_id, actors),
    do: Accountability.separate(organization_id, {:user, person_id}, actors)

  @doc """
  Approves a candidate revision against a passed comparison. `operation_id:` (the console's, #260)
  is recorded in the approval's evidence. On an approved revision (#260): the separation check
  still runs first; the same `operation_id`, approver and comparison report as its recorded
  approval answer `{:ok, {:replayed, revision}}` and write nothing; anything else is
  `{:error, {:mission_model_revision_already_approved, %{approved_by, approved_at}}}`.
  """
  @spec approve(Scope.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, Revision.t() | {:replayed, Revision.t()}} | {:error, term()}
  def approve(%Scope{} = scope, mission_id, revision_id, comparison_report_id, opts \\ [])
      when is_binary(mission_id) and is_binary(revision_id) and is_binary(comparison_report_id) do
    organization_id = scope.organization_id

    with :ok <- authorize(scope, mission_id),
         {:ok, actor} <- actor(scope) do
      # Read, check and update under the revision's row lock: two administrators deciding at once
      # serialize, and an approval can't land on a revision another one just rejected (api-ops).
      locked(organization_id, mission_id, revision_id, fn row ->
        approve_locked(row, actor, comparison_report_id, opts)
      end)
    end
  end

  # #260: approving an approved revision records nothing. The separation check runs first (the
  # importer gets its refusal, never who approved); then this approval's own retry is a replay,
  # matched against THIS revision's recorded approval only; anything else is refused with who
  # decided and when. The first approver stays on record either way.
  defp approve_locked(%RevisionRow{status: "approved"} = row, actor, report, opts) do
    with {:ok, _checked} <- independent(row, actor) do
      evidence = JsonDocument.unwrap_value(row.approved_by)

      if replay?(evidence, actor, report, Keyword.get(opts, :operation_id)),
        do: {:ok, {:replayed, row}},
        else: {:error, already_approved(evidence, row.approved_at)}
    end
  end

  defp approve_locked(row, actor, comparison_report_id, opts) do
    %{organization_id: organization_id, mission_id: mission_id, revision_id: revision_id} = row

    with :ok <- require_approvable(RevisionRow.to_domain(row)),
         {:ok, composition} <-
           CompositionApproval.require(organization_id, mission_id, revision_id),
         :ok <- require_ready_plans(organization_id, mission_id, revision_id),
         {:ok, comparison} <- Comparison.fetch(organization_id, mission_id, comparison_report_id),
         :ok <- passed_for(comparison, revision_id),
         {:ok, %{policy: policy, recorded: recorded}} <- independent(row, actor) do
      evidence =
        Map.merge(actor, %{
          # The approval policy in force at decision time (M2, director 11-18).
          "policy" => policy,
          "comparison_report_id" => comparison_report_id,
          "replay" => get_in(comparison, ["replay", "status"]),
          "importer_recorded" => recorded,
          # #542 (M2): the combination approved, not only a revision id.
          "composition" => CompositionApproval.evidence(composition),
          # Approved after it already ran (the pre-gate revisions, lead 11-15): the caller says so
          # (ModelApprovalGate.running?/3), and the audit tells it.
          "retroactive" => Keyword.get(opts, :retroactive, false) == true
        })
        |> put_operation_id(Keyword.get(opts, :operation_id))

      row |> RevisionRow.status_changeset(:approved, evidence, at(opts)) |> Repo.update()
    end
  end

  @doc "Rejects a candidate revision, with the reason (an approved one stays approved)."
  @spec reject(Scope.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, Revision.t()} | {:error, term()}
  def reject(%Scope{} = scope, mission_id, revision_id, reason, opts \\ [])
      when is_binary(mission_id) and is_binary(revision_id) do
    with :ok <- authorize(scope, mission_id),
         {:ok, actor} <- actor(scope),
         {:ok, reason} <- reason(reason) do
      locked(
        scope.organization_id,
        mission_id,
        revision_id,
        &reject_locked(&1, actor, reason, opts)
      )
    end
  end

  @doc """
  Withdraws an approved revision's approval (E2, #546; design §5): its status becomes `withdrawn`,
  which is terminal (a database trigger refuses any move away from it), and an append-only
  `mission_model_decisions` row records who, when and why, naming the composition approved.

  - The same authority as approving (`:approve_mission_model`), a person, never a service. No
    four-eyes (commanding, #546): withdrawing narrows what can run and stops nothing.
  - A reason is required. Takes the revision row FOR UPDATE; the caller holds the locks before it
    in `ActivationLocks`' order (`Control.ModelWithdrawal`: the stable policy, then the mission's
    configuration lock), so an apply's or approval's FOR SHARE sees the withdrawal or finishes first.
  - The status change and the decision row commit together.
  - On a withdrawn revision the same `operation_id` by the same person replays
    `{:ok, {:replayed, revision}}` (#260); anything else, and any revision that isn't approved, is
    `{:error, :mission_model_revision_not_withdrawable}`.
  """
  @spec withdraw(Scope.t(), binary(), binary(), term(), keyword()) ::
          {:ok, Revision.t() | {:replayed, Revision.t()}} | {:error, term()}
  def withdraw(%Scope{} = scope, mission_id, revision_id, reason, opts \\ [])
      when is_binary(mission_id) and is_binary(revision_id) do
    organization_id = scope.organization_id

    with :ok <- authorize(scope, mission_id),
         {:ok, actor} <- actor(scope),
         {:ok, reason} <- reason(reason) do
      locked(organization_id, mission_id, revision_id, fn row ->
        withdraw_locked(row, scope, actor, reason, opts)
      end)
    end
  end

  defp withdraw_locked(%RevisionRow{status: "approved"} = row, scope, actor, reason, opts) do
    %{organization_id: organization_id, mission_id: mission_id, revision_id: revision_id} = row
    composition = composition(organization_id, mission_id, revision_id)

    with {:ok, record} <-
           DecisionRecord.new(scope, %{
             decision: :withdrawn,
             reason: reason,
             subject: %{
               kind: "mission_model_revision",
               id: revision_id,
               digest: row.content_sha256,
               composition: composition && CompositionApproval.evidence(composition)
             },
             decided_at: at(opts)
           }) do
      Repo.insert!(%DecisionRow{
        decision_id: Ids.new("mission_model_decision"),
        organization_id: organization_id,
        mission_id: mission_id,
        revision_id: revision_id,
        composition_id: composition && composition.composition_id,
        decision: "withdrawn",
        actor: actor,
        reason: reason,
        subject: record.subject,
        policy_document: ActivationPolicy.evidence(organization_id, mission_id),
        admin_mode: record.admin_mode,
        operation_id: operation_id(opts),
        decided_at: record.decided_at
      })

      row |> RevisionRow.status_changeset(:withdrawn, actor, record.decided_at) |> Repo.update()
    end
  end

  defp withdraw_locked(%RevisionRow{status: "withdrawn"} = row, _scope, actor, _reason, opts) do
    case withdrawal(row.organization_id, row.mission_id, row.revision_id) do
      %DecisionRow{operation_id: id, actor: %{"id" => by}}
      when is_binary(id) and id != "" ->
        if id == operation_id(opts) and by == actor["id"],
          do: {:ok, {:replayed, row}},
          else: {:error, :mission_model_revision_not_withdrawable}

      _other ->
        {:error, :mission_model_revision_not_withdrawable}
    end
  end

  defp withdraw_locked(%RevisionRow{}, _scope, _actor, _reason, _opts),
    do: {:error, :mission_model_revision_not_withdrawable}

  @doc "The revision's withdrawal record, or nil."
  @spec withdrawal(binary(), binary(), binary()) :: DecisionRow.t() | nil
  def withdrawal(organization_id, mission_id, revision_id) do
    Repo.one(
      from(decision in DecisionRow,
        where:
          decision.organization_id == ^organization_id and decision.mission_id == ^mission_id and
            decision.revision_id == ^revision_id and decision.decision == "withdrawn"
      )
    )
  end

  defp composition(organization_id, mission_id, revision_id) do
    case CompositionApproval.require(organization_id, mission_id, revision_id) do
      {:ok, composition} -> composition
      {:error, _none} -> nil
    end
  end

  defp operation_id(opts) do
    case Keyword.get(opts, :operation_id) do
      id when is_binary(id) and id != "" -> id
      _none -> nil
    end
  end

  @doc """
  The mission's model decisions people made, newest first, for the organization audit:
  `[%{revision_id, decision: :approved | :rejected, at, by: %{"id", "display_name"}, evidence}]`.
  """
  # todo(authz): no scope here; callers authorize (the organization audit source).
  @spec list_decisions(binary(), binary()) :: [map()]
  def list_decisions(organization_id, mission_id) do
    from(row in RevisionRow,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          (not is_nil(row.approved_at) or not is_nil(row.rejected_at)),
      select:
        {row.revision_id, row.status, row.approved_at, row.approved_by, row.rejected_at,
         row.rejected_by}
    )
    |> Repo.all()
    |> Enum.flat_map(&decision/1)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
  end

  defp decision({id, "rejected", _approved_at, _approved_by, at, by}),
    do: person(id, :rejected, at, by)

  defp decision({id, _status, at, by, _rejected_at, _rejected_by}) when not is_nil(at),
    do: person(id, :approved, at, by)

  defp decision(_row), do: []

  defp person(id, decision, at, by) do
    case JsonDocument.unwrap_value(by) do
      %{"kind" => "user", "id" => user} = evidence ->
        [
          %{
            revision_id: id,
            decision: decision,
            at: at,
            by: %{"id" => user, "display_name" => evidence["display_name"]},
            evidence: evidence
          }
        ]

      _not_a_person ->
        []
    end
  end

  defp locked(organization_id, mission_id, revision_id, fun) do
    Repo.transaction(fn ->
      RevisionRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.revision_id == ^revision_id
      )
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> decide_locked(fun)
    end)
    |> case do
      {:ok, {:replayed, row}} -> {:ok, {:replayed, RevisionRow.to_domain(row)}}
      {:ok, row} -> {:ok, RevisionRow.to_domain(row)}
      {:error, reason} -> {:error, reason}
    end
  end

  # The recorded approval's own operation: same id, same approver, same comparison report.
  defp replay?(%{} = evidence, %{"id" => actor_id}, report, operation_id)
       when is_binary(operation_id) do
    evidence["operation_id"] == operation_id and evidence["id"] == actor_id and
      evidence["comparison_report_id"] == report
  end

  defp replay?(_evidence, _actor, _report, _operation_id), do: false

  defp already_approved(evidence, approved_at),
    do:
      {:mission_model_revision_already_approved,
       %{approved_by: evidence, approved_at: approved_at}}

  defp put_operation_id(evidence, id) when is_binary(id),
    do: Map.put(evidence, "operation_id", id)

  defp put_operation_id(evidence, _id), do: evidence

  defp reject_locked(%RevisionRow{status: "candidate"} = row, actor, reason, opts) do
    row
    |> RevisionRow.status_changeset(
      :rejected,
      actor
      |> Map.put("reason", reason)
      |> Map.put("policy", ActivationPolicy.evidence(row.organization_id, row.mission_id)),
      at(opts)
    )
    |> Repo.update()
  end

  defp reject_locked(%RevisionRow{}, _actor, _reason, _opts),
    do: {:error, :mission_model_revision_not_approvable}

  @reason_max 2_000

  defp reason(reason) when is_binary(reason) do
    case String.trim(reason) do
      "" ->
        {:error, :mission_model_decision_reason_required}

      trimmed when byte_size(trimmed) > @reason_max ->
        {:error, :mission_model_decision_reason_too_long}

      trimmed ->
        {:ok, trimmed}
    end
  end

  defp reason(_reason), do: {:error, :mission_model_decision_reason_required}

  defp decide_locked(nil, _fun), do: Repo.rollback(:mission_model_revision_not_found)

  defp decide_locked(row, fun) do
    case fun.(row) do
      {:ok, updated} -> updated
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp authorize(%Scope{} = scope, mission_id) do
    Policy.authorize(scope, :approve_mission_model, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    })
  end

  defp actor(%Scope{actor_kind: :user, user: %{user_id: id} = user}) when is_binary(id),
    do: {:ok, %{"kind" => "user", "id" => id, "display_name" => user.display_name}}

  defp actor(%Scope{}), do: {:error, :human_mission_model_approver_required}

  defp passed_for(%{"candidate_revision_id" => id, "status" => "passed"}, id), do: :ok

  defp passed_for(%{"candidate_revision_id" => id}, id),
    do: {:error, :mission_model_comparison_not_passed}

  defp passed_for(_comparison, _id), do: {:error, :mission_model_comparison_mismatch}

  defp independent(row, %{"id" => actor_id}) do
    case separation(row.organization_id, row.mission_id, row.revision_id, actor_id) do
      {:ok, checked} ->
        {:ok, checked}

      {:refused, %{reason: :self, via_service: nil}} ->
        {:error, :mission_model_self_approval_forbidden}

      # #280 (U100): through a service identity the approver is accountable for.
      {:refused, %{reason: :self, via_service: via}} ->
        {:error, {:mission_model_self_approval_forbidden, %{via_service: via}}}

      {:refused, %{reason: :authors_unknown, service: service}} ->
        {:error, {:mission_model_approver_authors_unknown, %{service: service}}}
    end
  end

  defp at(opts), do: opts |> Keyword.get(:at, DateTime.utc_now()) |> normalized_datetime()

  defp require_approvable(%Revision{status: :candidate}), do: :ok
  defp require_approvable(%Revision{status: :approved}), do: :ok
  defp require_approvable(%Revision{}), do: {:error, :mission_model_revision_not_approvable}

  defp require_ready_plans(organization_id, mission_id, revision_id) do
    statuses =
      RuntimePlanRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.revision_id == ^revision_id
      )
      |> select([row], row.status)
      |> Repo.all()

    if length(statuses) == 4 and Enum.all?(statuses, &(&1 == "ready")) do
      :ok
    else
      {:error, :mission_model_runtime_plans_not_ready}
    end
  end

  defp normalized_datetime(%DateTime{} = datetime) do
    {microsecond, _precision} = datetime.microsecond
    %{datetime | microsecond: {microsecond, 6}}
  end
end
