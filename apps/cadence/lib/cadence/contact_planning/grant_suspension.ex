defmodule Cadence.ContactPlanning.GrantSuspension do
  @moduledoc """
  #499 (the director on #283; ca-security and api-ops 11-20): tightening a mission's approval
  setting to 'independent' suspends its automation grants that went active on ONE approval (under
  'direct'), until a second, separated approval resumes them (`AutomationGrantReview.resume/5`).
  Suspended, not revoked: a suspended grant authorizes nothing (every use checks 'active').

  Which grants: active and unexpired, issued under #283 (a legacy grant is only ever revoked, and
  is refused at use already), whose stored approval policy didn't require separation (`false`, or
  missing on a non-legacy row: fail closed).

  Runs inside the setting's save (`Governance.ApprovalTightening`), under its exclusive lock:
  the policy lock first, then these rows `FOR UPDATE` (ActivationLocks' order). Grant issue and
  approve take the policy lock shared before reading it, so neither can slip a single-approval
  grant past a tightening.
  """

  @behaviour Cadence.Governance.ApprovalTightening

  import Ecto.Query

  alias Cadence.Auth
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{AutomationGrant, AutomationGrantDecisions, ContentHash}
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Contacts.Store.AutomationGrantRow
  alias Cadence.Missions
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @digest_version 1

  @impl true
  def preview(organization_id, mission_ids, acknowledged, opts) do
    case candidates(organization_id, mission_ids, now(opts)) do
      [] ->
        :ok

      grants ->
        digest = digest(grants)

        if acknowledged == digest,
          do: :ok,
          else:
            {:error,
             {:approval_tightening_suspends_grants,
              %{grants: describe(organization_id, grants), digest: digest}}}
    end
  end

  @impl true
  def apply(%Scope{} = scope, organization_id, mission_ids, revision_id, level, opts) do
    now = now(opts)
    actor = actor_id(scope)

    organization_id
    |> candidate_rows(mission_ids, now)
    |> Enum.reduce_while({:ok, []}, fn {row, grant}, {:ok, done} ->
      case suspend(scope, row, grant, actor, revision_id, level, now) do
        :ok -> {:cont, {:ok, [grant.automation_grant_id | done]}}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  The acknowledgement digest of what a tightening would suspend (ca-security's versioned layout,
  with api-ops' state): `sha256` of the canonical JSON of `[1, [[id, content_sha256, state], …]]`,
  sorted by id. A grant changed, revoked or added meanwhile changes it.
  """
  @spec digest([AutomationGrant.t()]) :: binary()
  def digest(grants) do
    entries =
      grants
      |> Enum.map(
        &[&1.automation_grant_id, &1.content_sha256, Atom.to_string(&1.lifecycle_state)]
      )
      |> Enum.sort()

    [@digest_version, entries] |> JsonDocument.encode() |> ContentHash.sha256()
  end

  @doc "The grants a tightening of `mission_ids` would suspend now (rows locked FOR UPDATE)."
  @spec candidates(binary(), [binary()], DateTime.t()) :: [AutomationGrant.t()]
  def candidates(organization_id, mission_ids, now),
    do: organization_id |> candidate_rows(mission_ids, now) |> Enum.map(&elem(&1, 1))

  defp candidate_rows(_organization_id, [], _now), do: []

  # In id order, so two tightenings lock the same rows in the same order.
  defp candidate_rows(organization_id, mission_ids, now) do
    AutomationGrantRow
    |> where(
      [r],
      r.organization_id == ^organization_id and r.mission_id in ^mission_ids and
        r.lifecycle_state == "active" and r.legacy_issue == false
    )
    |> order_by([r], asc: r.automation_grant_id)
    |> lock("FOR UPDATE")
    |> Repo.all()
    |> Enum.map(&{&1, AutomationGrantRow.to_domain(&1)})
    |> Enum.filter(fn {_row, grant} -> single_approval?(grant, now) end)
  end

  defp single_approval?(grant, now) do
    AutomationGrant.effective_state(grant, now) == :active and
      (grant.approval_policy || %{})["separation_of_duties"] != true
  end

  # A state change never re-hashes (as every grant act but narrowing): the stored hash stays.
  defp suspend(scope, row, grant, actor, revision_id, level, now) do
    suspended =
      grant
      |> Map.from_struct()
      |> Map.merge(%{
        lifecycle_state: :suspended,
        suspension: %{by: actor, at: now, revision: revision_id, level: level}
      })
      |> AutomationGrant.new()

    with {:ok, _row} <-
           row |> AutomationGrantRow.transition_changeset(suspended) |> Repo.update(),
         do:
           AutomationGrantDecisions.record(scope, :suspended, suspended, %{
             reason: "Approval setting tightened (settings revision #{revision_id}).",
             policy: ActivationPolicy.evidence(grant.organization_id, grant.mission_id),
             decided_at: now
           })
  end

  defp now(opts), do: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

  defp actor_id(%Scope{user: %{user_id: id}}) when is_binary(id), do: id
  defp actor_id(%Scope{service_identity: %{service_identity_id: id}}), do: id

  # The 409's list (ux words it): each grant with its mission and service, never an id as a name.
  defp describe(organization_id, grants) do
    missions =
      organization_id
      |> Missions.list_missions()
      |> Map.new(&{&1.mission_id, &1.display_name})

    services =
      Auth.service_identity_names(organization_id, Enum.map(grants, & &1.service_identity_id))

    Enum.map(grants, fn grant ->
      %{
        id: grant.automation_grant_id,
        mission: %{id: grant.mission_id, name: Map.get(missions, grant.mission_id)},
        service: %{
          id: grant.service_identity_id,
          name: Map.get(services, grant.service_identity_id)
        },
        allowed_actions: Enum.map(grant.allowed_actions, &Atom.to_string/1),
        valid_until: grant.valid_until
      }
    end)
  end
end
