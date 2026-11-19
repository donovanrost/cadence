defmodule Cadence.Reads.PlanMeasures do
  @moduledoc """
  Measures over a plan's selected passes for K1's C panel and S4 (lead, BACKLOG §8 domain 7/8).
  Nothing here judges: no rule carries a gap limit or an uplink count yet, so `limit_seconds`
  and `need` are `nil` and the console shows the measure without a verdict.

  - `longest_gap/2`: the longest stretch of the plan's UTC day without one of the spacecraft's
    passes. A gap runs from LOS to the next AOS; the day's edges count (00:00Z to the first AOS,
    the last LOS to 24:00Z). Only the plan's own passes count.
  - `uplink_passes/3`: passes whose booking will request an uplink leg (`UplinkLegs`), i.e.
    requested, not confirmed by the provider.
  - `provider_freeze/2`: the earliest `expires_at` (the last moment the provider honours the
    offer) among passes not yet sent to the provider, overall and per provider.
  """

  alias Cadence.ContactPlanning.{ContactGaps, ContactOpportunitySnapshot}
  alias Cadence.Contacts.UplinkLegs

  @day_s 86_400

  @doc "The plan's UTC day from its earliest pass: `{from, to}`, or nil without passes."
  @spec day([ContactOpportunitySnapshot.t()]) :: {DateTime.t(), DateTime.t()} | nil
  def day([]), do: nil

  def day(passes) do
    first = passes |> Enum.map(& &1.starts_at) |> Enum.min(DateTime)
    {:ok, from} = DateTime.new(DateTime.to_date(first), ~T[00:00:00], "Etc/UTC")
    {from, DateTime.add(from, @day_s)}
  end

  @doc """
  `%{seconds, limit_seconds: nil, from, to}` for `passes` (one spacecraft's) over `day`; nil
  when there's no day. A day with no pass is one gap of 86400 s; a day fully covered reads 0
  with `from`/`to` nil.
  """
  @spec longest_gap([ContactOpportunitySnapshot.t()], {DateTime.t(), DateTime.t()} | nil) ::
          map() | nil
  def longest_gap(_passes, nil), do: nil

  def longest_gap(passes, {from, to}),
    do: passes |> ContactGaps.longest(from, to) |> Map.put(:limit_seconds, nil)

  @doc """
  One spacecraft's `longest_gap` given its `requirements` (DECISIONS #74). With a gap limit on
  any of them, it's the evaluator's number for the limited requirement with the largest excess
  (`seconds - limit_seconds`): its window, its own eligible selected passes. Otherwise, the
  plan-day measure (`longest_gap/2`).
  """
  @spec spacecraft_gap(
          list(),
          [ContactOpportunitySnapshot.t()],
          {DateTime.t(), DateTime.t()} | nil
        ) ::
          map() | nil
  def spacecraft_gap(requirements, passes, day) do
    case Enum.filter(requirements, &is_integer(&1.max_gap_seconds)) do
      [] ->
        longest_gap(passes, day)

      limited ->
        limited
        |> Enum.map(&requirement_gap(&1, passes))
        |> Enum.max_by(&(&1.seconds - &1.limit_seconds))
    end
  end

  defp requirement_gap(requirement, passes) do
    passes
    |> Enum.filter(
      &(&1.eligible and &1.contact_requirement_id == requirement.contact_requirement_id)
    )
    |> ContactGaps.longest(requirement.earliest_start, requirement.latest_end)
    |> Map.put(:limit_seconds, requirement.max_gap_seconds)
  end

  @doc """
  `%{have, need: nil}`: how many of `passes` (one spacecraft's) will be booked with an uplink
  leg. One routing lookup per station and provider.
  """
  @spec uplink_passes(binary(), binary(), [ContactOpportunitySnapshot.t()]) :: map()
  def uplink_passes(organization_id, mission_id, passes) do
    have =
      passes
      |> Enum.frequencies_by(&leg_key/1)
      |> Enum.reduce(0, fn {{spacecraft_id, station, provider_id}, count}, acc ->
        leg =
          UplinkLegs.for_booking(organization_id, mission_id, spacecraft_id, station, provider_id)

        if is_map(leg), do: acc + count, else: acc
      end)

    %{have: have, need: nil}
  end

  defp leg_key(%ContactOpportunitySnapshot{} = pass) do
    route = pass.route_binding_document || %{}
    opportunity = pass.normalized_opportunity_document || %{}
    {route["spacecraft_id"], opportunity["ground_station_ref"], route["provider_id"]}
  end

  @doc """
  `%{at, provider: %{id, name}, snapshot_id, by_provider: [%{provider, at}]}` from the passes not
  yet sent to a provider (earliest `expires_at`, which may already be past), or nil when none
  is left. `names` maps provider ids to display names.
  """
  @spec provider_freeze([ContactOpportunitySnapshot.t()], %{binary() => binary()}) :: map() | nil
  def provider_freeze([], _names), do: nil

  def provider_freeze(unsent, names) do
    earliest = Enum.min_by(unsent, & &1.expires_at, DateTime)

    by_provider =
      unsent
      |> Enum.group_by(&provider_id/1)
      |> Enum.map(fn {id, passes} ->
        %{
          provider: provider(id, names),
          at: passes |> Enum.map(& &1.expires_at) |> Enum.min(DateTime)
        }
      end)
      |> Enum.sort_by(& &1.at, DateTime)

    %{
      at: earliest.expires_at,
      provider: provider(provider_id(earliest), names),
      snapshot_id: earliest.contact_opportunity_snapshot_id,
      by_provider: by_provider
    }
  end

  defp provider_id(pass), do: (pass.route_binding_document || %{})["provider_id"]

  defp provider(id, names), do: %{id: id, name: Map.get(names, id)}
end
