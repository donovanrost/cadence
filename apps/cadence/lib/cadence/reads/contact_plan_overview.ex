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
    ContactPlanExecutions,
    ContactPlanVersion,
    FleetPlanningRuns,
    PlanSupersession,
    StationConflicts
  }

  alias Cadence.GroundNetworks.MissionProviders
  alias Cadence.Management.Contacts
  alias Cadence.Reads.ContactPlanOverview.Demand
  alias Cadence.Reads.{PlanApproval, PlanMeasures, PlanRounds}

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

  @doc """
  The open drafts a save of `subject` (`{:template, id}` or `{:requirement, id}`) would
  supersede: `[%{plan: %{id, version}, day, author, state}]`. Nothing is written.
  """
  @spec would_supersede(binary(), binary(), {:template | :requirement, binary()}) :: [map()]
  def would_supersede(organization_id, mission_id, subject) do
    ids =
      organization_id
      |> PlanSupersession.would_supersede(mission_id, subject)
      |> MapSet.new(fn {plan, _version} -> plan.contact_plan_id end)

    organization_id
    |> list(mission_id, %{state: :draft})
    |> Enum.filter(&MapSet.member?(ids, &1.id))
    |> Enum.map(fn row ->
      %{
        plan: %{id: row.id, version: row.version},
        day: row.window.from && DateTime.to_date(row.window.from),
        author: row.author,
        state: row.state
      }
    end)
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

      approval = PlanApproval.latest(organization_id, mission_id, plan_id, version.version)

      summary = plan |> summary(version, passes, superseded) |> Map.put(:repair_of, repair_of)

      {:ok,
       summary
       |> Map.merge(%{
         # U69 A10: the plan's newest version, for the historical-version banner.
         latest_version: current.version,
         counts: %{summary.counts | conflicts: length(conflicts)},
         ready_to_approve: summary.ready_to_approve and availability.conflicts == [],
         passes: Enum.map(passes, &pass(&1, version, stations)),
         demand: demand(organization_id, mission_id, version, passes),
         unmet: Demand.unmet(organization_id, mission_id, version),
         provider_freeze: provider_freeze(organization_id, mission_id, plan, version, passes),
         conflicts: conflicts,
         at_risk: availability.at_risk,
         approval: approval
       })
       # U36: the round that submitted this version, and the one before it.
       |> Map.merge(PlanRounds.load(organization_id, mission_id, plan_id, version.version))}
    else
      _missing -> {:error, :plan_not_found}
    end
  end

  @doc "S2 demand for a version (`ContactPlanOverview.Demand.demand/4`)."
  defdelegate demand(organization_id, mission_id, version, passes), to: Demand

  # K1's freeze clock: the earliest offer expiry among passes not yet sent to a provider. Before
  # the version is approved or executed that's every selected pass; after, the unplaced items.
  defp provider_freeze(organization_id, mission_id, plan, version, passes) do
    unsent = unsent(organization_id, mission_id, plan, version, passes)

    names =
      if unsent == [],
        do: %{},
        else:
          organization_id
          |> MissionProviders.list_providers(mission_id)
          |> Map.new(&{&1.provider_id, &1.display_name})

    PlanMeasures.provider_freeze(unsent, names)
  end

  defp unsent(
         organization_id,
         mission_id,
         %ContactPlan{approved_version: v} = plan,
         version,
         passes
       )
       when v == version.version do
    case ContactPlanExecutions.list(organization_id, mission_id, plan.contact_plan_id, v) do
      [] ->
        passes

      items ->
        ids =
          for item <- items,
              item.lifecycle_state in [:pending, :requesting],
              item.provider_reservation_id in [nil, ""],
              into: MapSet.new(),
              do: item.contact_opportunity_snapshot_id

        Enum.filter(passes, &MapSet.member?(ids, &1.contact_opportunity_snapshot_id))
    end
  end

  defp unsent(_organization_id, _mission_id, _plan, _version, passes), do: passes

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
      # When the plan was first drafted, and when this version was made.
      created_at: plan.inserted_at,
      version_created_at: version.created_at,
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
      # When the provider stops honouring the offer (K1 'offers expire' count).
      expires_at: snapshot.expires_at,
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

  defp actor(id) when is_binary(id) do
    case Accounts.fetch_user(id) do
      # #466: never the email (#468 adds the membership check here).
      {:ok, user} -> %{kind: "user", id: id, name: user.display_name}
      _not_a_user -> system_actor(id)
    end
  end

  defp actor(_other), do: nil

  defp system_actor("cadence" <> _), do: %{kind: "system", name: "Cadence"}
  defp system_actor("system" <> _), do: %{kind: "system", name: "Cadence"}
  defp system_actor(_unknown), do: nil
end
