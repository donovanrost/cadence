defmodule Cadence.Reads.ApplicationSurfaces.Planning.FleetRun do
  @moduledoc "Authoritative bounded evidence for one mission-scoped fleet run."
  alias Cadence.ContactPlanning.{
    ContactPlans,
    ContactRequirements,
    FleetAutomationActions,
    FleetPlanningRuns,
    FleetRunRepairs,
    FleetRunReviews
  }

  alias Cadence.Reads.ApplicationSurfaces.Planning.FleetRunProjection, as: Projection
  @pages ~w(requirements_page decisions_page resources_page automation_page commitments_page)

  def load(scope, mission, params) do
    with {:ok, query} <- admit_query(Map.delete(params, "mission_id")),
         {:ok, snapshot} <- FleetRunReviews.load(scope, mission.mission_id, query.run_id),
         {:ok, requirements} <- requirement_page(snapshot, query.requirements_page),
         {:ok, decisions} <- decision_page(snapshot.run, query.decisions_page),
         {:ok, candidate} <- candidate(snapshot.run),
         {:ok, repair} <- repair(scope, snapshot, query.commitments_page) do
      automation =
        FleetAutomationActions.list_page(
          scope.organization_id,
          mission.mission_id,
          query.run_id,
          query.automation_page
        )

      {:ok,
       %{
         run:
           Projection.model(
             snapshot,
             query,
             requirements,
             decisions,
             candidate,
             repair,
             automation
           )
       }}
    end
  end

  def admit_query(params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in ["fleet_planning_run_id" | @pages])),
         id when is_binary(id) and byte_size(id) in 1..240 <- params["fleet_planning_run_id"],
         {:ok, pages} <- pages(params) do
      {:ok, Map.put(pages, :run_id, id)}
    else
      _ -> {:error, :invalid_fleet_run_query}
    end
  end

  def admit_query(_), do: {:error, :invalid_fleet_run_query}

  defp pages(params) do
    Enum.reduce_while(@pages, {:ok, %{}}, fn key, {:ok, acc} ->
      case page(Map.get(params, key, "1")) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, page_key(key), value)}}
        error -> {:halt, error}
      end
    end)
  end

  defp page(v) when is_binary(v) and byte_size(v) <= 7 do
    case Integer.parse(v) do
      {n, ""} when n in 1..1_000_000 ->
        if Integer.to_string(n) == v, do: {:ok, n}, else: {:error, :invalid_page}

      _ ->
        {:error, :invalid_page}
    end
  end

  defp page(_), do: {:error, :invalid_page}
  defp page_key("requirements_page"), do: :requirements_page
  defp page_key("decisions_page"), do: :decisions_page
  defp page_key("resources_page"), do: :resources_page
  defp page_key("automation_page"), do: :automation_page
  defp page_key("commitments_page"), do: :commitments_page

  defp requirement_page(snapshot, page) do
    selected = Enum.slice(snapshot.refs, (page - 1) * 10, 10)

    pins =
      Map.new(
        snapshot.run.input_document["requirements"],
        &{&1["contact_requirement_id"], &1["content_sha256"]}
      )

    with {:ok, rows} <- traverse(selected, fn ref -> requirement(snapshot.run, ref, pins) end) do
      {:ok,
       %{
         page: page,
         more: length(snapshot.refs) > page * 10,
         total: length(snapshot.refs),
         entries: rows
       }}
    end
  end

  defp requirement(run, ref, pins) do
    with {:ok, version} <-
           ContactRequirements.fetch_version(
             run.organization_id,
             run.mission_id,
             ref.contact_requirement_id,
             ref.contact_requirement_version
           ),
         true <- pins[ref.contact_requirement_id] == version.content_sha256 do
      {:ok, Projection.requirement(ref, version)}
    else
      _ -> {:error, :fleet_run_requirement_unavailable}
    end
  end

  defp decision_page(run, page) do
    ledger =
      FleetPlanningRuns.decisions_page(
        run.organization_id,
        run.mission_id,
        run.fleet_planning_run_id,
        page
      )

    with {:ok, rows} <- traverse(ledger.entries, &decision(run, &1)),
         do: {:ok, %{ledger | entries: rows}}
  end

  defp decision(run, decision) do
    with {:ok, snapshot} <-
           ContactPlans.fetch_opportunity_snapshot(
             run.organization_id,
             run.mission_id,
             decision.contact_opportunity_snapshot_id
           ),
         do: {:ok, Projection.decision(decision, snapshot)}
  end

  defp candidate(%{candidate_contact_plan_id: nil}), do: {:ok, nil}

  defp candidate(run) do
    with {:ok, plan, _} <-
           ContactPlans.fetch(run.organization_id, run.mission_id, run.candidate_contact_plan_id),
         {:ok, version} <-
           ContactPlans.fetch_version(
             run.organization_id,
             run.mission_id,
             run.candidate_contact_plan_id,
             run.candidate_contact_plan_version
           ) do
      {:ok,
       %{
         id: plan.contact_plan_id,
         version: version.version,
         content_sha256: version.content_sha256,
         lifecycle_state: Atom.to_string(plan.lifecycle_state),
         current_version: plan.current_version
       }}
    end
  end

  defp repair(scope, snapshot, page) do
    case FleetRunRepairs.review(scope, snapshot) do
      {:ok, review} ->
        {:ok, Projection.repair(review, page)}

      {:error, reason}
      when reason in [
             :fleet_repair_source_unavailable,
             :fleet_repair_source_run_not_complete,
             :fleet_repair_source_plan_not_repairable,
             :fleet_repair_source_plan_version_changed,
             :active_fleet_planning_policy_not_found
           ] ->
        {:ok, %{available: false, reason: Atom.to_string(reason)}}

      {:error, _} = error ->
        error
    end
  end

  defp traverse(rows, fun) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case fun.(row) do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end
end
