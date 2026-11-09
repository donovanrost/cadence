defmodule Cadence.ContactPlanning.RepairChain do
  @moduledoc """
  A day's plan and the repairs applied to it (qa #30, domain's model call).

  - The **chain** is the root plan plus every *applied* repair plan in its `repair_of` chain
    (a repair run's `source_contact_plan_id` → its candidate plan). The **head** is the latest
    applied plan; a new repair is computed from it.
  - The day's **current bookings** are the live execution items (`reserved`, `uncertain`,
    `requesting`) across the whole chain; a repair locks them.
  - A booking is **lost** when its item was rejected, failed after it was placed (the provider
    canceled or failed it, `booking_lost`), or failed `operator_not_booked` (#53).
  - A lost booking is **replaced** once an applied repair paired a new pass with it. The
    pairing is persisted on the repair run when its candidate plan is created
    (`result_summary_document["replaces"]`, `%{new snapshot_id => lost key}`), never re-derived.
    If the replacement is lost in turn, the replacement is the lost booking, so one need is
    never counted twice.

  `lost_bookings/1` (lost and not replaced) feeds both the repair and the passes read.
  """

  alias Cadence.ContactPlanning.{
    ContactPlanExecutions,
    ContactPlans,
    FleetPlanningRuns,
    RepairLinks,
    RepairPairing
  }

  @applied [:approved, :executing, :partially_reserved, :reserved, :failed]
  @live [:reserved, :uncertain, :requesting]

  @type link :: %{
          run_id: binary(),
          source: binary(),
          plan_id: binary(),
          replaces: %{binary() => binary()},
          covered: %{binary() => binary()}
        }
  @type t :: %{
          root: binary(),
          head: binary(),
          plans: [binary()],
          versions: %{binary() => pos_integer()},
          links: [link()],
          items: [struct()]
        }

  @doc "The chain that `plan_id` belongs to (as root, applied repair or proposal)."
  @spec load(binary(), binary(), binary()) :: {:ok, t()} | {:error, :contact_plan_not_found}
  def load(organization_id, mission_id, plan_id) do
    links = RepairLinks.list(organization_id, mission_id)
    root = root(plan_id, Map.new(links, &{&1.plan_id, &1.source}), MapSet.new())

    # The root is the day's plan in whatever state; only repairs must be applied to join.
    case ContactPlans.fetch(organization_id, mission_id, root) do
      {:error, _not_found} ->
        {:error, :contact_plan_not_found}

      {:ok, plan, current} ->
        root_plan = %{plan | approved_version: plan.approved_version || current.version}
        {plans, chain_links} = descend(organization_id, mission_id, [root_plan], links)

        {:ok,
         %{
           root: root,
           head: List.last(plans).contact_plan_id,
           plans: Enum.map(plans, & &1.contact_plan_id),
           versions: Map.new(plans, &{&1.contact_plan_id, &1.approved_version}),
           links: chain_links,
           items: Enum.flat_map(plans, &items(organization_id, mission_id, &1))
         }}
    end
  end

  @doc """
  The run that proposed the chain head of `plan_id` (the latest applied repair, else the plan
  itself): the source a new repair starts from.
  """
  @spec head_run(binary(), binary(), binary()) ::
          {:ok, struct()} | {:error, :repair_source_not_found}
  def head_run(organization_id, mission_id, plan_id) do
    head =
      case load(organization_id, mission_id, plan_id) do
        {:ok, chain} -> chain.head
        {:error, _not_found} -> plan_id
      end

    case Enum.find(
           FleetPlanningRuns.list(organization_id, mission_id),
           &(&1.candidate_contact_plan_id == head)
         ) do
      nil -> {:error, :repair_source_not_found}
      run -> {:ok, run}
    end
  end

  @doc """
  What a repair run proposes, for its diff (qa #30): `before` is the day's bookings it started
  from (live ones across the chain, plus lost ones no *other* repair replaced), `after` the
  candidate plan's passes, `locked` the candidate's locked snapshot ids. Stable after Apply.
  """
  @spec review_passes(struct()) ::
          %{before: [struct()], after: [struct()], locked: MapSet.t()} | nil
  def review_passes(%{candidate_contact_plan_id: plan_id, source_contact_plan_id: source} = run)
      when is_binary(plan_id) and is_binary(source) do
    org = run.organization_id
    mission = run.mission_id

    with {:ok, %{} = chain} <- load(org, mission, source),
         {:ok, version} <-
           ContactPlans.fetch_version(org, mission, plan_id, run.candidate_contact_plan_version) do
      replaced_elsewhere =
        for {lost, %{plan_id: by}} <- replacements(chain),
            by != plan_id,
            into: MapSet.new(),
            do: lost

      ids =
        chain.items
        |> Enum.filter(&(&1.contact_plan_id != plan_id and started_from?(&1, replaced_elsewhere)))
        |> MapSet.new(& &1.contact_opportunity_snapshot_id)

      before =
        chain.plans
        |> Enum.reject(&(&1 == plan_id))
        |> Enum.flat_map(&ContactPlans.selected_snapshots(org, mission, &1, chain.versions[&1]))
        |> Enum.filter(&MapSet.member?(ids, &1.contact_opportunity_snapshot_id))
        |> Enum.uniq_by(& &1.contact_opportunity_snapshot_id)

      %{
        before: before,
        after: ContactPlans.selected_snapshots(org, mission, plan_id, version.version),
        locked: MapSet.new(version.locked_snapshot_ids),
        covered: covered_snapshots(chain, run)
      }
    else
      _missing -> nil
    end
  end

  def review_passes(_run), do: nil

  # `%{snapshot_id => provider_reservation_id}`: the lost passes this run found covered by a
  # single booking (#56), for the review's 'covered by a single booking'.
  defp covered_snapshots(chain, run) do
    covered = get_in(run.input_document || %{}, ["repair", "covered"]) || %{}

    for item <- chain.items,
        reservation_id = covered[lost_key(item)],
        reservation_id != nil,
        into: %{},
        do: {item.contact_opportunity_snapshot_id, reservation_id}
  end

  defp started_from?(item, replaced_elsewhere),
    do:
      item.lifecycle_state in @live or
        (lost?(item) and not MapSet.member?(replaced_elsewhere, lost_key(item)))

  @doc """
  The replacements across the chains of `plan_ids` (the passes read's `replaced_by`):
  `%{lost key => %{plan_id, reservation_id}}`. Each chain loads once.
  """
  @spec replacements_for(binary(), binary(), [binary()]) :: %{binary() => map()}
  def replacements_for(organization_id, mission_id, plan_ids) do
    plan_ids
    |> Enum.uniq()
    |> Enum.reduce({MapSet.new(), %{}}, &add_chain(organization_id, mission_id, &1, &2))
    |> elem(1)
  end

  defp add_chain(organization_id, mission_id, plan_id, {seen, acc}) do
    with false <- MapSet.member?(seen, plan_id),
         {:ok, chain} <- load(organization_id, mission_id, plan_id) do
      {MapSet.union(seen, MapSet.new(chain.plans)), Map.merge(acc, replacements(chain))}
    else
      true -> {seen, acc}
      {:error, _not_found} -> {MapSet.put(seen, plan_id), acc}
    end
  end

  @doc """
  One-time pairing for applied repairs created before pairings were persisted (qa #30): each
  such run pairs its new passes with its source chain's lost bookings, the same way
  `RepairPairing` does at creation, and persists it. Returns the run ids it filled; a link that
  can't be paired is skipped. Run once per mission with `mix cadence.repairs.backfill_pairing
  ORG MISSION` after deploying the chain model; it only fills runs with no pairing, so a rerun
  is harmless.
  """
  @spec backfill(binary(), binary()) :: [binary()]
  def backfill(organization_id, mission_id) do
    organization_id
    |> RepairLinks.list(mission_id)
    |> Enum.filter(&(&1.replaces == %{}))
    |> Enum.flat_map(fn link ->
      case backfill_link(organization_id, mission_id, link) do
        :ok -> [link.run_id]
        _skipped -> []
      end
    end)
  end

  # Skips (never raises on) a link that isn't applied, can't load or pairs nothing.
  defp backfill_link(organization_id, mission_id, link) do
    with %{} = plan <- applied(organization_id, mission_id, link.plan_id),
         {:ok, chain} <- load(organization_id, mission_id, link.source),
         {:ok, version} <-
           ContactPlans.fetch_version(
             organization_id,
             mission_id,
             plan.contact_plan_id,
             plan.approved_version
           ),
         earlier = %{
           chain
           | items: Enum.reject(chain.items, &(&1.contact_plan_id == plan.contact_plan_id))
         },
         run = %{
           organization_id: organization_id,
           mission_id: mission_id,
           input_document: %{
             "repair" => %{
               "lost_bookings" => lost_booking_inputs(earlier, organization_id, mission_id)
             }
           }
         },
         %{"replaces" => replaces} when map_size(replaces) > 0 <-
           RepairPairing.summary(run, version) do
      RepairLinks.put_replaces(link.run_id, replaces)
    end
  end

  @doc "Live items (the day's current bookings)."
  @spec live_items(t()) :: [struct()]
  def live_items(chain), do: Enum.filter(chain.items, &(&1.lifecycle_state in @live))

  @doc "Lost bookings that no applied repair has replaced yet."
  @spec lost_bookings(t()) :: [struct()]
  def lost_bookings(chain) do
    replaced = chain |> replacements() |> Map.keys() |> MapSet.new()
    Enum.filter(chain.items, &(lost?(&1) and not MapSet.member?(replaced, lost_key(&1))))
  end

  @doc """
  `%{lost key => %{plan_id, reservation_id}}`: the repair plan and booking that replaced each
  lost booking (`reservation_id` is nil until that pass is placed).
  """
  @spec replacements(t()) :: %{binary() => %{plan_id: binary(), reservation_id: binary() | nil}}
  def replacements(chain) do
    by_plan_snapshot =
      Map.new(chain.items, &{{&1.contact_plan_id, &1.contact_opportunity_snapshot_id}, &1})

    repaired =
      for link <- chain.links, {snapshot_id, lost} <- link.replaces, into: %{} do
        item = Map.get(by_plan_snapshot, {link.plan_id, snapshot_id})

        {lost,
         %{
           kind: "repair",
           plan_id: link.plan_id,
           reservation_id: item && item.provider_reservation_id
         }}
      end

    # DECISIONS #56: a live single booking covers it (no plan).
    covered =
      for link <- chain.links, {lost, reservation_id} <- link.covered, into: %{} do
        {lost, %{kind: "single_booking", plan_id: nil, reservation_id: reservation_id}}
      end

    Map.merge(covered, repaired)
  end

  @doc "Whether an execution item is a lost booking."
  @spec lost?(struct()) :: boolean()
  def lost?(%{lifecycle_state: :rejected}), do: true

  def lost?(%{lifecycle_state: :failed} = item),
    do:
      is_binary(item.provider_reservation_id) or
        (item.last_error_document || %{})["code"] == "operator_not_booked"

  def lost?(_item), do: false

  @doc "A lost booking's identity in `replaces`: its reservation, else its execution item."
  @spec lost_key(struct()) :: binary()
  def lost_key(item), do: item.provider_reservation_id || item.contact_plan_execution_item_id

  @doc """
  The chain's lost bookings as a repair records them in its input (`RepairPairing`):
  `[%{"key", "spacecraft_id", "starts_at"}]`.
  """
  @spec lost_booking_inputs(t(), binary(), binary()) :: [map()]
  def lost_booking_inputs(chain, organization_id, mission_id) do
    snapshots =
      chain.plans
      |> Enum.flat_map(
        &ContactPlans.selected_snapshots(organization_id, mission_id, &1, chain.versions[&1])
      )
      |> Map.new(&{&1.contact_opportunity_snapshot_id, &1})

    for item <- lost_bookings(chain),
        snapshot = snapshots[item.contact_opportunity_snapshot_id],
        snapshot != nil do
      %{
        "key" => lost_key(item),
        "requirement_id" => snapshot.contact_requirement_id,
        "spacecraft_id" => (snapshot.route_binding_document || %{})["spacecraft_id"],
        "starts_at" => DateTime.to_iso8601(snapshot.starts_at)
      }
    end
  end

  defp root(plan_id, sources, seen) do
    case Map.fetch(sources, plan_id) do
      {:ok, source} when is_binary(source) ->
        if MapSet.member?(seen, source),
          do: plan_id,
          else: root(source, sources, MapSet.put(seen, plan_id))

      _root ->
        plan_id
    end
  end

  # Applied repairs whose source is in the chain, in the order they were proposed.
  defp descend(organization_id, mission_id, plans, links) do
    in_chain = MapSet.new(plans, & &1.contact_plan_id)

    next =
      Enum.find_value(links, fn link ->
        if MapSet.member?(in_chain, link.source) and not MapSet.member?(in_chain, link.plan_id),
          do: applied(organization_id, mission_id, link.plan_id)
      end)

    case next do
      nil ->
        {plans, chain_links(plans, links)}

      plan ->
        descend(organization_id, mission_id, plans ++ [plan], links)
    end
  end

  defp chain_links(plans, links) do
    ids = MapSet.new(plans, & &1.contact_plan_id)
    Enum.filter(links, &MapSet.member?(ids, &1.plan_id))
  end

  defp applied(organization_id, mission_id, plan_id) do
    case ContactPlans.fetch(organization_id, mission_id, plan_id) do
      {:ok, %{lifecycle_state: state, approved_version: v} = plan, _version}
      when state in @applied and is_integer(v) ->
        plan

      _not_applied ->
        nil
    end
  end

  defp items(organization_id, mission_id, plan),
    do:
      ContactPlanExecutions.list(
        organization_id,
        mission_id,
        plan.contact_plan_id,
        plan.approved_version
      )
end
