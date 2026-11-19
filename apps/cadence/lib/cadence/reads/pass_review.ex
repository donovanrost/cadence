defmodule Cadence.Reads.PassReview do
  @moduledoc """
  Pass review reads for K3 "Close the books" (S9, DECISIONS #47/#48,
  `docs/apogee/domain/pass-review.md`).

  `realized_ratio = realized / (planned − canceled − pending_report)`: Cadence-requested
  cancellations and passes without a provider report stay out of the denominator, and any
  pending report (or an unhealthy provider event cursor) makes the span `provisional`. Failed
  passes count as missed on the strip.
  """

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Comms.StationRefs
  alias Cadence.Contacts.PassResults
  alias Cadence.Contacts.PassResults.Queries
  alias Cadence.GroundNetworks.{MissionProviders, ProviderEventCursors}
  alias Cadence.Platform.PassReviewSettings
  alias Cadence.SpacecraftStore

  @spec rows(Scope.t(), binary(), DateTime.t(), DateTime.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def rows(%Scope{} = scope, mission_id, from, to, filters \\ %{}) do
    with :ok <- authorize(scope, mission_id) do
      org = scope.organization_id
      {rows, total, disputable} = Queries.rows(org, mission_id, from, to, filters)
      names = identity(org, mission_id, rows)
      next = Map.get(filters, :offset, 0) + length(rows)

      {:ok,
       %{
         rows: Enum.map(rows, &row(&1, names)),
         total: total,
         disputable: disputable,
         next_cursor: if(next < total, do: Integer.to_string(next))
       }}
    end
  end

  @spec summary(Scope.t(), binary(), DateTime.t(), DateTime.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def summary(%Scope{} = scope, mission_id, from, to, opts \\ []) do
    with :ok <- authorize(scope, mission_id) do
      org = scope.organization_id
      agg = Queries.aggregate(org, mission_id, from, to, Keyword.get(opts, :plan))
      settings = PassReviewSettings.effective(org, mission_id)
      counts = outcome_counts(agg.outcomes)
      freshness = freshness(org, mission_id, agg.provider_ids)
      providers = providers(org, mission_id)
      stations = stations(org, mission_id)

      {:ok,
       Map.merge(counts, %{
         realized_ratio: ratio(counts),
         threshold: settings.threshold,
         target: settings.target,
         provisional:
           counts.pending_count > 0 or Enum.any?(freshness, &(&1.cursor_healthy == false)),
         missed_by_owner: by_owner(agg.owners, ["missed", "failed"]),
         partial_by_owner: by_owner(agg.owners, ["partial"]),
         by_station: by_station(agg.stations, stations, providers),
         by_cause: by_cause(agg.causes),
         plans: agg.plans,
         volume: volume(agg.volume),
         freshness:
           Enum.map(freshness, &Map.put(&1, :provider, Map.get(providers, &1.provider_id)))
       })}
    end
  end

  @spec daily(Scope.t(), binary(), DateTime.t(), DateTime.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def daily(%Scope{} = scope, mission_id, from, to, opts \\ []) do
    with :ok <- authorize(scope, mission_id) do
      org = scope.organization_id
      agg = Queries.aggregate(org, mission_id, from, to, Keyword.get(opts, :plan))
      settings = PassReviewSettings.effective(org, mission_id)

      days =
        agg.days
        |> Enum.group_by(& &1.day)
        |> Enum.sort_by(fn {day, _} -> day end, Date)
        |> Enum.map(fn {day, entries} -> day(day, entries) end)

      {:ok, %{days: days, target: settings.target, threshold: settings.threshold}}
    end
  end

  # -- shaping ---------------------------------------------------------------------------------

  defp volume(nil), do: volume(%{})

  defp volume(totals) do
    %{
      provider_bytes: number(totals[:provider_bytes]),
      provider_frames: number(totals[:provider_frames]),
      received_bytes: number(totals[:received_bytes]),
      received_frames: number(totals[:received_frames]),
      provider_reported_passes: totals[:provider_reported_passes] || 0,
      received_known_passes: totals[:received_known_passes] || 0
    }
  end

  defp number(%Decimal{} = value), do: Decimal.to_integer(value)
  defp number(value), do: value

  defp outcome_counts(outcomes) do
    count = fn names ->
      outcomes
      |> Enum.filter(&(elem(&1, 0).outcome in names))
      |> Enum.map(&elem(&1, 1))
      |> Enum.sum()
    end

    %{
      planned: count.(~w(realized partial missed failed canceled pending_report)),
      realized: count.(["realized"]),
      partial: count.(["partial"]),
      missed: count.(["missed", "failed"]),
      failed: count.(["failed"]),
      canceled: count.(["canceled"]),
      pending_count: count.(["pending_report"])
    }
  end

  defp ratio(%{planned: planned, canceled: canceled, pending_count: pending, realized: realized}) do
    case planned - canceled - pending do
      denominator when denominator > 0 -> Float.round(realized / denominator, 4)
      _none -> nil
    end
  end

  # Every owner key is present (0 when none), so the strip caption needs no defaults.
  defp by_owner(owners, outcomes) do
    owners
    |> Enum.filter(fn {key, _count} -> key.outcome in outcomes end)
    |> Enum.reduce(%{"provider" => 0, "us" => 0, "weather" => 0, "unknown" => 0}, fn {key, count},
                                                                                     acc ->
      Map.update(acc, key.owner || "unknown", count, &(&1 + count))
    end)
  end

  # One row per resolved station (a station seen by id and by code is one), falling back to the
  # raw ref when it doesn't resolve.
  defp by_station(entries, stations, providers) do
    entries
    |> Enum.group_by(&{station_key(&1.ground_station_ref, stations), &1.provider_id})
    |> Enum.map(fn {{_station, provider_id}, group} ->
      ref = group |> Enum.map(& &1.ground_station_ref) |> Enum.min(fn -> nil end)

      outcome = fn names ->
        group |> Enum.filter(&(&1.outcome in names)) |> Enum.map(& &1.count) |> Enum.sum()
      end

      %{
        station: station(ref, stations),
        provider: Map.get(providers, provider_id),
        planned: Enum.sum(Enum.map(group, & &1.count)),
        realized: outcome.(["realized"]),
        partial: outcome.(["partial"]),
        # As on the strip: missed includes failed, and failed is also given alone (contacts.md).
        missed: outcome.(["missed", "failed"]),
        failed: outcome.(["failed"]),
        canceled: outcome.(["canceled"]),
        planned_seconds: group |> Enum.map(&(&1.planned_seconds || 0)) |> Enum.sum(),
        flown_seconds: group |> Enum.map(&(&1.flown_seconds || 0)) |> Enum.sum()
      }
    end)
    |> Enum.sort_by(&(&1.station.code || &1.station.name || ""))
  end

  defp station_key(nil, _stations), do: nil

  defp station_key(ref, stations) do
    case StationRefs.resolve(ref, stations) do
      %{id: nil} -> {:ref, ref}
      %{id: id} -> {:id, id}
    end
  end

  defp by_cause(causes) do
    causes
    |> Enum.filter(fn {key, _} -> key.outcome in ~w(missed failed partial) and key.cause end)
    |> Enum.group_by(fn {key, _} -> {key.cause, key.cause_source, key.owner} end)
    |> Enum.map(fn {{cause, source, owner}, group} ->
      sum = fn names ->
        group
        |> Enum.filter(&(elem(&1, 0).outcome in names))
        |> Enum.map(&elem(&1, 1))
        |> Enum.sum()
      end

      %{
        cause: cause,
        cause_source: source,
        owner: owner,
        missed: sum.(~w(missed failed)),
        partial: sum.(["partial"])
      }
    end)
    |> Enum.sort_by(&(-(&1.missed + &1.partial)))
  end

  defp day(day, entries) do
    sum = fn names ->
      entries |> Enum.filter(&(&1.outcome in names)) |> Enum.map(& &1.count) |> Enum.sum()
    end

    counts = %{
      planned: Enum.sum(Enum.map(entries, & &1.count)),
      realized: sum.(["realized"]),
      canceled: sum.(["canceled"]),
      pending_count: sum.(["pending_report"])
    }

    losses = Enum.filter(entries, &(&1.outcome in ~w(missed failed partial)))

    %{
      day: day,
      planned: counts.planned,
      realized: counts.realized,
      canceled: counts.canceled,
      pending: counts.pending_count,
      realized_ratio: ratio(counts),
      top_cause: top(losses, & &1.cause),
      top_station: top(losses, & &1.station)
    }
  end

  defp top([], _key), do: nil

  defp top(entries, key) do
    entries
    |> Enum.reject(&is_nil(key.(&1)))
    |> Enum.group_by(key, & &1.count)
    |> Enum.max_by(fn {_value, counts} -> Enum.sum(counts) end, fn -> {nil, []} end)
    |> elem(0)
  end

  defp row(r, names) do
    %{
      id: r.provider_reservation_id,
      spacecraft: %{
        id: r.spacecraft_id,
        name: Map.get(names.spacecraft, r.spacecraft_id, r.spacecraft_id)
      },
      station: station(r.ground_station_ref, names.stations),
      provider: Map.get(names.providers, r.provider_id),
      antenna_ref: r.antenna_ref,
      plan: r.contact_plan_id && %{id: r.contact_plan_id, version: r.contact_plan_version},
      planned_aos: r.planned_aos,
      planned_los: r.planned_los,
      actual_aos: r.actual_aos,
      actual_los: r.actual_los,
      planned_seconds: r.planned_seconds,
      flown_seconds: r.flown_seconds,
      planned_bytes: r.planned_bytes,
      provider_bytes: r.provider_bytes,
      provider_frames: r.provider_frames,
      received_bytes: r.received_bytes,
      received_frames: r.received_frames,
      observations: r.observations,
      outcome: r.outcome,
      cause: r.cause,
      cause_source: r.cause_source,
      owner: r.owner,
      disputable: r.disputable,
      provisional: is_nil(r.provider_reported_at),
      provider_reported_at: r.provider_reported_at,
      realized_contact_id: r.realized_contact_id,
      scheduled_contact_id: r.scheduled_contact_id
    }
  end

  # -- identity --------------------------------------------------------------------------------

  defp identity(org, mission_id, rows) do
    ids = rows |> Enum.map(& &1.spacecraft_id) |> Enum.uniq()

    spacecraft =
      case SpacecraftStore.fetch_spacecrafts_in_batches(org, mission_id, ids) do
        {:ok, found} -> Map.new(found, fn {id, sc} -> {id, sc.display_name} end)
        _error -> %{}
      end

    %{
      spacecraft: spacecraft,
      stations: stations(org, mission_id),
      providers: providers(org, mission_id)
    }
  end

  # Matched by id, code or provider station ref, as `/passes` does (StationRefs).
  defp stations(org, mission_id), do: StationRefs.index(org, mission_id)

  # Identity never shows a suggested code (U25). `ref` stays the raw ref; an unmatched ref is
  # shown as its own name.
  defp station(nil, _stations), do: %{ref: nil, id: nil, code: nil, name: nil}

  defp station(ref, stations) do
    case StationRefs.resolve(ref, stations) do
      %{id: nil} -> %{ref: ref, id: nil, code: nil, name: ref}
      resolved -> resolved
    end
  end

  defp providers(org, mission_id),
    do:
      org
      |> MissionProviders.list_providers(mission_id)
      |> Map.new(
        &{&1.provider_id,
         %{id: &1.provider_id, name: &1.display_name, account_id: &1.provider_account_id}}
      )

  defp freshness(org, mission_id, provider_ids) do
    providers = providers(org, mission_id)
    cursors = org |> ProviderEventCursors.list() |> Enum.group_by(& &1.provider_account_id)

    org
    |> PassResults.freshness(mission_id)
    |> Enum.filter(&(&1.provider_id in provider_ids or &1.pending_reports > 0))
    |> Enum.map(fn entry ->
      account = get_in(providers, [entry.provider_id, :account_id])

      healthy =
        case Map.get(cursors, account, []) do
          [] -> nil
          list -> Enum.all?(list, &(&1.health == :healthy))
        end

      Map.put(entry, :cursor_healthy, healthy)
    end)
  end

  defp authorize(scope, mission_id) do
    case Policy.authorize(scope, :operate_mission, %{
           organization_id: scope.organization_id,
           mission_id: mission_id
         }) do
      :ok -> :ok
      {:error, _reason} -> {:error, :forbidden}
    end
  end
end
