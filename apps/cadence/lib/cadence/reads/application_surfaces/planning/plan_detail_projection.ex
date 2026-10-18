defmodule Cadence.Reads.ApplicationSurfaces.Planning.PlanDetailProjection do
  @moduledoc false

  alias Cadence.Auth.Policy

  def project(scope, plan, version, decision, query, evidence) do
    requirements = version.coverage_document["requirements"]
    policies = version.policy_snapshot_document["requirements"]

    %{
      contract_version: 1,
      context: %{organization_id: scope.organization_id, mission_id: plan.mission_id},
      plan: %{
        id: plan.contact_plan_id,
        version: version.version,
        current_version: plan.current_version,
        content_sha256: version.content_sha256,
        lifecycle_state: Atom.to_string(plan.lifecycle_state),
        approved_version: plan.approved_version,
        reviewed_decision: if(decision, do: approval(decision)),
        rationale: version.rationale,
        created_at: iso(version.created_at),
        selected_count: length(version.selected_snapshot_ids),
        locked_count: length(version.locked_snapshot_ids),
        rejected_count: length(version.rejected_snapshot_ids),
        coverage_satisfied: version.coverage_document["satisfied"],
        conflicts_clear: version.conflict_document["clear"],
        unsatisfied_clear: version.unsatisfied_document["clear"],
        manual_review:
          policies != [] and
            Enum.all?(policies, &(get_in(&1, ["approval_policy", "mode"]) == "manual"))
      },
      permissions: %{
        operate: allowed?(scope, :operate_mission, plan.mission_id),
        decide: allowed?(scope, :approve_contact_plans, plan.mission_id)
      },
      query: query,
      versions: page(evidence.versions, query["versions_page"], &version/1),
      approvals: page(evidence.approvals, query["approvals_page"], &approval/1),
      opportunities: page(evidence.opportunities, query["opportunities_page"], &opportunity/1),
      execution: page(evidence.execution, query["execution_page"], &execution/1),
      requirements:
        document_page(requirements, query["requirements_page"], &requirement(&1, policies)),
      issues: document_page(issues(version), query["issues_page"], & &1)
    }
  end

  defp allowed?(scope, action, mission),
    do:
      Policy.authorize(scope, action, %{
        organization_id: scope.organization_id,
        mission_id: mission
      }) == :ok

  defp page(result, number, project),
    do: %{page: number, more: result.more?, entries: Enum.map(result.entries, project)}

  defp document_page(entries, number, project) do
    rows = entries |> Enum.drop((number - 1) * 25) |> Enum.take(26)
    page(%{entries: Enum.take(rows, 25), more?: length(rows) > 25}, number, project)
  end

  defp version(v),
    do: %{
      id: v.contact_plan_version_id,
      version: v.version,
      content_sha256: v.content_sha256,
      created_at: iso(v.created_at)
    }

  defp approval(a),
    do: %{
      id: a.contact_plan_approval_id,
      version: a.contact_plan_version,
      content_sha256: a.content_sha256,
      decision: Atom.to_string(a.decision),
      reason: a.reason,
      actor_id: a.actor_id,
      actor_kind: Atom.to_string(a.actor_kind),
      decided_at: iso(a.decided_at)
    }

  defp execution(e),
    do: %{
      id: e.contact_plan_execution_item_id,
      version: e.contact_plan_version,
      snapshot_id: e.contact_opportunity_snapshot_id,
      state: Atom.to_string(e.lifecycle_state),
      attempts: e.attempt_count,
      reservation_id: e.provider_reservation_id
    }

  defp opportunity(%{disposition: disposition, snapshot: s}) do
    %{
      id: s.contact_opportunity_snapshot_id,
      disposition: Atom.to_string(disposition),
      content_sha256: s.content_sha256,
      requirement_id: s.contact_requirement_id,
      requirement_version: s.contact_requirement_version,
      provider: preview(s.route_binding_document["provider_display_name"] || "Provider"),
      station:
        preview(s.normalized_opportunity_document["ground_station_ref"] || "Unspecified station"),
      starts_at: iso(s.starts_at),
      ends_at: iso(s.ends_at),
      expires_at: iso(s.expires_at),
      eligible: s.eligible,
      synthetic: s.synthetic,
      availability: Atom.to_string(s.availability),
      route_key: preview(s.route_binding_document["route_key"] || "Unavailable route"),
      provider_id: s.route_binding_document["provider_id"],
      provider_version: s.route_binding_document["provider_version"],
      transport_id: s.route_binding_document["transport_id"],
      transport_version: s.route_binding_document["transport_version"]
    }
  end

  defp requirement(r, policies) do
    policy =
      Enum.find(
        policies,
        &(&1["contact_requirement_id"] == r["contact_requirement_id"] and
            &1["contact_requirement_version"] == r["contact_requirement_version"])
      )

    %{
      id: r["contact_requirement_id"],
      version: r["contact_requirement_version"],
      satisfied: r["satisfied"],
      selected_count: r["facts"]["selected_count"],
      eligible_count: r["facts"]["eligible_count"],
      hard_failure_count: length(r["hard_failures"]),
      search_failure_count: length(r["search_failures"]),
      approval_mode: get_in(policy, ["approval_policy", "mode"])
    }
  end

  defp issues(v) do
    requirement_issues =
      Enum.flat_map(v.coverage_document["requirements"], fn r ->
        Enum.map(r["hard_failures"] ++ r["search_failures"], fn item ->
          %{
            code: item["code"],
            requirement_id: r["contact_requirement_id"],
            requirement_version: r["contact_requirement_version"],
            message: preview(item["message"] || issue_message(item["code"])),
            snapshot_ids: []
          }
        end)
      end)

    conflicts =
      Enum.map(v.conflict_document["items"], fn item ->
        %{
          code: item["code"],
          requirement_id: nil,
          requirement_version: nil,
          message: "Selected contacts overlap.",
          snapshot_ids: item["snapshot_ids"]
        }
      end)

    (requirement_issues ++ conflicts)
    |> Enum.with_index(1)
    |> Enum.map(fn {item, index} -> Map.put(item, :id, "plan-issue-#{index}") end)
  end

  defp issue_message("selected_contacts_overlap"), do: "Selected contacts overlap."

  defp issue_message("minimum_separation_not_met"),
    do: "Selected contacts do not meet the minimum separation."

  defp issue_message("provider_search_unavailable"),
    do: "Provider search was unavailable for this requirement."

  defp issue_message(_), do: "Requirement review reported an issue."

  defp iso(time), do: DateTime.to_iso8601(time)
  defp preview(value) when is_binary(value), do: String.slice(value, 0, 120)
  defp preview(_), do: "Unavailable label"
end
