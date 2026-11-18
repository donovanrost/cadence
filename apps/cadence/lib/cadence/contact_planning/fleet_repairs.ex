defmodule Cadence.ContactPlanning.FleetRepairs do
  @moduledoc """
  Exact-source repair planning that preserves successful or uncertain commitments.

  A repair never mutates or compensates the source Plan. It creates a new Fleet
  Planning Run and records immutable lock evidence for the source commitments
  that the optimizer must plan around.
  """

  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactPlans,
    FleetPlanner,
    FleetPlanningPolicies,
    FleetPlanningRun,
    FleetPlanningRuns,
    RepairChain,
    RepairPairing
  }

  alias Cadence.Contacts.SingleBookings

  @repairable_plan_states [:executing, :partially_reserved, :failed]

  @type source :: %{
          required(:run) => struct(),
          required(:plan) => struct(),
          required(:plan_version) => struct(),
          required(:locked_commitments) => [struct()],
          required(:chain) => RepairChain.t(),
          required(:covered) => %{binary() => binary()},
          required(:repair_attempt) => pos_integer()
        }

  @spec start(
          Scope.t(),
          binary(),
          binary(),
          binary(),
          pos_integer(),
          map(),
          keyword()
        ) :: {:ok, FleetPlanningRun.t(), [struct()]} | {:error, term()}
  def start(
        %Scope{} = scope,
        mission_id,
        source_run_id,
        source_plan_id,
        source_plan_version,
        attrs,
        opts \\ []
      )
      when is_binary(mission_id) and is_binary(source_run_id) and
             is_binary(source_plan_id) and is_integer(source_plan_version) and
             source_plan_version > 0 and is_map(attrs) and is_list(opts) do
    with {:ok, source} <-
           source(
             scope.organization_id,
             mission_id,
             source_run_id,
             source_plan_id,
             source_plan_version
           ),
         {:ok, _policy, policy} <-
           FleetPlanningPolicies.fetch_active(scope.organization_id, mission_id),
         :ok <- repair_attempt_allowed(source.repair_attempt, policy),
         :ok <- repair_horizon_allowed(attrs, policy),
         run_attrs <-
           repair_run_attrs(
             attrs,
             source,
             source_run_id,
             source_plan_id,
             source_plan_version
           ) do
      FleetPlanner.start(
        scope,
        mission_id,
        run_attrs,
        Keyword.put(opts, :materialize_templates, false)
      )
    end
  end

  @spec repair(
          Scope.t(),
          binary(),
          binary(),
          binary(),
          pos_integer(),
          map(),
          keyword()
        ) :: {:ok, map()} | {:error, term()}
  def repair(
        %Scope{} = scope,
        mission_id,
        source_run_id,
        source_plan_id,
        source_plan_version,
        attrs,
        opts \\ []
      ) do
    with {:ok, run, _refs} <-
           start(
             scope,
             mission_id,
             source_run_id,
             source_plan_id,
             source_plan_version,
             attrs,
             opts
           ) do
      FleetPlanner.run(scope, mission_id, run.fleet_planning_run_id, opts)
    end
  end

  @doc "The attempt number a repair of `run`'s chain would be (1 for a first repair; U76's header)."
  @spec next_attempt(binary(), binary(), struct()) :: {:ok, pos_integer()} | {:error, term()}
  def next_attempt(organization_id, mission_id, run),
    do: repair_attempt(organization_id, mission_id, run)

  @spec source(binary(), binary(), binary(), binary(), pos_integer()) ::
          {:ok, source()} | {:error, term()}
  def source(organization_id, mission_id, run_id, plan_id, plan_version) do
    with {:ok, run} <- FleetPlanningRuns.fetch(organization_id, mission_id, run_id),
         {:ok, plan, current_version} <- ContactPlans.fetch(organization_id, mission_id, plan_id),
         :ok <- exact_source(run, plan, current_version, plan_version),
         {:ok, chain} <- RepairChain.load(organization_id, mission_id, plan_id),
         :ok <- repairable(plan, chain),
         {:ok, attempt} <- repair_attempt(organization_id, mission_id, run),
         covered = covered_by_single_bookings(organization_id, mission_id, run, chain),
         locked <- source_locked_commitments(plan, chain, covered) do
      {:ok,
       %{
         run: run,
         plan: plan,
         plan_version: current_version,
         locked_commitments: locked,
         chain: chain,
         covered: covered,
         repair_attempt: attempt
       }}
    end
  end

  # qa #30: the day's current bookings across the repair chain (root plan plus applied
  # repairs) are locked, so bookings an earlier repair made aren't re-sent, and a pass whose
  # booking was lost is re-planned even when a later plan had locked it.
  # Also kept (review R3): a pass a chain version locks that no item in the chain booked, so
  # nothing says it was lost (a lock carried from elsewhere). A locked pass whose booking is in
  # the chain follows that booking: live stays locked, lost is re-planned.
  # DECISIONS #56: a lost booking a live single booking covers is held like a current
  # booking, so the planner counts its need as met and doesn't book it again. Its snapshot can
  # only be held when the source plan selected it (the planner validates locks against it).
  defp source_locked_commitments(plan, chain, covered) do
    selected =
      plan.organization_id
      |> ContactPlans.selected_snapshots(
        plan.mission_id,
        plan.contact_plan_id,
        chain.versions[plan.contact_plan_id]
      )
      |> MapSet.new(& &1.contact_opportunity_snapshot_id)

    covered_items =
      Enum.filter(
        chain.items,
        &(Map.has_key?(covered, RepairChain.lost_key(&1)) and
            MapSet.member?(selected, &1.contact_opportunity_snapshot_id))
      )

    live =
      chain
      |> RepairChain.live_items()
      |> Enum.concat(covered_items)
      |> MapSet.new(&{&1.contact_plan_id, &1.contact_opportunity_snapshot_id})

    booked = MapSet.new(chain.items, & &1.contact_opportunity_snapshot_id)

    chain.plans
    |> Enum.flat_map(fn plan_id ->
      version = chain.versions[plan_id]
      held = held_locks(plan, plan_id, version, booked)

      plan.organization_id
      |> ContactPlans.selected_snapshots(plan.mission_id, plan_id, version)
      |> Enum.filter(fn snapshot ->
        id = snapshot.contact_opportunity_snapshot_id
        MapSet.member?(live, {plan_id, id}) or MapSet.member?(held, id)
      end)
    end)
    |> Enum.uniq_by(& &1.contact_opportunity_snapshot_id)
    |> Enum.sort_by(&{&1.starts_at, &1.contact_opportunity_snapshot_id})
  end

  defp covered_by_single_bookings(organization_id, mission_id, run, chain) do
    case SingleBookings.live(organization_id, mission_id, run.horizon_start, run.horizon_end) do
      [] ->
        %{}

      singles ->
        chain
        |> RepairChain.lost_booking_inputs(organization_id, mission_id)
        |> RepairPairing.cover(singles)
    end
  end

  defp held_locks(plan, plan_id, version, booked) do
    case ContactPlans.fetch_version(plan.organization_id, plan.mission_id, plan_id, version) do
      {:ok, %{locked_snapshot_ids: ids}} -> ids |> MapSet.new() |> MapSet.difference(booked)
      _missing -> MapSet.new()
    end
  end

  defp exact_source(run, plan, current_version, requested_version) do
    cond do
      run.candidate_contact_plan_id != plan.contact_plan_id or
          run.candidate_contact_plan_version != requested_version ->
        {:error, :fleet_repair_source_plan_not_run_candidate}

      current_version.version != requested_version ->
        {:error, :fleet_repair_source_plan_version_changed}

      run.lifecycle_state not in [:completed, :partial] ->
        {:error, :fleet_repair_source_run_not_complete}

      true ->
        :ok
    end
  end

  # A day is repairable while its chain has lost bookings, whatever the head plan reads.
  defp repairable(%{lifecycle_state: state}, _chain) when state in @repairable_plan_states,
    do: :ok

  defp repairable(_plan, chain) do
    if RepairChain.lost_bookings(chain) == [],
      do: {:error, :fleet_repair_source_plan_not_repairable},
      else: :ok
  end

  defp repair_attempt(organization_id, mission_id, run) do
    repair_depth(organization_id, mission_id, run, 1, MapSet.new())
  end

  defp repair_depth(_organization_id, _mission_id, %{trigger_kind: trigger}, depth, _seen)
       when trigger != :repair,
       do: {:ok, depth}

  defp repair_depth(organization_id, mission_id, run, depth, seen) do
    cond do
      MapSet.member?(seen, run.fleet_planning_run_id) ->
        {:error, :fleet_repair_source_cycle}

      depth > 100 ->
        {:error, :fleet_repair_source_depth_exceeded}

      true ->
        seen = MapSet.put(seen, run.fleet_planning_run_id)

        case FleetPlanningRuns.fetch(
               organization_id,
               mission_id,
               run.source_fleet_planning_run_id
             ) do
          {:ok, parent} -> repair_depth(organization_id, mission_id, parent, depth + 1, seen)
          {:error, _reason} -> {:error, :fleet_repair_source_run_not_found}
        end
    end
  end

  defp repair_attempt_allowed(attempt, policy) do
    if attempt <= policy.automation_repair_document["max_repair_attempts"],
      do: :ok,
      else: {:error, :fleet_repair_attempt_limit_exceeded}
  end

  defp repair_horizon_allowed(attrs, policy) do
    with {:ok, starts_at} <- datetime(value(attrs, :horizon_start)),
         {:ok, ends_at} <- datetime(value(attrs, :horizon_end)),
         seconds when seconds > 0 <- DateTime.diff(ends_at, starts_at, :second) do
      if seconds <= policy.automation_repair_document["repair_horizon_seconds"],
        do: :ok,
        else: {:error, :fleet_repair_horizon_exceeded}
    else
      _reason -> {:error, :fleet_repair_horizon_invalid}
    end
  end

  defp repair_run_attrs(attrs, source, source_run_id, source_plan_id, source_plan_version) do
    requirements = source.plan_version.requirement_refs_document["requirements"]

    attrs
    |> Map.put(:trigger_kind, :repair)
    |> Map.put(:source_fleet_planning_run_id, source_run_id)
    |> Map.put(:source_contact_plan_id, source_plan_id)
    |> Map.put(:source_contact_plan_version, source_plan_version)
    |> Map.put(:requirement_refs, requirements)
    |> Map.put(
      :occupied_document,
      SingleBookings.occupancy_document(
        source.plan.organization_id,
        source.plan.mission_id,
        attrs
      )
    )
    |> Map.put(:repair_input_document, %{
      "repair_attempt" => source.repair_attempt,
      "source_plan_content_sha256" => source.plan_version.content_sha256,
      # qa #30: what this repair replaces, paired with its new passes at materialization.
      # Lost bookings a single booking covers (#56) are recorded apart and aren't replaced.
      "lost_bookings" =>
        source.chain
        |> RepairChain.lost_booking_inputs(source.plan.organization_id, source.plan.mission_id)
        |> Enum.reject(&Map.has_key?(source.covered, &1["key"])),
      "covered" => source.covered,
      "locked_commitments" =>
        Enum.map(source.locked_commitments, fn snapshot ->
          %{
            "contact_opportunity_snapshot_id" => snapshot.contact_opportunity_snapshot_id,
            "content_sha256" => snapshot.content_sha256,
            "contact_planning_run_id" => snapshot.contact_planning_run_id
          }
        end)
    })
  end

  defp datetime(%DateTime{} = value), do: {:ok, DateTime.truncate(value, :microsecond)}

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed, _offset} -> {:ok, DateTime.truncate(parsed, :microsecond)}
      _other -> {:error, :invalid_datetime}
    end
  end

  defp datetime(_value), do: {:error, :invalid_datetime}

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
