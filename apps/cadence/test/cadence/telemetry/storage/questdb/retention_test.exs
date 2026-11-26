defmodule Cadence.Telemetry.Storage.QuestDB.RetentionTest do
  use Cadence.UnitCase, async: false

  alias Cadence.Telemetry.Storage.QuestDB.{Retention, RetentionJob}

  @now ~U[2026-11-25 12:00:00Z]
  @columns Enum.map(~w(name maxTimestamp numRows diskSize active), &%{"name" => &1})

  defp partition(day, disk, active? \\ false) do
    [day, "#{day}T23:59:59.999999Z", 1_000, disk, active?]
  end

  # A fake /exec: answers the partition listing, records every statement.
  defp exec(dataset, test_pid, drop_result \\ {:ok, %{}}) do
    fn sql, _opts ->
      send(test_pid, {:sql, sql})

      if sql =~ "table_partitions",
        do: {:ok, %{"columns" => @columns, "dataset" => dataset}},
        else: drop_result
    end
  end

  defp settings(overrides \\ []), do: Keyword.merge([retention_days: 7], overrides)

  test "the retention is the one platform setting, 30 days by default" do
    assert Retention.retention_days(settings()) == 7
    assert Retention.retention_days([]) == 30
  end

  test "only inactive partitions wholly older than the cutoff expire" do
    cutoff = Retention.cutoff(@now, 7)
    assert cutoff == ~U[2026-11-18 12:00:00Z]

    partitions = [
      %{
        name: "2026-11-10",
        max_timestamp: ~U[2026-11-10 23:59:59Z],
        rows: 1,
        disk_bytes: 1,
        active?: false
      },
      # Straddles the cutoff: kept.
      %{
        name: "2026-11-18",
        max_timestamp: ~U[2026-11-18 23:59:59Z],
        rows: 1,
        disk_bytes: 1,
        active?: false
      },
      # Old but the partition ingest is writing: kept.
      %{
        name: "2026-11-01",
        max_timestamp: ~U[2026-11-01 23:59:59Z],
        rows: 1,
        disk_bytes: 1,
        active?: true
      },
      %{name: "empty", max_timestamp: nil, rows: 0, disk_bytes: 0, active?: false}
    ]

    assert ["2026-11-10"] = partitions |> Retention.expired(cutoff) |> Enum.map(& &1.name)
  end

  test "a run drops the expired partitions in one statement and reports what is left" do
    :telemetry.attach(
      "retention-test",
      [:cadence, :telemetry, :questdb_retention, :measured],
      fn _event, measurements, _meta, pid -> send(pid, {:measured, measurements}) end,
      self()
    )

    on_exit(fn -> :telemetry.detach("retention-test") end)

    dataset = [
      partition("2026-11-01", 100),
      partition("2026-11-10", 200),
      partition("2026-11-20", 400),
      partition("2026-11-25", 800, true)
    ]

    assert {:ok, report} =
             Retention.run(now: @now, settings: settings(), exec_fun: exec(dataset, self()))

    assert report.dropped == ["2026-11-01", "2026-11-10"]
    assert report.dropped_bytes == 300
    assert report.partitions == 2
    assert report.disk_bytes == 1_200

    assert_receive {:sql, "SELECT name" <> _}

    assert_receive {:sql,
                    "ALTER TABLE telemetry_observations DROP PARTITION LIST '2026-11-01', '2026-11-10'"}

    assert_receive {:measured, %{partitions: 2, disk_bytes: 1_200, dropped_partitions: 2}}
  end

  test "the newest partition is never dropped, even when it is old and not flagged active" do
    dataset = [partition("2026-09-01", 10), partition("2026-10-01", 20)]

    assert {:ok, %{dropped: ["2026-09-01"], partitions: 1}} =
             Retention.run(now: @now, settings: settings(), exec_fun: exec(dataset, self()))
  end

  test "maxTimestamp may arrive as microseconds" do
    micros = DateTime.to_unix(~U[2026-10-01 23:59:59Z], :microsecond)
    dataset = [["2026-10-01", micros, 1, 10, false], partition("2026-11-25", 5, true)]

    assert {:ok, %{dropped: ["2026-10-01"]}} =
             Retention.run(now: @now, settings: settings(), exec_fun: exec(dataset, self()))
  end

  test "nothing expired means no drop statement" do
    dataset = [partition("2026-11-24", 100), partition("2026-11-25", 200, true)]

    assert {:ok, %{dropped: [], partitions: 2, disk_bytes: 300}} =
             Retention.run(now: @now, settings: settings(), exec_fun: exec(dataset, self()))

    assert_receive {:sql, "SELECT name" <> _}
    refute_receive {:sql, "ALTER TABLE" <> _}
  end

  test "a run drops at most max_drops_per_run, oldest first" do
    dataset = for day <- 1..5, do: partition("2026-10-0#{day}", 10)

    assert {:ok, %{dropped: ["2026-10-01", "2026-10-02"]}} =
             Retention.run(
               now: @now,
               settings: settings(max_drops_per_run: 2),
               exec_fun: exec(dataset, self())
             )
  end

  # A fake /exec for two nodes dropping at once: the first listing is `before`, every later one
  # `after_race`; a drop naming `fail_on` fails ("another node got there"), any other succeeds.
  defp racing_exec(listing_before, listing_after, fail_on) do
    parent = self()
    {:ok, listings} = Agent.start_link(fn -> 0 end)

    fn sql, _opts ->
      send(parent, {:sql, sql})

      cond do
        sql =~ "table_partitions" ->
          first? = Agent.get_and_update(listings, &{&1 == 0, &1 + 1})

          {:ok,
           %{
             "columns" => @columns,
             "dataset" => if(first?, do: listing_before, else: listing_after)
           }}

        sql =~ fail_on ->
          {:error, :partition_does_not_exist}

        true ->
          {:ok, %{}}
      end
    end
  end

  test "a drop another node partly made is retried for what remains" do
    active = partition("2026-11-25", 5, true)
    before = [partition("2026-10-01", 10), partition("2026-10-02", 10), active]
    # By the re-read, the other node has dropped 2026-10-01.
    exec =
      racing_exec(before, [partition("2026-10-02", 10), active], "'2026-10-01', '2026-10-02'")

    assert {:ok, %{dropped: ["2026-10-01", "2026-10-02"]}} =
             Retention.run(now: @now, settings: settings(), exec_fun: exec)

    assert_receive {:sql,
                    "ALTER TABLE telemetry_observations DROP PARTITION LIST '2026-10-01', '2026-10-02'"}

    assert_receive {:sql, "ALTER TABLE telemetry_observations DROP PARTITION LIST '2026-10-02'"}
  end

  test "a drop another node already made in full is success, with no retry" do
    active = partition("2026-11-25", 5, true)
    before = [partition("2026-10-01", 10), active]
    exec = racing_exec(before, [active], "2026-10-01")

    assert {:ok, %{dropped: ["2026-10-01"]}} =
             Retention.run(now: @now, settings: settings(), exec_fun: exec)

    assert_receive {:sql, "ALTER TABLE" <> _}
    refute_receive {:sql, "ALTER TABLE" <> _}
  end

  test "failures are returned, not raised" do
    dataset = [partition("2026-10-01", 10), partition("2026-11-25", 10, true)]

    assert {:error, {:drop_partition_failed, :boom}} =
             Retention.run(
               now: @now,
               settings: settings(),
               exec_fun: exec(dataset, self(), {:error, :boom})
             )

    assert {:error, :unreachable} =
             Retention.run(
               now: @now,
               settings: settings(),
               exec_fun: fn _sql, _opts -> {:error, :unreachable} end
             )
  end

  test "the job runs the retention on demand and on its timer" do
    parent = self()

    run_fun = fn _opts ->
      send(parent, :ran) && {:ok, %{dropped: [], partitions: 0, disk_bytes: 0}}
    end

    start_supervised!({RetentionJob, interval_ms: 20, run_fun: run_fun})

    assert {:ok, %{dropped: []}} = RetentionJob.run_now()
    assert_receive :ran
    assert_receive :ran, 500
  end
end
