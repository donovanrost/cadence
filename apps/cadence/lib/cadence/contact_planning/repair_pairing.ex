defmodule Cadence.ContactPlanning.RepairPairing do
  @moduledoc """
  Which lost booking each new pass of a repair replaces (qa #30), fixed when the repair's
  candidate plan is created and persisted on its run (`result_summary_document["replaces"]`,
  `%{new snapshot_id => lost key}`).

  The repair records the lost bookings it started from in its input
  (`input_document["repair"]["lost_bookings"]`, from `RepairChain` at repair start). New passes
  are the candidate's selected passes that aren't locked. Pairing (domain review R1, DECISIONS
  #56): within the same `contact_requirement_id` first, nearest start first; then, only where a
  side's requirement is unknown, within the same spacecraft, nearest start first. The rest stay
  unpaired: a new pass for demand that was never lost replaces nothing.
  """

  alias Cadence.ContactPlanning.ContactPlans

  @doc """
  What a repair run's candidate version persists on the run: `"replaces"` (`%{new snapshot_id =>
  lost key}`) and, when single bookings cover lost ones (#56), `"covered"` (`%{lost key =>
  provider_reservation_id}`, decided at repair start and recorded in its input).
  """
  @spec summary(struct() | map(), struct()) :: map()
  def summary(run, version), do: Map.merge(replaces(run, version), covered(run))

  defp replaces(
         %{input_document: %{"repair" => %{"lost_bookings" => [_ | _] = lost}}} = run,
         version
       ) do
    locked = MapSet.new(version.locked_snapshot_ids)

    fresh =
      run.organization_id
      |> ContactPlans.selected_snapshots(run.mission_id, version.contact_plan_id, version.version)
      |> Enum.reject(&MapSet.member?(locked, &1.contact_opportunity_snapshot_id))
      |> Enum.map(
        &%{
          id: &1.contact_opportunity_snapshot_id,
          requirement_id: &1.contact_requirement_id,
          spacecraft_id: (&1.route_binding_document || %{})["spacecraft_id"],
          starts_at: &1.starts_at
        }
      )

    %{"replaces" => pair(Enum.map(lost, &lost_entry/1), fresh)}
  end

  defp replaces(_run, _version), do: %{}

  defp covered(%{input_document: %{"repair" => %{"covered" => covered}}})
       when is_map(covered) and map_size(covered) > 0,
       do: %{"covered" => covered}

  defp covered(_run), do: %{}

  @doc """
  Which lost bookings live single bookings cover (DECISIONS #56): `%{lost key =>
  provider_reservation_id}`. The same rules as `pair/2`; a single booking has no requirement,
  so it pairs within its spacecraft, nearest start first, and the rest stay unpaired.
  """
  @spec cover([map()], [map()]) :: %{binary() => binary()}
  def cover(lost_inputs, single_bookings) do
    singles =
      Enum.map(
        single_bookings,
        &%{
          id: &1.provider_reservation_id,
          requirement_id: nil,
          spacecraft_id: &1.spacecraft_id,
          starts_at: &1.starts_at
        }
      )

    lost_inputs
    |> Enum.map(&lost_entry/1)
    |> pair(singles)
    |> Map.new(fn {reservation_id, lost_key} -> {lost_key, reservation_id} end)
  end

  defp lost_entry(booking) do
    {:ok, starts_at, _} = DateTime.from_iso8601(booking["starts_at"])

    %{
      id: booking["key"],
      requirement_id: booking["requirement_id"],
      spacecraft_id: booking["spacecraft_id"],
      starts_at: starts_at
    }
  end

  @doc """
  Pairs `%{id, requirement_id, spacecraft_id, starts_at}` lists: `%{new id => lost id}`. Same
  requirement first; then same spacecraft where either requirement is unknown; nearest start
  first within each step (ties by id); the rest unpaired.
  """
  @spec pair([map()], [map()]) :: %{binary() => binary()}
  def pair(lost, fresh) do
    {pairs, lost, fresh} = greedy(lost, fresh, %{}, &same_requirement?/2)
    {pairs, _lost, _fresh} = greedy(lost, fresh, pairs, &same_spacecraft_unknown_requirement?/2)
    pairs
  end

  defp same_requirement?(l, f),
    do: l.requirement_id != nil and l.requirement_id == f.requirement_id

  defp same_spacecraft_unknown_requirement?(l, f),
    do:
      (l.requirement_id == nil or f.requirement_id == nil) and l.spacecraft_id != nil and
        l.spacecraft_id == f.spacecraft_id

  # Repeatedly takes the closest eligible (lost, new) pair until none is left.
  defp greedy(lost, fresh, pairs, eligible?) do
    candidates =
      for l <- lost, f <- fresh, eligible?.(l, f) do
        {abs(DateTime.diff(f.starts_at, l.starts_at, :millisecond)), l.id, f.id, l, f}
      end

    case Enum.min(candidates, fn -> nil end) do
      nil ->
        {pairs, lost, fresh}

      {_distance, _lost_id, _new_id, l, f} ->
        greedy(
          List.delete(lost, l),
          List.delete(fresh, f),
          Map.put(pairs, f.id, l.id),
          eligible?
        )
    end
  end
end
