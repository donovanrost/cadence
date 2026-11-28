defmodule Cadence.Reads.PointConditions do
  @moduledoc """
  The current condition of every point of one spacecraft (#143), paged.

  A point's condition is the runtime's (`:catalog_monitoring`, `semantic_latest_alarm_states`;
  #451 T3d, it also read the ground limit states before): written on every state transition, so it
  is live and its `receipt_time` is when the parameter entered the state. A parameter that never
  left normal has no row; neither has a monitoring rule that never changed state. The inventory is
  the compiled plan's (`MonitoredParameters`): a parameter the plan evaluates on this spacecraft
  that has a sample but no state yet is `evaluated: false` (nominal, no time), which the screen
  says. Every row's `source` is `catalog_monitoring`; `evaluated_at`, `raw_limit_state` and `value`
  are `null`, and `entered_at_is_lower_bound` is `false`.

  **Staleness.** A point is stale when its newest sample is older than `stale_after_s` (the one
  setting Fleet uses, `FleetStatus.stale_after_s/0`). The newest sample time is the current-value
  store's, which is node-local: correct on the node that owns the spacecraft's partition, empty on
  another. It is merged with the durable history store's per-point receipts
  (`DurableReceiptCache`, as Fleet does for spacecraft), so a node that does not own the
  spacecraft still knows when it was last heard. In production the history is QuestDB (`LATEST ON`
  per point); the Postgres sample store answers in dev and test only. Only a point neither knows is `:unknown` when the
  history store did not answer (`telemetry: :degraded`) and `:stale` when it did (never sampled).

  **Order and paging.** By the point's worst rank (critical, caution, stale, everything else),
  then point id, then policy, so a point's rows stay together. The cursor is that key of the last
  row; rows that change between pages neither repeat nor skip one that stays. The spacecraft's rows
  (its points, not the fleet) are merged in memory, because staleness is not in the database.
  """

  alias Cadence.Ops.PointCatalog
  alias Cadence.Reads.{DurableReceiptCache, FleetStatus, MonitoredParameters, PointInfo}
  alias Cadence.SemanticObservations
  alias Cadence.SemanticRuntime.AlarmLevel
  alias Cadence.SpacecraftStore
  alias Cadence.Telemetry.{CurrentValueStore, SpacecraftReceipts}

  @default_limit 100
  @max_limit 200
  @source_order %{catalog_monitoring: 1}

  @spec load(binary(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, :invalid_cursor | :spacecraft_not_found}
  def load(organization_id, mission_id, spacecraft_id, opts \\ []) do
    with {:ok, after_key} <- decode_cursor(Keyword.get(opts, :cursor)),
         {:ok, _spacecraft} <- spacecraft(organization_id, mission_id, spacecraft_id) do
      now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
      stale_after_s = Keyword.get_lazy(opts, :stale_after_s, &FleetStatus.stale_after_s/0)
      limit = page_size(Keyword.get(opts, :limit))

      points = PointCatalog.list_points(organization_id, mission_id)
      {samples, telemetry} = last_samples(organization_id, mission_id, spacecraft_id)

      rows =
        organization_id
        |> rows(mission_id, spacecraft_id, points, samples, opts)
        |> Enum.map(&freshness(&1, samples, telemetry, now, stale_after_s))
        |> rank_points()
        |> filter(Keyword.get(opts, :state), Keyword.get(opts, :query))

      page_rows = page(rows, after_key, limit + 1)
      {page, more?} = split_page(page_rows, limit)

      {:ok,
       %{
         observed_at: now,
         stale_after_s: stale_after_s,
         telemetry: telemetry,
         counts: counts(rows),
         next_cursor: if(more?, do: page |> List.last() |> sort_key() |> encode_cursor()),
         points: enrich(page, organization_id, mission_id)
       }}
    end
  end

  defp spacecraft(organization_id, mission_id, spacecraft_id) do
    case SpacecraftStore.fetch_spacecraft(organization_id, mission_id, spacecraft_id) do
      {:ok, spacecraft} -> {:ok, spacecraft}
      {:error, _not_found} -> {:error, :spacecraft_not_found}
    end
  end

  # -- rows ---------------------------------------------------------------------------------------

  defp rows(organization_id, mission_id, spacecraft_id, points, samples, opts) do
    by_parameter =
      for %{parameter_id: p, point_id: id} <- points, is_binary(p), into: %{}, do: {p, id}

    names = Map.new(points, &{&1.point_id, Map.get(&1, :point_name) || &1.point_id})

    live = SemanticObservations.list_for_spacecraft(organization_id, mission_id, spacecraft_id)

    live_rows = Enum.map(live, &live_row(&1, by_parameter, names))

    evaluated = MapSet.new(live_rows, & &1.point_id)

    live_rows ++
      not_evaluated_rows(
        organization_id,
        mission_id,
        spacecraft_id,
        by_parameter,
        evaluated,
        samples,
        names,
        opts
      )
  end

  defp live_row(row, by_parameter, names) do
    point_id = Map.get(by_parameter, row.parameter_id, row.parameter_id)

    %{
      source: :catalog_monitoring,
      point_id: point_id,
      point_name: Map.get(names, point_id, row.parameter_id),
      policy_id: row.policy_id,
      condition: live_condition(row.effective_state),
      raw_limit_state: nil,
      normalized_state: nil,
      evaluated: true,
      evaluated_at: nil,
      # A state is written on a transition only, so its time is when the parameter entered it.
      entered_at: row.receipt_time,
      entered_at_is_lower_bound: false,
      value: nil,
      state_received_at: row.receipt_time
    }
  end

  # A point the compiled monitoring plan evaluates on this spacecraft (#451 T3a), with a sample and
  # no state yet. The plan, not the limit definitions, is the inventory.
  defp not_evaluated_rows(
         organization_id,
         mission_id,
         spacecraft_id,
         by_parameter,
         evaluated,
         samples,
         names,
         opts
       ) do
    monitored =
      case MonitoredParameters.for_spacecraft(organization_id, mission_id, spacecraft_id, opts) do
        {:ok, parameters} -> parameters
        :none -> MapSet.new()
      end

    monitored
    |> Enum.map(&Map.get(by_parameter, &1, &1))
    |> Enum.sort()
    |> Enum.filter(&(Map.has_key?(samples, &1) and not MapSet.member?(evaluated, &1)))
    |> Enum.map(fn point_id ->
      %{
        source: :catalog_monitoring,
        point_id: point_id,
        point_name: Map.get(names, point_id, point_id),
        policy_id: nil,
        condition: :nominal,
        raw_limit_state: nil,
        normalized_state: nil,
        evaluated: false,
        evaluated_at: nil,
        entered_at: nil,
        entered_at_is_lower_bound: false,
        value: nil,
        state_received_at: nil
      }
    end)
  end

  # The mapping the alarm episodes use (`Alarms.Sources`).
  defp live_condition(state) do
    case AlarmLevel.level(state) do
      :critical -> :critical
      :caution -> :caution
      _normal_or_ignored -> :nominal
    end
  end

  # -- freshness ----------------------------------------------------------------------------------

  # The newest sample time per point: this node's current-value store, then the durable history
  # (cached), the newer of the two.
  defp last_samples(organization_id, mission_id, spacecraft_id) do
    live =
      mission_id
      |> CurrentValueStore.latest_values_for_mission(spacecraft_id: spacecraft_id)
      |> Enum.reject(&is_nil(&1.receipt_time))
      |> Enum.group_by(& &1.point_id, & &1.receipt_time)
      |> Map.new(fn {point, times} -> {point, Enum.max(times, DateTime)} end)

    durable =
      DurableReceiptCache.get({__MODULE__, organization_id, mission_id, spacecraft_id}, fn ->
        SpacecraftReceipts.latest_by_point(organization_id, mission_id, spacecraft_id)
      end)

    {Map.merge(durable.receipts, live, fn _point, a, b -> Enum.max([a, b], DateTime) end),
     durable.telemetry}
  end

  defp freshness(row, samples, telemetry, now, stale_after_s) do
    last = Map.get(samples, row.point_id)

    fresh =
      cond do
        is_nil(last) and telemetry == :degraded -> :unknown
        is_nil(last) -> :stale
        DateTime.diff(now, last) > stale_after_s -> :stale
        true -> :fresh
      end

    Map.merge(row, %{last_sample_at: last, freshness: fresh})
  end

  # -- order and paging ---------------------------------------------------------------------------

  # A point's rank is its worst row's: critical 0, caution 1, a stale (or unknown) point 2, the
  # rest 3. Every row of a point carries it, so the point's rows stay together.
  defp rank_points(rows) do
    ranks =
      rows
      |> Enum.group_by(& &1.point_id)
      |> Map.new(fn {point, point_rows} -> {point, point_rank(point_rows)} end)

    Enum.map(rows, &Map.put(&1, :rank, Map.fetch!(ranks, &1.point_id)))
  end

  defp point_rank(rows) do
    conditions = Enum.map(rows, & &1.condition)

    cond do
      :critical in conditions -> 0
      :caution in conditions -> 1
      Enum.any?(rows, &(&1.freshness != :fresh)) -> 2
      true -> 3
    end
  end

  defp sort_key(row),
    do: {row.rank, row.point_id, Map.fetch!(@source_order, row.source), row.policy_id || ""}

  defp page(rows, after_key, count) do
    rows
    |> Enum.sort_by(&sort_key/1)
    |> Enum.drop_while(fn row -> after_key != nil and sort_key(row) <= after_key end)
    |> Enum.take(count)
  end

  defp split_page(rows, limit) when length(rows) > limit, do: {Enum.take(rows, limit), true}
  defp split_page(rows, _limit), do: {rows, false}

  defp filter(rows, state, query),
    do: Enum.filter(rows, &((state != "attention" or &1.rank < 3) and matches?(&1, query)))

  defp matches?(_row, query) when query in [nil, ""], do: true

  defp matches?(row, query) do
    needle = String.downcase(query)

    String.contains?(String.downcase(row.point_id), needle) or
      String.contains?(String.downcase(row.point_name), needle)
  end

  defp counts(rows) do
    %{
      total: length(rows),
      critical: Enum.count(rows, &(&1.condition == :critical)),
      caution: Enum.count(rows, &(&1.condition == :caution)),
      stale: Enum.count(rows, &(&1.freshness == :stale)),
      unknown: Enum.count(rows, &(&1.freshness == :unknown)),
      not_evaluated: Enum.count(rows, &(not &1.evaluated))
    }
  end

  defp page_size(limit) when is_integer(limit) and limit in 1..@max_limit, do: limit
  defp page_size(_limit), do: @default_limit

  defp encode_cursor(key),
    do: key |> :erlang.term_to_binary() |> Base.url_encode64(padding: false)

  defp decode_cursor(nil), do: {:ok, nil}

  defp decode_cursor(cursor) when is_binary(cursor) and byte_size(cursor) <= 1_024 do
    with {:ok, binary} <- Base.url_decode64(cursor, padding: false),
         {:ok, key} <- safe_term(binary),
         {rank, point, source, policy}
         when rank in 0..3 and is_binary(point) and source in [0, 1] and is_binary(policy) <- key do
      {:ok, key}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end

  defp decode_cursor(_cursor), do: {:error, :invalid_cursor}

  defp safe_term(binary) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    ArgumentError -> :error
  end

  # -- the page's extras --------------------------------------------------------------------------

  # The unit of each point of the page.
  defp enrich(page, organization_id, mission_id) do
    units = if page == [], do: %{}, else: PointInfo.by_id(organization_id, mission_id)

    Enum.map(page, fn row ->
      row
      |> Map.put(:unit, units |> Map.get(row.point_id, PointInfo.unknown()) |> Map.get(:unit))
      |> Map.drop([:normalized_state, :rank])
    end)
  end
end
