defmodule Cadence.Reads.ActionQueue.ContactItems do
  @moduledoc """
  Contact items of the action queue (BACKLOG §8; ux U11 as amended by U35):

    * `missed_pass`: one row per spacecraft with a `missed` or `failed` pass result (S9) whose
      planned AOS is within the failure lookback. **P1** when the spacecraft has no booked
      contact within `missed_pass_horizon_s/0` (or none is known), **P2** otherwise. The
      horizon is a stand-in for a contact requirement's maximum gap, which isn't modelled yet.
    * `station`: one row per ground station with an outage, maintenance or degraded window (S7)
      overlapping booked passes in the next 24 h. **P1** when an affected pass starts within
      2 h or is in progress (the U31/U33 clock), **P2** otherwise.
  """

  alias Cadence.Auth.Scope
  alias Cadence.Comms.StationAvailability
  alias Cadence.Reads.ActionQueue.Item
  alias Cadence.Reads.{Passes, PassReview}

  # U35: until a contact requirement carries a maximum gap.
  @missed_pass_horizon_s 6 * 3_600
  @station_horizon_s 24 * 3_600
  @next_contact_lookahead_s 7 * 86_400
  @p1_window_s 2 * 3_600
  @booked ~w(confirmed active)

  @doc "How far ahead a booked contact keeps a missed pass at P2 (seconds)."
  @spec missed_pass_horizon_s() :: pos_integer()
  def missed_pass_horizon_s, do: @missed_pass_horizon_s

  @doc "Both kinds of item for the mission. `fleet` resolves spacecraft members."
  @spec load(Scope.t(), binary(), map(), DateTime.t(), pos_integer()) :: [map()]
  def load(%Scope{} = scope, mission_id, fleet, now, lookback_s) do
    org = scope.organization_id
    by_id = Map.new(fleet.spacecraft, &{&1.id, &1})

    upcoming =
      org
      |> Passes.load(mission_id, now, DateTime.add(now, @next_contact_lookahead_s), %{
        states: @booked
      })
      |> Map.fetch!(:passes)

    missed_items(scope, mission_id, now, lookback_s, upcoming, by_id) ++
      station_items(org, mission_id, now, upcoming, by_id)
  end

  # -- missed passes -----------------------------------------------------------

  defp missed_items(scope, mission_id, now, lookback_s, upcoming, by_id) do
    from = DateTime.add(now, -lookback_s)
    filters = %{outcome: ["missed", "failed"], limit: 500}

    case PassReview.rows(scope, mission_id, from, now, filters) do
      {:ok, %{rows: [_ | _] = rows}} ->
        next = next_contacts(upcoming, now)

        rows
        |> Enum.group_by(& &1.spacecraft.id)
        |> Enum.map(fn {spacecraft_id, missed} ->
          missed_item(spacecraft_id, missed, Map.get(next, spacecraft_id), now, by_id)
        end)

      _none_or_forbidden ->
        []
    end
  end

  defp missed_item(spacecraft_id, missed, next, now, by_id) do
    missed = Enum.sort_by(missed, & &1.planned_aos, {:desc, DateTime})
    p1? = is_nil(next) or seconds_until(next.starts_at, now) > @missed_pass_horizon_s

    Item.new(%{
      id: "missed_pass:#{spacecraft_id}",
      priority: if(p1?, do: 1, else: 2),
      kind: :missed_pass,
      state: if(p1?, do: :critical, else: :caution),
      since: hd(missed).planned_aos,
      due_at: next && next.starts_at,
      count: length(missed),
      spacecraft: members([spacecraft_id], by_id),
      missed_passes:
        Enum.map(missed, fn row ->
          %{
            reservation_id: row.id,
            station: row.station,
            planned_aos: row.planned_aos,
            outcome: row.outcome,
            cause: row.cause,
            owner: row.owner
          }
        end),
      next_contact: next && %{reservation_id: next.id, station: next.station, aos: next.starts_at}
    })
  end

  defp next_contacts(upcoming, now) do
    upcoming
    |> Enum.filter(&(DateTime.compare(&1.starts_at, now) == :gt))
    |> Enum.sort_by(& &1.starts_at, DateTime)
    |> Enum.reduce(%{}, fn pass, acc -> Map.put_new(acc, pass.spacecraft_id, pass) end)
  end

  # -- stations ----------------------------------------------------------------

  defp station_items(org, mission_id, now, upcoming, by_id) do
    until = DateTime.add(now, @station_horizon_s)
    windows = StationAvailability.planning_windows(org, mission_id, now, until)
    sources = blocking_sources(org, mission_id, now, until)

    in_horizon =
      Enum.filter(upcoming, fn pass ->
        DateTime.compare(pass.starts_at, until) == :lt and
          DateTime.compare(pass.ends_at, now) == :gt
      end)

    windows
    |> Enum.flat_map(fn {station_id, station_windows} ->
      passes = Enum.filter(in_horizon, &(&1.station.id == station_id))
      station_item(station_id, station_windows, passes, sources, now, by_id)
    end)
  end

  defp station_item(station_id, windows, passes, sources, now, by_id) do
    affected =
      passes
      |> Enum.filter(&StationAvailability.overlaps?(windows, &1.starts_at, &1.ends_at))
      |> Enum.sort_by(& &1.starts_at, DateTime)

    case affected do
      [] ->
        []

      [first | _] ->
        window = StationAvailability.overlaps?(windows, first.starts_at, first.ends_at)
        p1? = Enum.any?(affected, &soon_or_flying?(&1, now))

        [
          Item.new(%{
            id: "station:#{station_id}",
            priority: if(p1?, do: 1, else: 2),
            kind: :station,
            state: if(p1?, do: :critical, else: :caution),
            since: window.starts_at,
            due_at: first.starts_at,
            count: length(affected),
            spacecraft: affected |> Enum.map(& &1.spacecraft_id) |> Enum.uniq() |> members(by_id),
            station_issue: %{
              station: first.station,
              window: %{
                id: window.window_id,
                kind: window.kind,
                starts_at: window.starts_at,
                ends_at: window.ends_at,
                source: Map.get(sources, window.window_id)
              },
              affected:
                Enum.map(affected, fn pass ->
                  %{
                    reservation_id: pass.id,
                    spacecraft_id: pass.spacecraft_id,
                    aos: pass.starts_at
                  }
                end)
            }
          })
        ]
    end
  end

  defp soon_or_flying?(pass, now),
    do:
      seconds_until(pass.starts_at, now) <= @p1_window_s and
        DateTime.compare(pass.ends_at, now) == :gt

  defp blocking_sources(org, mission_id, from, to) do
    org
    |> StationAvailability.blocking_windows(mission_id, from, to)
    |> Map.values()
    |> List.flatten()
    |> Map.new(&{&1.window_id, &1.source})
  end

  # -- shared ------------------------------------------------------------------

  defp seconds_until(at, now), do: DateTime.diff(at, now, :second)

  defp members(ids, by_id) do
    Enum.flat_map(ids, fn id ->
      case Map.fetch(by_id, id) do
        {:ok, craft} -> [Item.member(craft)]
        :error -> []
      end
    end)
  end
end
