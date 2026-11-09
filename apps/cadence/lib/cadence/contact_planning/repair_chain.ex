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

  alias Cadence.ContactPlanning.{ContactPlanExecutions, ContactPlans, RepairLinks}

  @applied [:approved, :executing, :partially_reserved, :reserved, :failed]
  @live [:reserved, :uncertain, :requesting]

  @type link :: %{
          run_id: binary(),
          source: binary(),
          plan_id: binary(),
          replaces: %{binary() => binary()}
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

    for link <- chain.links, {snapshot_id, lost} <- link.replaces, into: %{} do
      item = Map.get(by_plan_snapshot, {link.plan_id, snapshot_id})
      {lost, %{plan_id: link.plan_id, reservation_id: item && item.provider_reservation_id}}
    end
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
  Pairs a repair's new selections with the chain's lost bookings, per spacecraft in time
  order: `%{new snapshot_id => lost key}`. `snapshots` maps snapshot ids to snapshots (the
  lost items' and the new ones).
  """
  @spec pair([struct()], [struct()], %{binary() => struct()}) :: %{binary() => binary()}
  def pair(lost_items, new_snapshots, snapshots) do
    lost_by =
      Enum.group_by(lost_items, &spacecraft(snapshots[&1.contact_opportunity_snapshot_id]))

    new_by = Enum.group_by(new_snapshots, &spacecraft/1)

    for {spacecraft_id, fresh} <- new_by,
        {snapshot, item} <-
          Enum.zip(
            Enum.sort_by(fresh, & &1.starts_at, DateTime),
            lost_by
            |> Map.get(spacecraft_id, [])
            |> Enum.sort_by(&starts(snapshots, &1), DateTime)
          ),
        into: %{},
        do: {snapshot.contact_opportunity_snapshot_id, lost_key(item)}
  end

  @doc """
  The pairing to persist when a repair run creates its candidate plan: `%{"replaces" => ...}`
  (empty for a run that isn't a repair). New selections are the candidate's selected passes
  that aren't locked; lost ones are the source chain's at this moment.
  """
  @spec replaces_summary(struct(), struct()) :: map()
  def replaces_summary(%{source_contact_plan_id: source} = run, version) when is_binary(source) do
    org = run.organization_id
    mission = run.mission_id

    with {:ok, chain} <- load(org, mission, source),
         [_ | _] = lost <- lost_bookings(chain) do
      locked = MapSet.new(version.locked_snapshot_ids)

      fresh =
        org
        |> ContactPlans.selected_snapshots(mission, version.contact_plan_id, version.version)
        |> Enum.reject(&MapSet.member?(locked, &1.contact_opportunity_snapshot_id))

      snapshots =
        chain.plans
        |> Enum.flat_map(&ContactPlans.selected_snapshots(org, mission, &1, chain.versions[&1]))
        |> Map.new(&{&1.contact_opportunity_snapshot_id, &1})

      %{"replaces" => pair(lost, fresh, snapshots)}
    else
      _nothing_lost -> %{}
    end
  end

  def replaces_summary(_run, _version), do: %{}

  defp starts(snapshots, item),
    do: snapshots[item.contact_opportunity_snapshot_id].starts_at

  defp spacecraft(nil), do: nil
  defp spacecraft(snapshot), do: (snapshot.route_binding_document || %{})["spacecraft_id"]

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
