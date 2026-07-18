defmodule Cadence.ContactPlanning.ContactPlanApprovals do
  @moduledoc "Organization-admin approval boundary for exact Contact Plan versions."

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.ContactPlanning.{
    AutomationGrants,
    ContactPlan,
    ContactPlanApproval,
    ContactPlanExecutions,
    ContactPlans,
    ContactPlanVersion,
    Planner
  }

  alias Cadence.Contacts.ProviderScheduling

  alias Cadence.Persistence.Schemas.{
    ContactPlanApprovalRow,
    ContactPlanRow,
    ContactPlanVersionRow,
    ContactRequirementRow,
    ContactRequirementVersionRow
  }

  alias Cadence.Repo

  @spec approve(
          Scope.t(),
          binary(),
          binary(),
          pos_integer(),
          binary(),
          binary(),
          keyword()
        ) ::
          {:ok, ContactPlan.t(), ContactPlanVersion.t(), ContactPlanApproval.t()}
          | {:error, term()}
  def approve(
        %Scope{} = current_scope,
        mission_id,
        plan_id,
        expected_version,
        expected_hash,
        reason,
        opts \\ []
      ) do
    decide(
      current_scope,
      mission_id,
      plan_id,
      expected_version,
      expected_hash,
      :approved,
      reason,
      opts
    )
  end

  @spec reject(
          Scope.t(),
          binary(),
          binary(),
          pos_integer(),
          binary(),
          binary(),
          keyword()
        ) ::
          {:ok, ContactPlan.t(), ContactPlanVersion.t(), ContactPlanApproval.t()}
          | {:error, term()}
  def reject(
        %Scope{} = current_scope,
        mission_id,
        plan_id,
        expected_version,
        expected_hash,
        reason,
        opts \\ []
      ) do
    decide(
      current_scope,
      mission_id,
      plan_id,
      expected_version,
      expected_hash,
      :rejected,
      reason,
      opts
    )
  end

  @spec list(binary(), binary(), binary()) :: [ContactPlanApproval.t()]
  def list(organization_id, mission_id, plan_id) do
    ContactPlanApprovalRow
    |> where(
      [approval],
      approval.organization_id == ^organization_id and approval.mission_id == ^mission_id and
        approval.contact_plan_id == ^plan_id
    )
    |> order_by([approval], desc: approval.contact_plan_version, desc: approval.decided_at)
    |> Repo.all()
    |> Enum.map(&ContactPlanApprovalRow.to_domain/1)
  end

  defp decide(
         %Scope{} = current_scope,
         mission_id,
         plan_id,
         expected_version,
         expected_hash,
         decision,
         reason,
         opts
       )
       when is_binary(mission_id) and is_binary(plan_id) and is_integer(expected_version) and
              expected_version > 0 and is_binary(expected_hash) and is_list(opts) do
    reason = reason |> to_string() |> String.trim()
    now = now(opts)

    with {:ok, actor} <- authorize_actor(current_scope, mission_id, decision, opts),
         :ok <- require_reason(reason) do
      Repo.transaction(fn ->
        decide_transaction(%{
          organization_id: current_scope.organization_id,
          mission_id: mission_id,
          plan_id: plan_id,
          expected_version: expected_version,
          expected_hash: expected_hash,
          decision: decision,
          reason: reason,
          actor: actor,
          now: now,
          opts: opts
        })
      end)
      |> normalize_result()
    end
  end

  defp decide(_scope, _mission_id, _plan_id, _version, _hash, _decision, _reason, _opts),
    do: {:error, :invalid_contact_plan_decision}

  defp maybe_revalidate(
         :rejected,
         _version,
         _requirements,
         _selected,
         _actor,
         _now,
         _opts
       ),
       do: :ok

  defp maybe_revalidate(:approved, version, requirements, selected, actor, now, opts) do
    with :ok <- proposal_satisfied(version),
         :ok <- approval_mode(requirements, actor),
         :ok <- unexpired(selected, now),
         :ok <- routes_exact(version.organization_id, version.mission_id, selected, opts),
         {:ok, current_policy} <- ContactPlans.policy_snapshot(requirements, selected) do
      exact_policy(version.policy_snapshot_document, current_policy)
    end
  end

  defp decide_transaction(context) do
    with {:ok, plan_row} <-
           lock_plan(context.organization_id, context.mission_id, context.plan_id),
         :ok <- pending_plan(plan_row),
         :ok <- exact_version(plan_row, context.expected_version),
         {:ok, version_row} <- fetch_version_row(plan_row, context.expected_version),
         :ok <- exact_hash(version_row, context.expected_hash),
         version <- ContactPlanVersionRow.to_domain(version_row),
         {:ok, requirements} <- lock_current_requirements(version),
         selected <- selected_snapshots(plan_row, version),
         :ok <-
           maybe_revalidate(
             context.decision,
             version,
             requirements,
             selected,
             context.actor,
             context.now,
             context.opts
           ),
         approval <-
           build_approval(
             plan_row,
             version,
             context.decision,
             context.reason,
             context.actor,
             context.now
           ),
         {:ok, approval_row} <- Repo.insert(ContactPlanApprovalRow.changeset(approval)),
         :ok <- maybe_create_execution_items(context.decision, plan_row, version, selected),
         {:ok, updated_plan_row} <-
           update_plan(
             plan_row,
             version,
             context.decision,
             context.actor,
             context.reason,
             context.now
           ) do
      {
        ContactPlanRow.to_domain(updated_plan_row),
        version,
        ContactPlanApprovalRow.to_domain(approval_row)
      }
    else
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp selected_snapshots(plan, version) do
    ContactPlans.selected_snapshots(
      plan.organization_id,
      plan.mission_id,
      plan.contact_plan_id,
      version.version
    )
  end

  defp maybe_create_execution_items(:approved, plan, version, _selected) do
    bookable =
      ContactPlans.bookable_snapshots(
        plan.organization_id,
        plan.mission_id,
        plan.contact_plan_id,
        version.version
      )

    ContactPlanExecutions.ensure_items(plan, version, bookable)
  end

  defp maybe_create_execution_items(:rejected, _plan, _version, _selected), do: :ok

  defp proposal_satisfied(version) do
    if version.conflict_document["clear"] == true and
         version.unsatisfied_document["clear"] == true and
         version.selected_snapshot_ids ++ version.locked_snapshot_ids != [],
       do: :ok,
       else: {:error, :contact_plan_not_satisfied}
  end

  defp approval_mode(requirements, %{"kind" => "user"}) do
    if Enum.all?(requirements, &(&1.approval_policy_document["mode"] == "manual")),
      do: :ok,
      else: {:error, :contact_plan_approval_policy_not_satisfied}
  end

  defp approval_mode(requirements, %{"kind" => "service"}) do
    if Enum.all?(
         requirements,
         &(&1.approval_policy_document["mode"] == "bounded_automatic")
       ),
       do: :ok,
       else: {:error, :contact_plan_approval_policy_not_satisfied}
  end

  defp unexpired(snapshots, now) do
    if Enum.all?(snapshots, &DateTime.after?(&1.expires_at, now)),
      do: :ok,
      else: {:error, :contact_plan_opportunity_expired}
  end

  defp routes_exact(organization_id, mission_id, snapshots, opts) do
    resolver =
      Keyword.get(opts, :resolve_route, &ProviderScheduling.resolve_ready_downlink_route/4)

    Enum.reduce_while(snapshots, :ok, fn snapshot, :ok ->
      route = snapshot.route_binding_document

      organization_id
      |> resolve_route(mission_id, route, resolver)
      |> route_resolution_result(route)
    end)
  end

  defp resolve_route(organization_id, mission_id, route, resolver) do
    resolver.(organization_id, mission_id, route["spacecraft_id"], route["route_key"])
  end

  defp route_resolution_result({:ok, current_route}, route) do
    if Planner.route_binding(current_route) == route,
      do: {:cont, :ok},
      else: {:halt, {:error, :contact_plan_route_binding_changed}}
  end

  defp route_resolution_result({:error, _reason}, _route),
    do: {:halt, {:error, :contact_plan_route_not_ready}}

  defp route_resolution_result(_other, _route),
    do: {:halt, {:error, :contact_plan_route_resolution_malformed}}

  defp exact_policy(policy, policy), do: :ok
  defp exact_policy(_approved, _current), do: {:error, :contact_plan_policy_snapshot_changed}

  defp lock_current_requirements(version) do
    refs = version.requirement_refs_document["requirements"] || []

    results = Enum.map(refs, &lock_current_requirement(version, &1))

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, requirement} -> requirement end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lock_current_requirement(version, ref) do
    requirement_id = ref["id"]
    requirement_version = ref["version"]

    version
    |> lock_requirement_row(requirement_id)
    |> validate_current_requirement(requirement_version)
  end

  defp lock_requirement_row(version, requirement_id) do
    ContactRequirementRow
    |> where(
      [requirement],
      requirement.organization_id == ^version.organization_id and
        requirement.mission_id == ^version.mission_id and
        requirement.contact_requirement_id == ^requirement_id
    )
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp validate_current_requirement(nil, _version),
    do: {:error, :contact_plan_requirement_not_found}

  defp validate_current_requirement(%ContactRequirementRow{lifecycle_state: state}, _version)
       when state != "active",
       do: {:error, :contact_plan_requirement_not_active}

  defp validate_current_requirement(%ContactRequirementRow{current_version: current}, expected)
       when current != expected,
       do: {:error, :contact_plan_requirement_changed}

  defp validate_current_requirement(row, _version), do: fetch_current_requirement_version(row)

  defp fetch_current_requirement_version(row) do
    case Repo.get_by(ContactRequirementVersionRow,
           organization_id: row.organization_id,
           mission_id: row.mission_id,
           contact_requirement_id: row.contact_requirement_id,
           version: row.current_version
         ) do
      nil -> {:error, :contact_plan_requirement_version_not_found}
      version_row -> {:ok, ContactRequirementVersionRow.to_domain(version_row)}
    end
  end

  defp build_approval(plan, version, decision, reason, actor, now) do
    ContactPlanApproval.new(%{
      organization_id: plan.organization_id,
      mission_id: plan.mission_id,
      contact_plan_id: plan.contact_plan_id,
      contact_plan_version: version.version,
      decision: decision,
      content_sha256: version.content_sha256,
      reason: reason,
      actor_kind: actor["kind"],
      actor_id: actor["id"],
      actor_document: actor,
      automation_grant_id: get_in(actor, ["automation_grant", "id"]),
      automation_grant_content_sha256: get_in(actor, ["automation_grant", "content_sha256"]),
      decided_at: now
    })
  end

  defp update_plan(plan, version, :approved, actor, reason, now) do
    plan
    |> ContactPlanRow.projection_changeset(%{
      current_version: plan.current_version,
      lifecycle_state: "approved",
      lifecycle_changed_by: actor["id"],
      lifecycle_changed_at: now,
      lifecycle_reason: reason,
      approved_version: version.version,
      approved_at: now,
      approved_by: actor["id"]
    })
    |> Repo.update()
  end

  defp update_plan(plan, _version, :rejected, actor, reason, now) do
    plan
    |> ContactPlanRow.projection_changeset(%{
      current_version: plan.current_version,
      lifecycle_state: "draft",
      lifecycle_changed_by: actor["id"],
      lifecycle_changed_at: now,
      lifecycle_reason: reason,
      approved_version: nil,
      approved_at: nil,
      approved_by: nil
    })
    |> Repo.update()
  end

  defp lock_plan(organization_id, mission_id, plan_id) do
    case ContactPlanRow
         |> where(
           [plan],
           plan.organization_id == ^organization_id and plan.mission_id == ^mission_id and
             plan.contact_plan_id == ^plan_id
         )
         |> lock("FOR UPDATE")
         |> Repo.one() do
      nil -> {:error, :contact_plan_not_found}
      row -> {:ok, row}
    end
  end

  defp fetch_version_row(plan, version) do
    case Repo.get_by(ContactPlanVersionRow,
           organization_id: plan.organization_id,
           mission_id: plan.mission_id,
           contact_plan_id: plan.contact_plan_id,
           version: version
         ) do
      nil -> {:error, :contact_plan_version_not_found}
      row -> {:ok, row}
    end
  end

  defp pending_plan(%ContactPlanRow{lifecycle_state: "pending_approval"}), do: :ok
  defp pending_plan(_plan), do: {:error, :contact_plan_not_pending_approval}
  defp exact_version(%ContactPlanRow{current_version: version}, version), do: :ok
  defp exact_version(_plan, _version), do: {:error, :stale_contact_plan_version}
  defp exact_hash(%ContactPlanVersionRow{content_sha256: hash}, hash), do: :ok
  defp exact_hash(_version, _hash), do: {:error, :stale_contact_plan_content}
  defp require_reason(""), do: {:error, :contact_plan_decision_reason_required}
  defp require_reason(_reason), do: :ok

  defp authorize_actor(
         %Scope{actor_kind: :user, user: user} = scope,
         _mission_id,
         _decision,
         _opts
       )
       when not is_nil(user) do
    with :ok <-
           Policy.authorize(scope, :approve_contact_plans, %{
             organization_id: scope.organization_id
           }) do
      {:ok,
       %{
         "kind" => "user",
         "id" => user.user_id,
         "user_id" => user.user_id,
         "display_name" => user.display_name,
         "email" => user.email
       }}
    end
  end

  defp authorize_actor(
         %Scope{actor_kind: :service, service_identity: identity} = scope,
         mission_id,
         :approved,
         opts
       ) do
    grant_id = Keyword.get(opts, :automation_grant_id)
    evidence = Keyword.get(opts, :automation_evidence, %{})

    with {:ok, grant} <-
           AutomationGrants.authorize(
             scope,
             mission_id,
             grant_id,
             :approve,
             evidence,
             opts
           ) do
      {:ok,
       %{
         "kind" => "service",
         "id" => identity.service_identity_id,
         "service_identity_id" => identity.service_identity_id,
         "display_name" => identity.display_name,
         "automation_grant" => %{
           "id" => grant.automation_grant_id,
           "content_sha256" => grant.content_sha256,
           "approved_by" => grant.approved_by,
           "approved_at" => DateTime.to_iso8601(grant.approved_at)
         }
       }}
    end
  end

  defp authorize_actor(%Scope{actor_kind: :service}, _mission_id, :rejected, _opts),
    do: {:error, :automation_cannot_reject_contact_plan}

  defp authorize_actor(%Scope{}, _mission_id, _decision, _opts),
    do: {:error, :authenticated_actor_required}

  defp normalize_result({:ok, {plan, version, approval}}),
    do: {:ok, plan, version, approval}

  defp normalize_result({:error, reason}), do: {:error, reason}

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)
end
