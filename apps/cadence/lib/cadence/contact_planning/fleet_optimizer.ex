defmodule Cadence.ContactPlanning.FleetOptimizer do
  @moduledoc """
  Pure deterministic bounded allocator for exact Requirement and opportunity snapshots.

  Hard constraints decide feasibility. Integer score components only rank feasible
  alternatives and are retained with each explainable decision.
  """

  alias Cadence.ContactPlanning.{
    ContactOpportunitySnapshot,
    ContactRequirementVersion,
    FleetOptimizationResult,
    FleetOptimizer.Constraints,
    FleetOptimizer.Scoring,
    FleetPlanningPolicyVersion,
    RequirementEvaluator
  }

  @algorithm_key "deterministic_bounded_greedy"
  @algorithm_version 1

  @type decision :: %{
          required(:contact_opportunity_snapshot_id) => binary(),
          required(:disposition) => :selected | :displaced | :ineligible | :locked,
          required(:score) => integer(),
          required(:rank) => pos_integer() | nil,
          required(:hard_constraint_document) => map(),
          required(:score_document) => map(),
          required(:explanation_document) => map()
        }

  @spec optimize(
          [ContactRequirementVersion.t()],
          [ContactOpportunitySnapshot.t()],
          FleetPlanningPolicyVersion.t(),
          keyword()
        ) :: {:ok, FleetOptimizationResult.t()} | {:error, term()}
  def optimize(requirements, snapshots, policy, opts \\ [])

  def optimize(requirements, snapshots, %FleetPlanningPolicyVersion{} = policy, opts)
      when is_list(requirements) and is_list(snapshots) and is_list(opts) do
    now = opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)
    locked_commitments = Keyword.get(opts, :locked_commitments, [])
    requested_locked_ids = MapSet.new(Keyword.get(opts, :locked_snapshot_ids, []))

    with {:ok, requirements} <- normalize_requirements(requirements, policy),
         {:ok, snapshots} <- normalize_snapshots(snapshots ++ locked_commitments, policy),
         {:ok, locked_ids} <-
           normalize_locked_ids(snapshots, locked_commitments, requested_locked_ids),
         {:ok, initial} <- initialize(snapshots, requirements, policy, locked_ids, now) do
      scarcity = scarcity(initial.feasible)

      state =
        requirements
        |> demand_order(scarcity)
        |> Enum.reduce(initial, fn requirement, state ->
          allocate_requirement(requirement, scarcity, requirements, policy, now, state)
        end)
        |> improve_locally(requirements, policy, scarcity, now)
        |> assign_ranks()

      selected = ordered_selected(state.selected)
      coverage = coverage(requirements, selected, policy)

      {:ok,
       %FleetOptimizationResult{
         selected_snapshot_ids: Enum.map(selected, & &1.contact_opportunity_snapshot_id),
         selected_snapshots: selected,
         decisions: ordered_decisions(state.decisions),
         coverage_by_requirement: coverage,
         resource_summary:
           state
           |> selected_with_lock_count(selected)
           |> Map.merge(Constraints.resource_summary(selected, policy)),
         budget_summary: Constraints.budget_summary(selected, policy),
         termination_document: %{
           "algorithm_key" => @algorithm_key,
           "algorithm_version" => @algorithm_version,
           "reason" => "bounded_search_complete",
           "greedy_candidate_evaluations" => state.greedy_evaluations,
           "local_improvement_evaluations" => state.improvement_evaluations,
           "local_improvement_replacements" => state.improvement_replacements,
           "local_improvement_limit" => policy.scoring_document["local_improvement_limit"],
           "configured_local_improvement_width" =>
             policy.scoring_document["local_improvement_width"],
           "effective_local_improvement_width" => 1,
           "considered_snapshot_count" => length(snapshots),
           "selected_snapshot_count" => length(selected),
           "locked_snapshot_count" => MapSet.size(locked_ids)
         }
       }}
    end
  end

  def optimize(_requirements, _snapshots, _policy, _opts),
    do: {:error, :invalid_fleet_optimizer_inputs}

  defp normalize_requirements(requirements, policy) do
    requirements
    |> Enum.reduce_while({:ok, %{}}, fn
      %ContactRequirementVersion{} = requirement, {:ok, result} ->
        key = requirement_key(requirement)

        cond do
          requirement.organization_id != policy.organization_id or
              requirement.mission_id != policy.mission_id ->
            {:halt, {:error, :fleet_optimizer_scope_mismatch}}

          Map.has_key?(result, key) and
              result[key].content_sha256 != requirement.content_sha256 ->
            {:halt, {:error, {:fleet_optimizer_requirement_identity_collision, key}}}

          true ->
            {:cont, {:ok, Map.put(result, key, requirement)}}
        end

      _requirement, _result ->
        {:halt, {:error, :invalid_fleet_optimizer_requirement}}
    end)
    |> case do
      {:ok, result} when map_size(result) > 0 -> {:ok, result}
      {:ok, _result} -> {:error, :fleet_optimizer_requires_requirements}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_snapshots(snapshots, policy) do
    snapshots
    |> Enum.reduce_while({:ok, %{}}, fn
      %ContactOpportunitySnapshot{} = snapshot, {:ok, result} ->
        id = snapshot.contact_opportunity_snapshot_id

        cond do
          snapshot.organization_id != policy.organization_id or
              snapshot.mission_id != policy.mission_id ->
            {:halt, {:error, :fleet_optimizer_scope_mismatch}}

          Map.has_key?(result, id) and result[id].content_sha256 != snapshot.content_sha256 ->
            {:halt, {:error, {:fleet_optimizer_snapshot_identity_collision, id}}}

          true ->
            {:cont, {:ok, Map.put(result, id, snapshot)}}
        end

      _snapshot, _result ->
        {:halt, {:error, :invalid_fleet_optimizer_snapshot}}
    end)
    |> case do
      {:ok, result} ->
        {:ok,
         result
         |> Map.values()
         |> Enum.sort_by(& &1.contact_opportunity_snapshot_id)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_locked_ids(snapshots, locked_commitments, requested_ids) do
    commitment_ids =
      locked_commitments
      |> Enum.map(& &1.contact_opportunity_snapshot_id)
      |> MapSet.new()

    locked_ids = MapSet.union(requested_ids, commitment_ids)
    available_ids = snapshots |> Enum.map(& &1.contact_opportunity_snapshot_id) |> MapSet.new()

    if MapSet.subset?(locked_ids, available_ids),
      do: {:ok, locked_ids},
      else: {:error, :fleet_optimizer_locked_snapshot_not_found}
  end

  defp initialize(snapshots, requirements, policy, locked_ids, now) do
    initial = %{
      all: Map.new(snapshots, &{&1.contact_opportunity_snapshot_id, &1}),
      feasible: [],
      selected: [],
      locked_ids: locked_ids,
      decisions: %{},
      greedy_evaluations: 0,
      improvement_evaluations: 0,
      improvement_replacements: 0
    }

    snapshots
    |> Enum.reduce_while(
      {:ok, initial},
      &initialize_snapshot(&1, &2, requirements, policy, locked_ids, now)
    )
    |> case do
      {:ok, state} -> {:ok, %{state | feasible: Enum.reverse(state.feasible)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp initialize_snapshot(snapshot, {:ok, state}, requirements, policy, locked_ids, now) do
    requirement = requirements[snapshot_key(snapshot)]
    locked? = MapSet.member?(locked_ids, snapshot.contact_opportunity_snapshot_id)

    case {requirement, locked?} do
      {nil, true} ->
        {:halt,
         {:error,
          {:fleet_optimizer_locked_requirement_not_found,
           snapshot.contact_opportunity_snapshot_id}}}

      {nil, false} ->
        {:cont, {:ok, put_ineligible(state, snapshot, missing_requirement_failures(snapshot))}}

      {_requirement, true} ->
        {:cont, {:ok, add_locked_snapshot(state, snapshot)}}

      {requirement, false} ->
        {:cont, {:ok, classify_snapshot(state, requirement, snapshot, policy, now)}}
    end
  end

  defp missing_requirement_failures(snapshot) do
    [
      %{
        "code" => "requirement_input_not_found",
        "message" => "Snapshot does not reference a fleet-run Requirement input.",
        "evidence" => %{
          "contact_requirement_id" => snapshot.contact_requirement_id,
          "contact_requirement_version" => snapshot.contact_requirement_version
        }
      }
    ]
  end

  defp add_locked_snapshot(state, snapshot) do
    state
    |> Map.update!(:selected, &[snapshot | &1])
    |> put_decision(
      snapshot,
      :locked,
      0,
      %{"scale" => 1_000, "components" => %{}, "total" => 0},
      [],
      "locked_commitment",
      "Existing successful or uncertain commitment is preserved."
    )
  end

  defp classify_snapshot(state, requirement, snapshot, policy, now) do
    case Constraints.inherent_failures(requirement, snapshot, policy, now) do
      [] -> Map.update!(state, :feasible, &[snapshot | &1])
      failures -> put_ineligible(state, snapshot, failures)
    end
  end

  defp allocate_requirement(requirement, scarcity, requirements, policy, now, state) do
    candidates =
      Enum.filter(state.feasible, fn snapshot ->
        same_requirement?(snapshot, requirement) and
          not Map.has_key?(state.decisions, snapshot.contact_opportunity_snapshot_id)
      end)

    allocate_candidates(
      requirement,
      candidates,
      scarcity,
      requirements,
      policy,
      now,
      state
    )
  end

  defp allocate_candidates(
         _requirement,
         [],
         _scarcity,
         _requirements,
         _policy,
         _now,
         state
       ),
       do: state

  defp allocate_candidates(
         requirement,
         candidates,
         scarcity,
         requirements,
         policy,
         now,
         state
       ) do
    scored =
      candidates
      |> Enum.map(fn snapshot ->
        {score, document} =
          Scoring.score(
            requirement,
            snapshot,
            scarcity[requirement_key(requirement)],
            state.selected,
            policy,
            now
          )

        {snapshot, score, document}
      end)
      |> Enum.sort_by(fn {snapshot, score, _document} ->
        {-score, snapshot.starts_at, snapshot.contact_opportunity_snapshot_id}
      end)

    [{snapshot, score, score_document} | _rest] = scored
    remaining = Enum.reject(candidates, &same_snapshot?(&1, snapshot))
    state = Map.update!(state, :greedy_evaluations, &(&1 + 1))

    state =
      if coverage_satisfied?(requirement, state.selected, policy) do
        put_decision(
          state,
          snapshot,
          :displaced,
          score,
          score_document,
          [],
          "requirement_already_satisfied",
          "A higher-ranked feasible selection already satisfies this Requirement."
        )
      else
        allocate_candidate(
          state,
          requirement,
          snapshot,
          score,
          score_document,
          requirements,
          policy
        )
      end

    allocate_candidates(
      requirement,
      remaining,
      scarcity,
      requirements,
      policy,
      now,
      state
    )
  end

  defp allocate_candidate(
         state,
         requirement,
         snapshot,
         score,
         score_document,
         requirements,
         policy
       ) do
    case Constraints.dynamic_failures(
           requirement,
           snapshot,
           state.selected,
           requirements,
           policy
         ) do
      [] ->
        state
        |> Map.update!(:selected, &[snapshot | &1])
        |> put_decision(
          snapshot,
          :selected,
          score,
          score_document,
          [],
          "selected_by_greedy_allocator",
          "This was the highest-ranked feasible opportunity at this allocation step."
        )

      failures ->
        put_decision(
          state,
          snapshot,
          :displaced,
          score,
          score_document,
          failures,
          "hard_constraint_blocked",
          "This opportunity was feasible in isolation but conflicts with fleet state."
        )
    end
  end

  defp improve_locally(state, requirements, policy, scarcity, now) do
    limit = policy.scoring_document["local_improvement_limit"]

    candidates =
      state.decisions
      |> Map.values()
      |> Enum.filter(&(&1.disposition == :displaced))
      |> Enum.sort_by(&{-&1.score, &1.contact_opportunity_snapshot_id})
      |> Enum.take(limit)

    Enum.reduce(candidates, state, fn decision, state ->
      state = Map.update!(state, :improvement_evaluations, &(&1 + 1))
      candidate = state.all[decision.contact_opportunity_snapshot_id]
      requirement = requirements[snapshot_key(candidate)]

      case improvement_swap(
             candidate,
             requirement,
             requirements,
             policy,
             scarcity,
             now,
             state
           ) do
        {:ok, improved} -> improved
        :unchanged -> state
      end
    end)
  end

  defp improvement_swap(candidate, requirement, requirements, policy, scarcity, now, state) do
    removable =
      state.selected
      |> Enum.reject(&MapSet.member?(state.locked_ids, &1.contact_opportunity_snapshot_id))
      |> Enum.sort_by(fn snapshot ->
        decision = state.decisions[snapshot.contact_opportunity_snapshot_id]
        {decision.score, snapshot.contact_opportunity_snapshot_id}
      end)

    Enum.find_value(removable, :unchanged, fn current ->
      selected_without_current = Enum.reject(state.selected, &same_snapshot?(&1, current))

      with true <-
             Constraints.dynamic_failures(
               requirement,
               candidate,
               selected_without_current,
               requirements,
               policy
             ) == [],
           {candidate_score, candidate_score_document} <-
             Scoring.score(
               requirement,
               candidate,
               scarcity[requirement_key(requirement)],
               selected_without_current,
               policy,
               now
             ),
           current_decision <- state.decisions[current.contact_opportunity_snapshot_id],
           true <- candidate_score > current_decision.score,
           new_selected <- [candidate | selected_without_current],
           true <-
             protected_coverage_preserved?(
               current,
               candidate,
               state.selected,
               new_selected,
               requirements,
               policy
             ) do
        improved =
          state
          |> Map.put(:selected, new_selected)
          |> put_decision(
            current,
            :displaced,
            current_decision.score,
            current_decision.score_document,
            [],
            "replaced_by_local_improvement",
            "A bounded one-for-one replacement increased score without reducing coverage."
          )
          |> put_decision(
            candidate,
            :selected,
            candidate_score,
            candidate_score_document,
            [],
            "selected_by_local_improvement",
            "A bounded one-for-one replacement increased score without reducing coverage."
          )
          |> Map.update!(:improvement_replacements, &(&1 + 1))

        {:ok, improved}
      else
        _reason -> false
      end
    end)
  end

  defp protected_coverage_preserved?(
         removed,
         candidate,
         before,
         after_selection,
         requirements,
         policy
       ) do
    affected_keys =
      [snapshot_key(removed), snapshot_key(candidate)]
      |> Enum.uniq()

    Enum.all?(affected_keys, fn key ->
      requirement = requirements[key]
      before_coverage = requirement_coverage(requirement, before, policy)
      after_coverage = requirement_coverage(requirement, after_selection, policy)

      coverage_rank(after_coverage["state"]) >= coverage_rank(before_coverage["state"])
    end)
  end

  defp assign_ranks(state) do
    decisions =
      state.selected
      |> ordered_selected()
      |> Enum.with_index(1)
      |> Enum.reduce(state.decisions, fn {snapshot, rank}, decisions ->
        Map.update!(
          decisions,
          snapshot.contact_opportunity_snapshot_id,
          &Map.put(&1, :rank, rank)
        )
      end)

    %{state | decisions: decisions}
  end

  defp coverage(requirements, selected, policy) do
    requirements
    |> Map.values()
    |> Enum.sort_by(&{&1.contact_requirement_id, &1.version})
    |> Map.new(fn requirement ->
      {requirement.contact_requirement_id, requirement_coverage(requirement, selected, policy)}
    end)
  end

  defp requirement_coverage(requirement, selected, policy) do
    selected = Enum.filter(selected, &same_requirement?(&1, requirement))
    evaluation = RequirementEvaluator.evaluate_selection(requirement, selected)
    redundancy = redundancy_evaluation(requirement, selected, policy)
    satisfied = evaluation["satisfied"] and redundancy["satisfied"]

    state =
      cond do
        satisfied -> "satisfied"
        selected == [] -> "unsatisfied"
        true -> "partial"
      end

    %{
      "contact_requirement_id" => requirement.contact_requirement_id,
      "contact_requirement_version" => requirement.version,
      "state" => state,
      "satisfied" => satisfied,
      "selection" => evaluation,
      "redundancy" => redundancy,
      "selected_snapshot_ids" =>
        selected
        |> ordered_selected()
        |> Enum.map(& &1.contact_opportunity_snapshot_id)
    }
  end

  defp coverage_satisfied?(requirement, selected, policy),
    do: requirement_coverage(requirement, selected, policy)["satisfied"]

  defp redundancy_evaluation(requirement, selected, policy) do
    target = requirement.contact_count
    redundancy = policy.redundancy_document

    dimensions = %{
      "provider" =>
        dimension_evaluation(
          redundancy["distinct_provider_required"],
          target,
          Enum.map(selected, &Constraints.provider_id/1)
        ),
      "station" =>
        dimension_evaluation(
          redundancy["distinct_station_required"],
          target,
          Enum.map(selected, &Constraints.station_id/1)
        ),
      "service_pool" =>
        dimension_evaluation(
          redundancy["distinct_service_pool_required"],
          target,
          Enum.map(selected, &Constraints.service_pool_id/1)
        )
    }

    %{
      "satisfied" => Enum.all?(dimensions, fn {_name, result} -> result["satisfied"] end),
      "dimensions" => dimensions
    }
  end

  defp dimension_evaluation(false, _target, values) do
    %{
      "required" => false,
      "required_count" => 0,
      "distinct_count" => values |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length(),
      "satisfied" => true
    }
  end

  defp dimension_evaluation(true, target, values) do
    count = values |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length()

    %{
      "required" => true,
      "required_count" => target,
      "distinct_count" => count,
      "satisfied" => count >= target
    }
  end

  defp scarcity(feasible) do
    feasible
    |> Enum.frequencies_by(&snapshot_key/1)
  end

  defp demand_order(requirements, scarcity) do
    requirements
    |> Map.values()
    |> Enum.sort_by(fn requirement ->
      {
        DateTime.to_unix(requirement.latest_end, :microsecond),
        priority_order(requirement.priority),
        Map.get(scarcity, requirement_key(requirement), 0),
        requirement.contact_requirement_id,
        requirement.version
      }
    end)
  end

  defp priority_order(:critical), do: 0
  defp priority_order(:high), do: 1
  defp priority_order(:routine), do: 2

  defp put_ineligible(state, snapshot, failures) do
    put_decision(
      state,
      snapshot,
      :ineligible,
      0,
      %{"scale" => 1_000, "components" => %{}, "total" => 0},
      failures,
      "ineligible",
      "This opportunity failed one or more isolated hard constraints."
    )
  end

  defp put_decision(
         state,
         snapshot,
         disposition,
         score,
         score_document,
         failures,
         code,
         message
       ) do
    decision = %{
      contact_opportunity_snapshot_id: snapshot.contact_opportunity_snapshot_id,
      disposition: disposition,
      score: score,
      rank: nil,
      hard_constraint_document: %{
        "satisfied" => failures == [],
        "failures" => failures
      },
      score_document: score_document,
      explanation_document: %{
        "code" => code,
        "message" => message,
        "contact_requirement_id" => snapshot.contact_requirement_id,
        "contact_requirement_version" => snapshot.contact_requirement_version
      }
    }

    put_in(
      state,
      [:decisions, snapshot.contact_opportunity_snapshot_id],
      decision
    )
  end

  defp ordered_selected(selected) do
    Enum.sort_by(selected, fn snapshot ->
      {snapshot.starts_at, snapshot.ends_at, snapshot.contact_opportunity_snapshot_id}
    end)
  end

  defp ordered_decisions(decisions) do
    decisions
    |> Map.values()
    |> Enum.sort_by(fn decision ->
      {
        decision.rank || 2_147_483_647,
        disposition_order(decision.disposition),
        -decision.score,
        decision.contact_opportunity_snapshot_id
      }
    end)
  end

  defp disposition_order(:locked), do: 0
  defp disposition_order(:selected), do: 1
  defp disposition_order(:displaced), do: 2
  defp disposition_order(:ineligible), do: 3

  defp selected_with_lock_count(state, selected) do
    %{
      "selected_snapshot_count" => length(selected),
      "locked_snapshot_count" =>
        Enum.count(selected, fn snapshot ->
          MapSet.member?(state.locked_ids, snapshot.contact_opportunity_snapshot_id)
        end)
    }
  end

  defp coverage_rank("satisfied"), do: 2
  defp coverage_rank("partial"), do: 1
  defp coverage_rank("unsatisfied"), do: 0

  defp requirement_key(requirement),
    do: {requirement.contact_requirement_id, requirement.version}

  defp snapshot_key(snapshot),
    do: {snapshot.contact_requirement_id, snapshot.contact_requirement_version}

  defp same_requirement?(snapshot, requirement),
    do: snapshot_key(snapshot) == requirement_key(requirement)

  defp same_snapshot?(left, right),
    do: left.contact_opportunity_snapshot_id == right.contact_opportunity_snapshot_id
end
