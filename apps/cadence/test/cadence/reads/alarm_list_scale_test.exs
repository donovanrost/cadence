defmodule Cadence.Reads.AlarmListScaleTest do
  @moduledoc """
  What an alarm list page costs on the runtime's alarm states at fleet scale (#451 T3c): 1,000
  spacecraft x 200 parameters = 200,000 latest states, 5% of them alarming (critical or warning),
  the rest normal. The page sorts the mission's states by level rank, newest receipt, spacecraft
  and parameter (`SemanticObservations.AlarmPage`), and a cursor continues from the last row's key.
  Measured for `state: active` (the default) and `state: all` (every row, the worst case), the
  first page and a cursor 100,000 rows deep, each several times (p50, max). Excluded by default;
  `mix test --include scale`, or the Scale tests workflow.
  """
  use Cadence.DataCase, async: false

  @moduletag :scale
  @moduletag timeout: 900_000

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Reads.AlarmList
  alias Cadence.SemanticObservations.{AlarmPage, LatestAlarmStateRow}

  @org "org-alarm-scale"
  @mission "mission-alarm-scale"
  @craft 1_000
  @parameters 200
  @runs 5

  setup do
    persist_mission_scope(@org, @mission)
    seed()
    :ok
  end

  # Every 20th state alarms (alternating critical and warning); receipt times spread over a day.
  defp seed do
    now = DateTime.utc_now()
    base = ~U[2026-11-27 00:00:00.000000Z]

    for chunk <-
          Stream.chunk_every(
            for(craft <- 1..@craft, param <- 1..@parameters, do: {craft, param}),
            4_000
          ) do
      rows =
        for {craft, param} <- chunk do
          n = craft * @parameters + param
          id = "sc-#{String.pad_leading("#{craft}", 4, "0")}"
          at = DateTime.add(base, rem(n * 7919, 86_400), :second)

          %{
            organization_id: @org,
            mission_id: @mission,
            spacecraft_scope_id: id,
            spacecraft_id: id,
            parameter_id: "p#{String.pad_leading("#{param}", 3, "0")}",
            policy_id: "policy-#{param}",
            evaluation_id: "eval-#{n}",
            transition_id: "tr-#{n}",
            effective_state:
              cond do
                rem(n, 20) != 0 -> "normal"
                rem(div(n, 20), 2) == 0 -> "critical"
                true -> "warning"
              end,
            generation_time: at,
            receipt_time: at,
            state_document: JsonDocument.wrap_value(%{}),
            inserted_at: now,
            updated_at: now
          }
        end

      Repo.insert_all(LatestAlarmStateRow, rows)
    end

    Repo.query!("ANALYZE semantic_latest_alarm_states")
  end

  defp timed(filters) do
    times =
      for _ <- 1..@runs do
        {us, {:ok, page}} = :timer.tc(fn -> AlarmList.load(@org, @mission, filters) end)
        {us / 1_000, page}
      end

    {ms, pages} = Enum.unzip(times)
    sorted = Enum.sort(ms)
    {Enum.at(sorted, div(@runs, 2)), List.last(sorted), hd(pages)}
  end

  # The cursor of the row `offset` rows into the list for `filters`: the sort key of that row.
  defp cursor_at(filters, offset) do
    critical = Cadence.SemanticRuntime.AlarmLevel.states_of(:critical)
    caution = Cadence.SemanticRuntime.AlarmLevel.states_of(:caution)
    import Ecto.Query

    row =
      from(r in LatestAlarmStateRow,
        where: r.organization_id == ^@org and r.mission_id == ^@mission,
        where: ^state_clause(filters[:state]),
        order_by: [
          asc:
            fragment(
              "(CASE WHEN ? = ANY(?) THEN 0 WHEN ? = ANY(?) THEN 1 ELSE 2 END)",
              r.effective_state,
              ^critical,
              r.effective_state,
              ^caution
            ),
          desc: r.receipt_time,
          asc: r.spacecraft_id,
          asc: r.parameter_id
        ],
        offset: ^offset,
        limit: 1
      )
      |> Repo.one()

    row |> AlarmPage.key() |> :erlang.term_to_binary() |> Base.url_encode64(padding: false)
  end

  defp state_clause("active") do
    import Ecto.Query
    dynamic([r], r.effective_state in ^Cadence.SemanticRuntime.AlarmLevel.alarm_states_text())
  end

  defp state_clause(_all), do: true

  defp report(label, filters) do
    {p50, max, page} = timed(filters)

    IO.puts(
      "ALARM PAGE #{label}: p50 #{Float.round(p50, 1)} ms, max #{Float.round(max, 1)} ms " <>
        "(#{length(page.alarms)} rows, total #{page.total}, #{@runs} runs)"
    )

    {p50, max}
  end

  # Where a first page's time goes: the page's rows, the count over the same WHERE, the summary.
  defp breakdown(label, filters) do
    parts = [
      rows: fn -> AlarmPage.rows(@org, @mission, filters, nil, 100) end,
      count: fn -> AlarmPage.count(@org, @mission, filters) end,
      summary: fn -> AlarmPage.summary(@org, @mission) end
    ]

    timings =
      for {name, fun} <- parts do
        ms = for _ <- 1..@runs, do: elem(:timer.tc(fun), 0) / 1_000
        {name, ms |> Enum.sort() |> Enum.at(div(@runs, 2)) |> Float.round(1)}
      end

    IO.puts("ALARM PAGE #{label}, p50 by part (ms): #{inspect(timings)}")
  end

  test "an active page and a deep cursor, and an all page and a deep cursor" do
    assert Repo.aggregate(LatestAlarmStateRow, :count) == @craft * @parameters

    active = %{state: "active", limit: 100}
    all = %{state: "all", limit: 100}

    report("active, first page", active)
    deep_active = Map.put(active, :cursor, cursor_at(active, 5_000))
    report("active, cursor 5,000 rows deep", deep_active)

    breakdown("active", Map.take(active, [:state]))
    report("all, first page", all)
    breakdown("all", Map.take(all, [:state]))
    deep_all = Map.put(all, :cursor, cursor_at(all, 100_000))
    report("all, cursor 100,000 rows deep", deep_all)

    assert {:ok, %{alarms: [_ | _]}} = AlarmList.load(@org, @mission, deep_all)
  end
end
