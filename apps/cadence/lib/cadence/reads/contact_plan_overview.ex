defmodule Cadence.Reads.ContactPlanOverview do
  @moduledoc """
  Contact plan reads for the console scheduling screens (K1/K2): the plans
  list (S6), one plan version with totals and passes, and demand per
  spacecraft (S2) from the version's persisted coverage. Callers authorize
  first.

  A plan's day window is derived from its selected passes (the earliest start
  and the latest end), since plans don't store a horizon.
  """

  alias Cadence.Accounts
  alias Cadence.Comms.StationRefs

  alias Cadence.ContactPlanning.{
    ContactOpportunitySnapshot,
    ContactPlan,
    ContactPlanVersion,
    FleetPlanningRuns,
    PlanSupersession,
    StationConflicts
  }

  alias Cadence.Management.Contacts

  @list_cap 100

  @spec list(binary(), binary(), map()) :: [map()]
  def list(organization_id, mission_id, filters) do
    organization_id
    |> Contacts.list_plans(mission_id, list_opts(filters))
    |> Enum.take(@list_cap)
    |> then(fn plans ->
      ids = Enum.map(plans, fn {plan, _} -> plan.contact_plan_id end)
      superseded = PlanSupersession.check_many(organization_id, mission_id, plans)
      repairs = FleetPlanningRuns.repairs_for(organization_id, mission_id, ids)

      Enum.map(plans, fn {plan, _version} = pair ->
        {pair, Map.get(superseded, plan.contact_plan_id), Map.get(repairs, plan.contact_plan_id)}
      end)
    end)
    |> Enum.map(fn {{plan, version}, superseded, repair_of} ->
      passes =
        Contacts.selected_opportunities(
          organization_id,
          mission_id,
          plan.contact_plan_id,
          version.version
        )

      plan |> summary(version, passes, superseded) |> Map.put(:repair_of, repair_of)
    end)
    |> Enum.filter(&on_day?(&1, filters[:day]))
  end

  @doc "One plan at its current (or given) version, with totals and its selected passes."
  @spec plan(binary(), binary(), binary(), pos_integer() | nil) ::
          {:ok, map()} | {:error, :plan_not_found}
  def plan(organization_id, mission_id, plan_id, version_number \\ nil) do
    with {:ok, %ContactPlan{} = plan, current} <-
           Contacts.fetch_plan(organization_id, mission_id, plan_id),
         {:ok, %ContactPlanVersion{} = version} <-
           version(organization_id, mission_id, plan, current, version_number) do
      passes =
        Contacts.selected_opportunities(organization_id, mission_id, plan_id, version.version)

      stations = StationRefs.index(organization_id, mission_id)
      availability = StationConflicts.check(organization_id, mission_id, passes)
      conflicts = conflicts(version) ++ availability.conflicts
      superseded = PlanSupersession.check(organization_id, mission_id, plan, version)

      repair_of =
        FleetPlanningRuns.repairs_for(organization_id, mission_id, [plan_id])[plan_id]

      summary = plan |> summary(version, passes, superseded) |> Map.put(:repair_of, repair_of)

      {:ok,
       summary
       |> Map.merge(%{
         counts: %{summary.counts | conflicts: length(conflicts)},
         ready_to_approve: summary.ready_to_approve and availability.conflicts == [],
         passes: Enum.map(passes, &pass(&1, version, stations)),
         demand: demand(organization_id, mission_id, version),
         unmet: unmet(organization_id, mission_id, version),
         conflicts: conflicts,
         at_risk: availability.at_risk
       })}
    else
      _missing -> {:error, :plan_not_found}
    end
  end

  @doc "Per-spacecraft rule evaluation from a plan version's coverage, plus the rules."
  @spec demand(binary(), binary(), ContactPlanVersion.t()) :: map()
  def demand(organization_id, mission_id, %ContactPlanVersion{} = version) do
    evaluations = (version.coverage_document || %{})["requirements"] || []

    rules =
      Enum.flat_map(evaluations, fn evaluation ->
        case Contacts.fetch_requirement_version(
               organization_id,
               mission_id,
               evaluation["contact_requirement_id"],
               evaluation["contact_requirement_version"]
             ) do
          {:ok, requirement} -> [{requirement, evaluation}]
          _missing -> []
        end
      end)

    spacecraft =
      rules
      |> Enum.group_by(fn {requirement, _evaluation} -> requirement.spacecraft_id end)
      |> Enum.map(fn {spacecraft_id, items} -> spacecraft_demand(spacecraft_id, items) end)
      |> Enum.sort_by(&{&1.rule_met, &1.spacecraft_id})

    %{
      spacecraft: spacecraft,
      rule_met: Enum.count(spacecraft, & &1.rule_met),
      rule_total: length(spacecraft),
      rules: Enum.map(rules, fn {requirement, _evaluation} -> rule(requirement) end)
    }
  end

  # Requirements the version leaves unsatisfied (what an approver must acknowledge).
  defp unmet(organization_id, mission_id, version) do
    ((version.unsatisfied_document || %{})["requirements"] || [])
    |> Enum.map(fn item ->
      spacecraft_id =
        case Contacts.fetch_requirement_version(
               organization_id,
               mission_id,
               item["contact_requirement_id"],
               item["contact_requirement_version"]
             ) do
          {:ok, requirement} -> requirement.spacecraft_id
          _missing -> nil
        end

      %{
        requirement_id: item["contact_requirement_id"],
        requirement_version: item["contact_requirement_version"],
        spacecraft_id: spacecraft_id,
        why: Enum.map((item["hard_failures"] || []) ++ (item["search_failures"] || []), &reason/1)
      }
    end)
  end

  # Overlapping selected passes for one spacecraft (they block approval).
  defp conflicts(version) do
    ((version.conflict_document || %{})["items"] || [])
    |> Enum.map(fn item ->
      %{
        code: item["code"],
        spacecraft_id: item["spacecraft_id"],
        snapshot_ids: item["snapshot_ids"] || []
      }
    end)
  end

  defp spacecraft_demand(spacecraft_id, items) do
    {have, need} =
      Enum.reduce(items, {0, 0}, fn {requirement, evaluation}, {have, need} ->
        facts = evaluation["facts"] || %{}
        {have + (facts["selected_count"] || 0), need + (requirement.contact_count || 1)}
      end)

    %{
      spacecraft_id: spacecraft_id,
      rule_met: Enum.all?(items, fn {_requirement, evaluation} -> evaluation["satisfied"] end),
      contacts: %{have: have, need: need},
      reasons:
        items
        |> Enum.flat_map(fn {_requirement, evaluation} ->
          (evaluation["hard_failures"] || []) ++ (evaluation["search_failures"] || [])
        end)
        |> Enum.map(&reason/1)
        |> Enum.uniq()
    }
  end

  defp rule(requirement) do
    %{
      requirement_id: requirement.contact_requirement_id,
      version: requirement.version,
      spacecraft_id: requirement.spacecraft_id,
      text: rule_text(requirement),
      source: "requirement",
      window: %{from: requirement.earliest_start, to: requirement.latest_end}
    }
  end

  defp rule_text(requirement) do
    count = requirement.contact_count || 1
    direction = requirement.service_direction && to_string(requirement.service_direction)

    base = "#{count} #{direction || "contact"} #{if count == 1, do: "contact", else: "contacts"}"

    case requirement.success_measure do
      :minimum_duration ->
        base <> " of at least #{div(requirement.minimum_duration_seconds || 0, 60)} min"

      :minimum_data_volume ->
        base <> " moving at least #{requirement.minimum_data_volume_bytes} bytes"

      _other ->
        base
    end
  end

  defp reason(failure) when is_binary(failure), do: failure
  defp reason(%{"code" => code}), do: code
  defp reason(failure), do: inspect(failure)

  defp state(_plan, %{} = _superseded), do: :superseded
  defp state(plan, nil), do: plan.lifecycle_state

  defp ready?(nil, version, passes),
    do: (version.unsatisfied_document || %{})["clear"] == true and passes != []

  defp ready?(_superseded, _version, _passes), do: false

  # A draft overtaken by newer requirement or template versions reads as `superseded`, with why.
  defp summary(plan, version, passes, superseded) do
    {starts, ends} = span(passes)
    unsatisfied = (version.unsatisfied_document || %{})["requirements"] || []
    conflicts = (version.conflict_document || %{})["items"] || []

    %{
      id: plan.contact_plan_id,
      version: version.version,
      state: state(plan, superseded),
      superseded: superseded,
      window: %{from: starts, to: ends},
      author: actor(version.created_by || plan.created_by),
      counts: %{
        # The whole plan, kept (locked) passes included: what the Gantt shows.
        passes: length(passes),
        locked: length(version.locked_snapshot_ids || []),
        minutes:
          passes |> Enum.map(&DateTime.diff(&1.ends_at, &1.starts_at)) |> Enum.sum() |> div(60),
        conflicts: length(conflicts),
        unsatisfied: length(unsatisfied)
      },
      ready_to_approve: ready?(superseded, version, passes),
      updated_at: plan.updated_at
    }
  end

  defp pass(%ContactOpportunitySnapshot{} = snapshot, version, stations) do
    %{
      snapshot_id: snapshot.contact_opportunity_snapshot_id,
      spacecraft_id: (snapshot.route_binding_document || %{})["spacecraft_id"],
      station: StationRefs.of_snapshot(snapshot, stations),
      starts_at: snapshot.starts_at,
      ends_at: snapshot.ends_at,
      synthetic: snapshot.synthetic,
      locked: snapshot.contact_opportunity_snapshot_id in (version.locked_snapshot_ids || [])
    }
  end

  defp version(_org, _mission, _plan, current, nil), do: {:ok, current}

  defp version(organization_id, mission_id, plan, _current, number),
    do: Contacts.fetch_plan_version(organization_id, mission_id, plan.contact_plan_id, number)

  defp span([]), do: {nil, nil}

  defp span(passes),
    do:
      {passes |> Enum.map(& &1.starts_at) |> Enum.min(DateTime),
       passes |> Enum.map(& &1.ends_at) |> Enum.max(DateTime)}

  defp on_day?(_plan, nil), do: true
  defp on_day?(%{window: %{from: nil}}, _day), do: false
  defp on_day?(%{window: %{from: from}}, %Date{} = day), do: DateTime.to_date(from) == day

  defp list_opts(%{state: state}) when is_atom(state) and not is_nil(state),
    do: [lifecycle_state: state]

  defp list_opts(_filters), do: []

  # Who made the plan version: a person (`created_by` is usually a user id), Cadence itself for an
  # automatic run (`{kind: "system", name: "Cadence"}`), or nil when it isn't known (ux).
  defp actor(%{"display_name" => name}) when is_binary(name), do: %{kind: "user", name: name}
  defp actor(%{"name" => name}) when is_binary(name), do: %{kind: "user", name: name}
  defp actor(%{"email" => email}) when is_binary(email), do: %{kind: "user", name: email}

  defp actor(id) when is_binary(id) do
    case Accounts.fetch_user(id) do
      {:ok, user} -> %{kind: "user", id: id, name: user.display_name || user.email}
      _not_a_user -> system_actor(id)
    end
  end

  defp actor(_other), do: nil

  defp system_actor("cadence" <> _), do: %{kind: "system", name: "Cadence"}
  defp system_actor("system" <> _), do: %{kind: "system", name: "Cadence"}
  defp system_actor(_unknown), do: nil
end
