defmodule Cadence.ContactPlanning.FleetOptimizer do
  @moduledoc """
  Pure deterministic bounded allocator for exact Requirement and opportunity snapshots.

  Hard constraints decide feasibility. Integer score components only rank feasible
  alternatives and are retained with each explainable decision.
  """

  alias Cadence.ContactPlanning.{
    ContactGaps,
    ContactOpportunitySnapshot,
    ContactRequirementVersion,
    ContentHash,
    FleetOptimizationResult,
    FleetOptimizer.Constraints,
    FleetOptimizer.Scoring,
    FleetOptimizer.SelectionIndex,
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
         {:ok, initial} <-
           initialize(
             snapshots,
             requirements,
             policy,
             locked_ids,
             now,
             Keyword.get(opts, :occupied, [])
           ) do
      finish_optimization(initial, requirements, policy, now, length(snapshots), locked_ids)
    end
  end

  def optimize(_requirements, _snapshots, _policy, _opts),
    do: {:error, :invalid_fleet_optimizer_inputs}

  @doc "Optimizes a bounded stream of stored snapshots without retaining the full fleet in memory."
  @spec optimize_stream(
          [ContactRequirementVersion.t()],
          Enumerable.t(),
          FleetPlanningPolicyVersion.t(),
          keyword()
        ) :: {:ok, FleetOptimizationResult.t()} | {:error, term()}
  def optimize_stream(requirements, snapshots, %FleetPlanningPolicyVersion{} = policy, opts \\ [])
      when is_list(requirements) and is_list(opts) do
    now = opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)
    locked_commitments = Keyword.get(opts, :locked_commitments, [])

    locked_ids =
      opts
      |> Keyword.get(:locked_snapshot_ids, [])
      |> MapSet.new()
      |> MapSet.union(MapSet.new(locked_commitments, & &1.contact_opportunity_snapshot_id))

    with {:ok, requirements} <- normalize_requirements(requirements, policy),
         {:ok, initial, snapshot_count} <-
           initialize_stream(
             Stream.concat(snapshots, locked_commitments),
             requirements,
             policy,
             locked_ids,
             now,
             Keyword.get(opts, :occupied, [])
           ) do
      finish_optimization(initial, requirements, policy, now, snapshot_count, locked_ids)
    end
  end

  defp finish_optimization(initial, requirements, policy, now, snapshot_count, locked_ids) do
    scarcity = initial.feasible_counts

    state =
      try do
        requirements
        |> demand_order(scarcity)
        |> Enum.reduce(initial, fn requirement, state ->
          allocate_requirement(requirement, scarcity, policy, now, state)
        end)
      after
        :ets.delete(initial.feasible_table)
      end
      |> Map.delete(:feasible_table)
      |> improve_locally(requirements, policy, scarcity, now)
      |> assign_ranks()

    selected = ordered_selected(state.selected)
    coverage = coverage(requirements, state.selection_index, policy)

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
         "considered_snapshot_count" => snapshot_count,
         "selected_snapshot_count" => length(selected),
         "locked_snapshot_count" => MapSet.size(locked_ids)
       }
     }}
  end

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

  defp initialize(snapshots, requirements, policy, locked_ids, now, occupied) do
    initial = initial_state(policy, locked_ids)

    snapshots
    |> Enum.reduce_while(
      {:ok, initial},
      &initialize_snapshot(&1, &2, requirements, policy, locked_ids, now, occupied)
    )
    |> case do
      {:ok, state} ->
        {:ok, state}

      {:error, reason} ->
        :ets.delete(initial.feasible_table)
        {:error, reason}
    end
  end

  defp initialize_stream(snapshots, requirements, policy, locked_ids, now, occupied) do
    initial = initial_state(policy, locked_ids)
    seen = :ets.new(:fleet_optimizer_seen, [:set, :private])

    context = %{
      requirements: requirements,
      policy: policy,
      locked_ids: locked_ids,
      now: now,
      occupied: occupied,
      seen: seen
    }

    result =
      try do
        Enum.reduce_while(snapshots, {:ok, initial, 0}, fn snapshot, {:ok, state, count} ->
          accept_stream_snapshot(snapshot, state, count, context)
        end)
      after
        :ets.delete(seen)
      end

    case result do
      {:ok, state, count} ->
        if MapSet.subset?(locked_ids, state.found_locked_ids) do
          {:ok, state, count}
        else
          :ets.delete(initial.feasible_table)
          {:error, :fleet_optimizer_locked_snapshot_not_found}
        end

      {:error, reason} ->
        :ets.delete(initial.feasible_table)
        {:error, reason}
    end
  end

  defp accept_stream_snapshot(snapshot, state, count, context) do
    case validate_stream_snapshot(snapshot, context.policy, context.seen) do
      :new ->
        initialize_stream_snapshot(snapshot, state, count, context)

      :duplicate ->
        {:cont, {:ok, state, count}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp initialize_stream_snapshot(snapshot, state, count, context) do
    case initialize_snapshot(
           snapshot,
           {:ok, state},
           context.requirements,
           context.policy,
           context.locked_ids,
           context.now,
           context.occupied
         ) do
      {:cont, {:ok, updated}} ->
        found =
          if MapSet.member?(context.locked_ids, snapshot.contact_opportunity_snapshot_id),
            do: MapSet.put(updated.found_locked_ids, snapshot.contact_opportunity_snapshot_id),
            else: updated.found_locked_ids

        {:cont, {:ok, %{updated | found_locked_ids: found}, count + 1}}

      {:halt, error} ->
        {:halt, error}
    end
  end

  defp validate_stream_snapshot(%ContactOpportunitySnapshot{} = snapshot, policy, seen) do
    if snapshot.organization_id != policy.organization_id or
         snapshot.mission_id != policy.mission_id do
      {:error, :fleet_optimizer_scope_mismatch}
    else
      id = snapshot.contact_opportunity_snapshot_id

      case :ets.lookup(seen, id) do
        [] ->
          :ets.insert(seen, {id, snapshot.content_sha256})
          :new

        [{^id, hash}] when hash == snapshot.content_sha256 ->
          :duplicate

        [_conflict] ->
          {:error, {:fleet_optimizer_snapshot_identity_collision, id}}
      end
    end
  end

  defp validate_stream_snapshot(_snapshot, _policy, _seen),
    do: {:error, :invalid_fleet_optimizer_snapshot}

  defp initial_state(policy, locked_ids) do
    %{
      feasible_table: :ets.new(:fleet_optimizer_feasible, [:bag, :private]),
      feasible_counts: %{},
      selected: [],
      selection_index: SelectionIndex.new(),
      locked_ids: locked_ids,
      found_locked_ids: MapSet.new(),
      decisions: %{},
      score_documents: %{},
      improvement_limit: policy.scoring_document["local_improvement_limit"],
      top_displaced: :gb_sets.new(),
      greedy_evaluations: 0,
      improvement_evaluations: 0,
      improvement_replacements: 0
    }
  end

  defp initialize_snapshot(
         snapshot,
         {:ok, state},
         requirements,
         policy,
         locked_ids,
         now,
         occupied
       ) do
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

      {requirement, true} ->
        {:cont, {:ok, add_locked_snapshot(state, snapshot, requirement)}}

      {requirement, false} ->
        case held_by_single_booking(snapshot, occupied) do
          nil -> {:cont, {:ok, classify_snapshot(state, requirement, snapshot, policy, now)}}
          failure -> {:cont, {:ok, put_ineligible(state, snapshot, [failure])}}
        end
    end
  end

  # DECISIONS #78: a live single booking is fixed occupancy. An opportunity overlapping one of the
  # same spacecraft, or of another spacecraft on the same antenna, can't be planned.
  defp held_by_single_booking(_snapshot, []), do: nil

  defp held_by_single_booking(snapshot, occupied) do
    spacecraft = (snapshot.route_binding_document || %{})["spacecraft_id"]
    antenna = (snapshot.normalized_opportunity_document || %{})["antenna_or_service_pool_ref"]

    occupied
    |> Enum.filter(fn o ->
      DateTime.before?(o.starts_at, snapshot.ends_at) and
        DateTime.after?(o.ends_at, snapshot.starts_at)
    end)
    |> Enum.find_value(fn o ->
      cond do
        o.spacecraft_id == spacecraft -> held(o, "same_spacecraft")
        is_binary(antenna) and o.antenna_ref == antenna -> held(o, "same_antenna")
        true -> nil
      end
    end)
  end

  defp held(occupied, reason),
    do: %{
      "code" => "held_by_single_booking",
      "message" => "A pass booked outside any plan holds this window.",
      "reservation_id" => occupied.reservation_id,
      "reason" => reason
    }

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

  defp add_locked_snapshot(state, snapshot, requirement) do
    state
    |> Map.update!(:selected, &[snapshot | &1])
    |> Map.update!(:selection_index, &SelectionIndex.add(&1, snapshot, requirement))
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
      [] ->
        key = snapshot_key(snapshot)
        :ets.insert(state.feasible_table, {key, snapshot})
        Map.update!(state, :feasible_counts, &Map.update(&1, key, 1, fn count -> count + 1 end))

      failures ->
        put_ineligible(state, snapshot, failures)
    end
  end

  defp allocate_requirement(requirement, scarcity, policy, now, state) do
    key = requirement_key(requirement)

    candidates =
      state.feasible_table
      |> :ets.lookup(key)
      |> Enum.map(&elem(&1, 1))

    :ets.delete(state.feasible_table, key)

    candidates =
      Enum.reject(candidates, &Map.has_key?(state.decisions, &1.contact_opportunity_snapshot_id))

    allocate_candidates(
      requirement,
      candidates,
      scarcity[requirement_key(requirement)],
      policy,
      now,
      state
    )
  end

  defp allocate_candidates(_requirement, [], _scarcity, _policy, _now, state), do: state

  defp allocate_candidates(requirement, candidates, scarcity, policy, now, state) do
    {scored, score_documents} =
      candidates
      |> Enum.map_reduce(state.score_documents, fn snapshot, cache ->
        {score, document, cache} =
          Scoring.score(
            requirement,
            snapshot,
            scarcity,
            state.selection_index,
            policy,
            now,
            cache
          )

        {{snapshot, score, document}, cache}
      end)

    scored = order_candidates(scored, requirement, state.selection_index)
    covered? = coverage_satisfied?(requirement, state.selection_index, policy)

    allocate_scored(
      scored,
      requirement,
      scarcity,
      policy,
      now,
      %{state | score_documents: score_documents},
      covered?
    )
  end

  defp allocate_scored([], _requirement, _scarcity, _policy, _now, state, _covered?), do: state

  defp allocate_scored(
         [{snapshot, score, score_document} | remaining],
         requirement,
         scarcity,
         policy,
         now,
         state,
         covered?
       ) do
    selected_count = state.selection_index.count
    state = Map.update!(state, :greedy_evaluations, &(&1 + 1))

    state =
      cond do
        covered? ->
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

        extra_without_gap_gain?(requirement, snapshot, state.selection_index) ->
          put_decision(
            state,
            snapshot,
            :displaced,
            score,
            score_document,
            [],
            "does_not_shorten_gap",
            "The contact count is met and this opportunity doesn't shorten the longest gap."
          )

        true ->
          allocate_candidate(
            state,
            requirement,
            snapshot,
            score,
            score_document,
            policy
          )
      end

    if state.selection_index.count == selected_count do
      allocate_scored(remaining, requirement, scarcity, policy, now, state, covered?)
    else
      # A selection changes fragmentation and diversity, so the remaining scores need a refresh.
      candidates = Enum.map(remaining, &elem(&1, 0))
      allocate_candidates(requirement, candidates, scarcity, policy, now, state)
    end
  end

  # Without a gap limit, the order is unchanged: score, then AOS, then id. With one (DECISIONS
  # #74), the pick that leaves the requirement's shortest longest-gap comes first.
  defp order_candidates(scored, %{max_gap_seconds: nil}, _selected),
    do:
      Enum.sort_by(scored, fn {snapshot, score, _document} ->
        {-score, snapshot.starts_at, snapshot.contact_opportunity_snapshot_id}
      end)

  defp order_candidates(scored, requirement, selected) do
    own = SelectionIndex.for_requirement(selected, requirement)

    Enum.sort_by(scored, fn {snapshot, score, _document} ->
      {requirement_gap(requirement, [snapshot | own]), -score, snapshot.starts_at,
       snapshot.contact_opportunity_snapshot_id}
    end)
  end

  # Past the contact count, a limited requirement takes a pick only if it shortens its gap.
  defp extra_without_gap_gain?(%{max_gap_seconds: nil}, _snapshot, _selected), do: false

  defp extra_without_gap_gain?(requirement, snapshot, selected) do
    own = SelectionIndex.for_requirement(selected, requirement)

    length(own) >= requirement.contact_count and
      requirement_gap(requirement, [snapshot | own]) >= requirement_gap(requirement, own)
  end

  # DECISIONS #74: a score swap may not lengthen a limited requirement's longest gap.
  defp gaps_not_longer?(touched, before, after_selection, requirements) do
    touched
    |> Enum.map(&requirements[snapshot_key(&1)])
    |> Enum.uniq()
    |> Enum.reject(&(is_nil(&1) or is_nil(&1.max_gap_seconds)))
    |> Enum.all?(fn requirement ->
      own = fn selection -> Enum.filter(selection, &same_requirement?(&1, requirement)) end

      requirement_gap(requirement, own.(after_selection)) <=
        requirement_gap(requirement, own.(before))
    end)
  end

  defp requirement_gap(requirement, passes),
    do: ContactGaps.longest(passes, requirement.earliest_start, requirement.latest_end).seconds

  defp allocate_candidate(
         state,
         requirement,
         snapshot,
         score,
         score_document,
         policy
       ) do
    case Constraints.dynamic_failures(
           requirement,
           snapshot,
           state.selection_index,
           policy
         ) do
      [] ->
        state
        |> Map.update!(:selected, &[snapshot | &1])
        |> Map.update!(:selection_index, &SelectionIndex.add(&1, snapshot, requirement))
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
    candidates =
      state.top_displaced
      |> :gb_sets.to_list()
      |> Enum.map(fn {_negative_score, _id, snapshot} -> snapshot end)

    excess =
      Map.filter(state.selection_index.by_requirement, fn {_key, snapshots} ->
        match?([_, _ | _], snapshots)
      end)

    {state, _excess} =
      Enum.reduce(candidates, {state, excess}, fn candidate, {state, excess} ->
        state = Map.update!(state, :improvement_evaluations, &(&1 + 1))
        key = snapshot_key(candidate)
        requirement = requirements[key]

        removable =
          excess
          |> Map.put(key, SelectionIndex.for_requirement(state.selection_index, requirement))
          |> Map.values()
          |> List.flatten()
          |> Enum.reject(&MapSet.member?(state.locked_ids, &1.contact_opportunity_snapshot_id))
          |> Enum.sort_by(fn snapshot ->
            decision = state.decisions[snapshot.contact_opportunity_snapshot_id]
            {decision.score, snapshot.contact_opportunity_snapshot_id}
          end)

        case improvement_swap(
               removable,
               candidate,
               requirement,
               requirements,
               policy,
               scarcity,
               now,
               state
             ) do
          {:ok, improved, removed_key} ->
            excess = refresh_excess(excess, improved.selection_index, [key, removed_key])
            {improved, excess}

          :unchanged ->
            {state, excess}
        end
      end)

    state
  end

  defp refresh_excess(excess, selection, keys) do
    Enum.reduce(keys, excess, fn key, excess ->
      case selection.by_requirement[key] do
        [_, _ | _] = snapshots -> Map.put(excess, key, snapshots)
        _ -> Map.delete(excess, key)
      end
    end)
  end

  defp improvement_swap(
         removable,
         candidate,
         requirement,
         requirements,
         policy,
         scarcity,
         now,
         state
       ) do
    Enum.find_value(removable, :unchanged, fn current ->
      current_requirement = requirements[snapshot_key(current)]

      without_current =
        SelectionIndex.remove(state.selection_index, current, current_requirement)

      with true <-
             Constraints.dynamic_failures(
               requirement,
               candidate,
               without_current,
               policy
             ) == [],
           {candidate_score, candidate_score_document} <-
             Scoring.score(
               requirement,
               candidate,
               scarcity[requirement_key(requirement)],
               without_current,
               policy,
               now
             ),
           current_decision <- state.decisions[current.contact_opportunity_snapshot_id],
           true <- candidate_score > current_decision.score,
           selected_without_current <-
             Enum.reject(state.selected, &same_snapshot?(&1, current)),
           new_selected <- [candidate | selected_without_current],
           true <-
             protected_coverage_preserved?(
               current,
               candidate,
               state.selected,
               new_selected,
               requirements,
               policy
             ),
           true <-
             gaps_not_longer?([current, candidate], state.selected, new_selected, requirements) do
        improved =
          state
          |> Map.put(:selected, new_selected)
          |> Map.put(
            :selection_index,
            SelectionIndex.add(without_current, candidate, requirement)
          )
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

        {:ok, improved, snapshot_key(current)}
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
      {requirement.contact_requirement_id,
       requirement_coverage(
         requirement,
         SelectionIndex.for_requirement(selected, requirement),
         policy
       )}
    end)
  end

  defp requirement_coverage(requirement, selected, policy) do
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

  defp coverage_satisfied?(requirement, selected, policy) do
    case SelectionIndex.for_requirement(selected, requirement) do
      [] ->
        false

      own ->
        RequirementEvaluator.evaluate_selection(requirement, own)["satisfied"] and
          redundancy_evaluation(requirement, own, policy)["satisfied"]
    end
  end

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
    {score_document, score_sha256, state} = shared_score_document(state, score_document)

    decision = %{
      contact_opportunity_snapshot_id: snapshot.contact_opportunity_snapshot_id,
      disposition: disposition,
      score: score,
      rank: nil,
      hard_constraint_document: constraint_document(failures),
      score_document: score_document,
      score_document_sha256: score_sha256,
      explanation_document: %{
        "code" => code,
        "message" => message,
        "contact_requirement_id" => snapshot.contact_requirement_id,
        "contact_requirement_version" => snapshot.contact_requirement_version
      }
    }

    state =
      put_in(
        state,
        [:decisions, snapshot.contact_opportunity_snapshot_id],
        decision
      )

    track_displaced(state, snapshot, disposition, score)
  end

  defp track_displaced(state, snapshot, :displaced, score) do
    candidate = {-score, snapshot.contact_opportunity_snapshot_id, snapshot}
    top = :gb_sets.add(candidate, state.top_displaced)

    top =
      if :gb_sets.size(top) > state.improvement_limit,
        do: :gb_sets.del_element(:gb_sets.largest(top), top),
        else: top

    %{state | top_displaced: top}
  end

  defp track_displaced(state, _snapshot, _disposition, _score), do: state

  defp shared_score_document(state, %{"components" => components} = document) do
    case Map.fetch(state.score_documents, components) do
      {:ok, {shared, sha256}} ->
        {shared, sha256, state}

      :error ->
        sha256 = ContentHash.sha256(document)
        {document, sha256, put_in(state, [:score_documents, components], {document, sha256})}
    end
  end

  defp shared_score_document(state, document),
    do: {document, ContentHash.sha256(document), state}

  defp constraint_document([]), do: %{"satisfied" => true, "failures" => []}
  defp constraint_document(failures), do: %{"satisfied" => false, "failures" => failures}

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
