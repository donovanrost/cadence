defmodule Cadence.Reads.ApplicationSurfaces.Planning.FleetRunProjection do
  @moduledoc "Semantic fleet evidence; provider payloads and error documents remain private."
  alias Cadence.ContactPlanning.{FleetRunRepairs, FleetRunReviews, FleetStartProjection}

  def model(snapshot, query, requirements, decisions, candidate, repair, automation) do
    run = snapshot.run

    %{
      contract_version: 1,
      context: %{organization_id: run.organization_id, mission_id: run.mission_id},
      query: Map.drop(query, [:run_id]),
      id: run.fleet_planning_run_id,
      lifecycle_state: Atom.to_string(run.lifecycle_state),
      phase: Atom.to_string(run.phase),
      trigger_kind: Atom.to_string(run.trigger_kind),
      algorithm: %{key: run.algorithm_key, version: run.algorithm_version},
      horizon_start: timestamp(run.horizon_start),
      horizon_end: timestamp(run.horizon_end),
      inserted_at: timestamp(run.inserted_at),
      started_at: timestamp(run.started_at),
      completed_at: timestamp(run.completed_at),
      policy: FleetStartProjection.policy(snapshot.policy),
      evidence: snapshot.evidence,
      can_continue: FleetRunReviews.continuable?(run),
      candidate: candidate,
      source: source(run),
      requirements: requirements,
      decisions: decisions,
      repair: repair,
      resources: resources(run.result_summary_document["resources"], query.resources_page),
      automation: %{automation | entries: Enum.map(automation.entries, &automation/1)},
      failure: failure(run.failure_document)
    }
  end

  def requirement(ref, version),
    do: %{
      id: ref.fleet_planning_run_requirement_ref_id,
      requirement_id: ref.contact_requirement_id,
      version: ref.contact_requirement_version,
      content_sha256: version.content_sha256,
      spacecraft_id: version.spacecraft_id,
      earliest_start: timestamp(version.earliest_start),
      latest_end: timestamp(version.latest_end),
      input_state: Atom.to_string(ref.input_state),
      result_state: Atom.to_string(ref.result_state),
      planning_run_id: ref.contact_planning_run_id,
      priority: Atom.to_string(version.priority)
    }

  def decision(d, snapshot),
    do: %{
      id: d.fleet_planning_decision_id,
      snapshot_id: d.contact_opportunity_snapshot_id,
      spacecraft_id: snapshot.route_binding_document["spacecraft_id"],
      starts_at: timestamp(snapshot.starts_at),
      ends_at: timestamp(snapshot.ends_at),
      disposition: Atom.to_string(d.disposition),
      score: d.score,
      rank: d.rank,
      code: text(d.explanation_document["code"], 80),
      rationale: text(d.explanation_document["message"], 400),
      constraints_satisfied: d.hard_constraint_document["satisfied"] == true,
      failures:
        d.hard_constraint_document
        |> Map.get("failures", [])
        |> Enum.take(8)
        |> Enum.map(&failure_code/1)
    }

  def repair(review, page) do
    source = review.source
    policy = FleetRunRepairs.policy_projection(review)
    start = DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.truncate(:second)

    %{
      available: review.allowed,
      reason: if(review.allowed, do: nil, else: "fleet_repair_attempt_limit_exceeded"),
      evidence: review.evidence,
      policy: policy,
      attempt: source.repair_attempt,
      plan: %{
        id: source.plan.contact_plan_id,
        version: source.plan_version.version,
        lifecycle_state: Atom.to_string(source.plan.lifecycle_state)
      },
      defaults: %{
        horizon_start: timestamp(start),
        horizon_end:
          start |> DateTime.add(policy.max_repair_horizon_seconds, :second) |> timestamp()
      },
      commitments:
        page(source.locked_commitments, page, fn s ->
          %{
            id: s.contact_opportunity_snapshot_id,
            content_sha256: s.content_sha256,
            spacecraft_id: s.route_binding_document["spacecraft_id"],
            starts_at: timestamp(s.starts_at),
            ends_at: timestamp(s.ends_at)
          }
        end)
    }
  end

  defp resources(nil, page), do: %{page: page, more: false, total: 0, entries: []}

  defp resources(document, page) do
    document
    |> Map.get("resources", %{})
    |> Enum.sort_by(&elem(&1, 0))
    |> page(page, fn {key, value} ->
      %{
        key: key,
        peak_parallel: value["peak_parallel"],
        capacity: value["capacity"],
        selected_count: value["selected_count"],
        over_capacity: value["over_capacity"]
      }
    end)
  end

  defp page(rows, page, mapper),
    do: %{
      page: page,
      more: length(rows) > page * 10,
      total: length(rows),
      entries: rows |> Enum.slice((page - 1) * 10, 10) |> Enum.map(mapper)
    }

  defp automation(a),
    do: %{
      id: a.fleet_automation_action_id,
      action: Atom.to_string(a.action),
      lifecycle_state: Atom.to_string(a.lifecycle_state),
      attempt_count: a.attempt_count,
      grant_id: a.automation_grant_id,
      service_identity_id: a.service_identity_id,
      plan_id: a.contact_plan_id,
      plan_version: a.contact_plan_version,
      started_at: timestamp(a.started_at),
      completed_at: timestamp(a.completed_at)
    }

  defp source(%{source_fleet_planning_run_id: nil}), do: nil

  defp source(run),
    do: %{
      run_id: run.source_fleet_planning_run_id,
      plan_id: run.source_contact_plan_id,
      plan_version: run.source_contact_plan_version
    }

  defp failure(document) when map_size(document) == 0, do: nil
  defp failure(document), do: %{code: text(document["code"], 80)}
  defp failure_code(%{"code" => code}), do: text(code, 80)
  defp failure_code(code) when is_binary(code), do: text(code, 80)
  defp failure_code(_), do: "constraint_failed"

  defp text(v, maximum) when is_binary(v),
    do: v |> String.slice(0, maximum) |> String.replace(~r/[\x00-\x1f\x7f]/u, " ")

  defp text(_, _), do: nil
  defp timestamp(nil), do: nil
  defp timestamp(value), do: DateTime.to_iso8601(value)
end
