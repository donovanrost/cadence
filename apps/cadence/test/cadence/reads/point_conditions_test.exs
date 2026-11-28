defmodule Cadence.Reads.PointConditionsTest do
  @moduledoc """
  A spacecraft's points from both stores (#143): ground-limit states and live monitoring alarms,
  labelled by source, critical and caution first, a stale point named stale, a point the compiled plan monitors
  and a sample but no state shown as not evaluated, paged with a cursor that never repeats or
  skips a row, with a fixed number of queries however many points there are.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Limits.{Event, Store}
  alias Cadence.MonitoringPlanFixtures
  alias Cadence.Reads.PointConditions
  alias Cadence.SemanticObservations.LatestAlarmStateRow
  alias Cadence.SemanticRuntime.{PlanDecoder, ThresholdLimits}
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore
  alias Cadence.Telemetry.{CurrentValueStore, Sample, SampleRecords}
  alias Cadence.Telemetry.CurrentValueStore.ETS

  @org "org-point-conditions"
  @mission "mission-point-conditions"
  @now ~U[2026-11-27 12:00:00.000000Z]
  @states [:green, :blue, :yellow_high, :red_high]

  setup do
    persist_mission_scope(@org, @mission)
    persist_mission_scope(@org, "#{@mission}-other")
    saved = Application.get_env(:cadence, :durable_receipts_ttl_ms)
    # No cache between tests: the durable answer is asked every time.
    Application.put_env(:cadence, :durable_receipts_ttl_ms, 0)

    on_exit(fn ->
      if saved,
        do: Application.put_env(:cadence, :durable_receipts_ttl_ms, saved),
        else: Application.delete_env(:cadence, :durable_receipts_ttl_ms)
    end)

    # This node's current-value store, as in production (the suite's default is the Postgres one).
    cache = CurrentValueStore.policy(module: ETS)
    saved_store = Application.get_env(:cadence, :telemetry_current_value_store)
    Application.put_env(:cadence, :telemetry_current_value_store, module: ETS)

    on_exit(fn ->
      if saved_store,
        do: Application.put_env(:cadence, :telemetry_current_value_store, saved_store),
        else: Application.delete_env(:cadence, :telemetry_current_value_store)
    end)

    start_supervised!(CurrentValueStore.child_spec(cache))

    for n <- 1..3, do: craft(n)
    :ok
  end

  defp craft(n) do
    {:ok, _} =
      SpacecraftStore.persist_spacecraft(
        @org,
        Spacecraft.new(%{
          spacecraft_id: "sc-#{n}",
          organization_id: @org,
          mission_id: @mission,
          display_name: "SC-#{n}",
          scid: n
        })
      )
  end

  defp ground!(craft, point, state, opts \\ []) do
    at = Keyword.get(opts, :at, DateTime.add(@now, -600, :second))

    event = %Event{
      limit_event_id: "ev-#{craft}-#{point}-#{state}",
      mission_id: Keyword.get(opts, :mission, @mission),
      spacecraft_id: craft,
      point_id: point,
      point_name: "name #{point}",
      source_sample_type: :telemetry_sample,
      sample_id: "s-#{point}",
      limit_definition_id: "d",
      limit_definition_version: 1,
      limit_set_name: "d",
      evaluated_value: 5,
      limit_state: state,
      normalized_state: ThresholdLimits.normalize_state(state),
      violation: ThresholdLimits.violation?(state),
      generation_time: nil,
      receipt_time: at,
      provenance: %{}
    }

    {:ok, _} = Store.persist_latest_states(Repo, [event])
  end

  defp live!(craft, parameter, state, opts \\ []) do
    at = Keyword.get(opts, :at, DateTime.add(@now, -300, :second))

    %{
      organization_id: @org,
      mission_id: Keyword.get(opts, :mission, @mission),
      spacecraft_id: craft,
      parameter_id: parameter,
      policy_id: Keyword.get(opts, :policy, "pol-1"),
      evaluation_id: "eval-#{craft}-#{parameter}",
      transition_id: "tr-#{craft}-#{parameter}",
      effective_state: state,
      generation_time: at,
      receipt_time: at
    }
    |> LatestAlarmStateRow.changeset()
    |> Repo.insert!()
  end

  defp sample(craft, point, at) do
    %Sample{
      sample_id: "s-#{craft}-#{point}-#{DateTime.to_unix(at)}",
      mission_id: @mission,
      spacecraft_id: craft,
      point_id: point,
      point_name: point,
      packet_definition_id: "pd",
      packet_definition_version: 1,
      packet_id: "pk",
      evidence_id: "ev",
      raw_value: 1,
      engineering_value: 1,
      quality_state: :good,
      generation_time: at,
      receipt_time: at,
      provenance: %{}
    }
  end

  defp heard!(craft, point, seconds_ago) do
    at = DateTime.add(@now, -seconds_ago, :second)
    :ok = CurrentValueStore.record_samples([sample(craft, point, at)])
  end

  defp load(craft \\ "sc-1", opts \\ []) do
    {:ok, result} =
      PointConditions.load(@org, @mission, craft, Keyword.merge([now: @now], opts))

    result
  end

  defp ids(result), do: Enum.map(result.points, &{&1.point_id, &1.source})

  test "a live alarm shows with no ground job having run, labelled by its source" do
    heard!("sc-1", "HK.mode", 10)
    live!("sc-1", "HK.mode", "critical")

    assert [row] = load().points
    assert row.source == :catalog_monitoring
    assert row.condition == :critical
    assert row.point_id == "HK.mode"
    assert row.policy_id == "pol-1"
    assert row.evaluated_at == nil
    # A live state is written on a transition: its time is when the point entered it.
    assert row.entered_at == DateTime.add(@now, -300, :second)
    assert row.freshness == :fresh
  end

  test "a point in both stores has one row per source, adjacent, worst first" do
    heard!("sc-1", "HK.a", 10)
    heard!("sc-1", "HK.b", 10)
    ground!("sc-1", "HK.a", :green)
    live!("sc-1", "HK.a", "warning")
    ground!("sc-1", "HK.b", :green)

    assert ids(load()) == [
             {"HK.a", :ground_limit},
             {"HK.a", :catalog_monitoring},
             {"HK.b", :ground_limit}
           ]

    [ground, live, _b] = load().points
    assert {ground.condition, live.condition} == {:nominal, :caution}
    assert ground.evaluated_at != nil
  end

  test "critical first, then caution, then stale, then the healthy; a stale critical stays critical" do
    for {p, age} <- [{"HK.ok", 10}, {"HK.stale", 7_200}, {"HK.warn", 10}, {"HK.crit", 7_200}],
        do: heard!("sc-1", p, age)

    ground!("sc-1", "HK.ok", :green)
    ground!("sc-1", "HK.stale", :green)
    ground!("sc-1", "HK.warn", :yellow_high)
    ground!("sc-1", "HK.crit", :red_high)

    result = load("sc-1", stale_after_s: 900)

    assert Enum.map(result.points, &{&1.point_id, &1.condition, &1.freshness}) == [
             {"HK.crit", :critical, :stale},
             {"HK.warn", :caution, :fresh},
             {"HK.stale", :nominal, :stale},
             {"HK.ok", :nominal, :fresh}
           ]

    assert %{critical: 1, caution: 1, stale: 2, total: 4} = result.counts
  end

  test "the sample time comes from the durable history when this node's store has none" do
    # Not in the current-value store (another node owns the partition), but in the history.
    # (The history rows name a packet record this test does not create.)
    Repo.query!("SET LOCAL session_replication_role = replica")

    :ok =
      SampleRecords.persist_samples([
        sample("sc-1", "HK.far", DateTime.add(@now, -30, :second)),
        sample("sc-1", "HK.old", DateTime.add(@now, -9_000, :second))
      ])

    Repo.query!("SET LOCAL session_replication_role = origin")

    ground!("sc-1", "HK.far", :green)
    ground!("sc-1", "HK.old", :green)
    ground!("sc-1", "HK.never", :green)

    rows = Map.new(load().points, &{&1.point_id, &1})

    assert rows["HK.far"].freshness == :fresh
    assert rows["HK.far"].last_sample_at == DateTime.add(@now, -30, :second)
    assert rows["HK.old"].freshness == :stale
    # Never sampled on either: stale, not healthy and not missing.
    assert rows["HK.never"].freshness == :stale
    assert rows["HK.never"].last_sample_at == nil
  end

  test "the staleness threshold is Fleet's setting" do
    saved = Application.get_env(:cadence, :fleet_stale_after_s)
    Application.put_env(:cadence, :fleet_stale_after_s, 60)

    on_exit(fn ->
      if saved,
        do: Application.put_env(:cadence, :fleet_stale_after_s, saved),
        else: Application.delete_env(:cadence, :fleet_stale_after_s)
    end)

    heard!("sc-1", "HK.a", 120)
    ground!("sc-1", "HK.a", :green)

    result = load()
    assert result.stale_after_s == 60
    assert [%{freshness: :stale}] = result.points
  end

  describe "the inventory is the compiled plan's (#451 T3a)" do
    setup do
      # One policy on a parameter, a craft whose override turns it off, and a craft-only one.
      plans =
        MonitoringPlanFixtures.compile!(
          @org,
          @mission,
          [
            {"temp", "/parameters/temperature", above: 10},
            {"mode", "/parameters/mode", above: 100, disabled: true}
          ],
          [
            {:override, "temp", "temp-sc-2", ["sc-2"], disabled: true},
            {:craft_only, "mode-own", "/parameters/mode", ["sc-1"], above: 1}
          ]
        )

      entries = PlanDecoder.decode(plans).monitoring

      id_of = fn threshold ->
        Enum.find_value(entries, fn
          %{scope: :mission, default_rules: [rule | _]} = e ->
            if (rule["value"] || rule[:value]) == threshold, do: e.parameter_id

          _other ->
            nil
        end)
      end

      %{
        opts: [revision_id: plans.monitoring.mission_model_revision_id],
        temp: id_of.(10),
        mode: id_of.(100)
      }
    end

    test "a monitored point with a sample and no state is not evaluated, and says which rule source",
         c do
      heard!("sc-1", c.temp, 10)

      assert [row] = load("sc-1", c.opts).points

      assert {row.point_id, row.source, row.condition, row.evaluated} ==
               {c.temp, :catalog_monitoring, :nominal, false}

      assert row.evaluated_at == nil and row.entered_at == nil and row.policy_id == nil
      assert load("sc-1", c.opts).counts.not_evaluated == 1
    end

    test "a craft's own entries decide: its craft-only policy lists, a disabled override does not",
         c do
      for craft <- ["sc-1", "sc-2", "sc-3"],
          point <- [c.temp, c.mode],
          do: heard!(craft, point, 10)

      assert Enum.sort(ids(load("sc-1", c.opts))) ==
               Enum.sort([{c.temp, :catalog_monitoring}, {c.mode, :catalog_monitoring}])

      # sc-2's override turns the temperature off; the mode policy is sc-1's only.
      assert ids(load("sc-2", c.opts)) == []
      assert ids(load("sc-3", c.opts)) == [{c.temp, :catalog_monitoring}]
    end

    test "a point with no sample on the craft, or already in a state, is not listed again", c do
      assert load("sc-1", c.opts).points == []

      heard!("sc-1", c.temp, 10)
      live!("sc-1", c.temp, "critical")

      assert [%{source: :catalog_monitoring, evaluated: true, condition: :critical}] =
               load("sc-1", c.opts).points
    end

    test "a mission with no monitoring plan lists no inventory", c do
      heard!("sc-1", c.temp, 10)
      assert load("sc-1", revision_id: nil).points == []
    end
  end

  test "ground rows with no evaluation history before them say the entry time is a lower bound" do
    heard!("sc-1", "HK.a", 10)
    ground!("sc-1", "HK.a", :red_high)

    assert [%{entered_at: nil, entered_at_is_lower_bound: true}] = load().points
  end

  test "another spacecraft's and another mission's rows never appear, and an unknown one is refused" do
    heard!("sc-1", "HK.a", 10)
    ground!("sc-2", "HK.b", :red_high)
    live!("sc-2", "HK.c", "critical")
    live!("sc-1", "HK.x", "critical", mission: "#{@mission}-other")

    assert ids(load()) == []
    assert ids(load("sc-2")) == [{"HK.b", :ground_limit}, {"HK.c", :catalog_monitoring}]

    assert {:error, :spacecraft_not_found} = PointConditions.load(@org, @mission, "sc-nope")
  end

  test "the attention filter keeps the critical, caution and stale points; a query narrows by id or name" do
    for p <- ~w(HK.a HK.b HK.c), do: heard!("sc-1", p, 10)
    ground!("sc-1", "HK.a", :green)
    ground!("sc-1", "HK.b", :red_high)
    ground!("sc-1", "HK.c", :green)

    assert load("sc-1", state: "attention").points |> Enum.map(& &1.point_id) == ["HK.b"]
    assert load("sc-1", query: "name HK.c").points |> Enum.map(& &1.point_id) == ["HK.c"]
    assert load("sc-1", query: "hk.a").counts.total == 1
  end

  test "paging walks every row exactly once, in order, and a bad cursor is refused" do
    points = for n <- 1..11, do: "HK.p#{String.pad_leading("#{n}", 2, "0")}"

    for {p, n} <- Enum.with_index(points) do
      heard!("sc-1", p, if(rem(n, 4) == 0, do: 7_200, else: 10))
      ground!("sc-1", p, Enum.at(@states, rem(n, 4)))
      if rem(n, 3) == 0, do: live!("sc-1", p, "warning")
    end

    all = load("sc-1", limit: 200)
    assert all.next_cursor == nil

    paged =
      Stream.unfold(:start, fn
        :done ->
          nil

        cursor ->
          page = load("sc-1", limit: 3, cursor: if(cursor == :start, do: nil, else: cursor))
          {ids(page), page.next_cursor || :done}
      end)
      |> Enum.concat()

    assert paged == ids(all)
    assert length(paged) == length(Enum.uniq(paged))

    assert {:error, :invalid_cursor} =
             PointConditions.load(@org, @mission, "sc-1", cursor: "not-a-cursor")
  end

  test "the number of queries does not depend on the number of points" do
    count = fn ->
      handler = "pc-queries-#{System.unique_integer([:positive])}"
      parent = self()

      :telemetry.attach(
        handler,
        [:cadence, :repo, :query],
        fn _event, _measurements, _meta, _ -> send(parent, :query) end,
        nil
      )

      flush()
      load("sc-1", limit: 200)
      :telemetry.detach(handler)
      flush()
    end

    for n <- 1..3,
        do:
          (
            heard!("sc-1", "HK.q#{n}", 10)
            ground!("sc-1", "HK.q#{n}", :red_high)
          )

    few = count.()

    for n <- 4..40 do
      heard!("sc-1", "HK.q#{n}", 10)
      ground!("sc-1", "HK.q#{n}", :red_high)
      live!("sc-1", "HK.q#{n}", "warning")
    end

    assert count.() == few
  end

  defp flush(n \\ 0) do
    receive do
      :query -> flush(n + 1)
    after
      0 -> n
    end
  end
end
