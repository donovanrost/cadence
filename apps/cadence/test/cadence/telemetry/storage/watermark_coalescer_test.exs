defmodule Cadence.Telemetry.Storage.WatermarkCoalescerTest do
  use ExUnit.Case, async: true

  alias Cadence.DataSources.SourceWatermarkEvent
  alias Cadence.Telemetry.Storage.WatermarkCoalescer, as: Coalescer
  alias Ecto.Adapters.SQL.Sandbox

  defp attrs(mission_id, seconds, sample_id, count \\ 1) do
    at = DateTime.add(~U[2026-06-17 12:00:00.000000Z], seconds, :second)

    %{
      organization_id: "org",
      mission_id: mission_id,
      logical_source: :telemetry,
      data_source_id: "ds",
      source_binding_id: "binding",
      realm: :flight,
      replay_run_id: nil,
      dataset: nil,
      complete_through: at,
      latest_receipt_time: at,
      retention_starts_at: at,
      sample_count: count,
      confidence: :best_effort,
      reason: :telemetry_storage_write,
      observed_at: at,
      payload: %{
        kind: "telemetry_storage_write",
        observation_count: count,
        first_sample_id: sample_id,
        last_sample_id: sample_id,
        replay_run_id: nil
      }
    }
  end

  # An Agent does not understand the bus's call, so publishing a fact to it exits inside the
  # flush's transaction, after the rows are written: a failure that is not an `{:error, _}` return.
  defp dead_bus do
    {:ok, agent} = Agent.start(fn -> nil end)
    [event_bus: agent, publish_facts?: true]
  end

  defp pending(attrs, opts \\ []) do
    key = {
      SourceWatermarkEvent.new(attrs).source_watermark_key,
      opts[:event_bus],
      Keyword.get(opts, :publish_facts?, false)
    }

    [{^key, _version, _mission, merged}] = :ets.lookup(Coalescer, key)
    :ets.delete(Coalescer, key)
    merged
  end

  test "merge takes the earliest start, the latest watermark, the summed count and the window's ends" do
    merged = Coalescer.merge(attrs("m", 5, "a", 2), attrs("m", 2, "b", 3))

    assert merged.retention_starts_at == DateTime.add(~U[2026-06-17 12:00:00.000000Z], 2, :second)
    assert merged.latest_receipt_time == DateTime.add(~U[2026-06-17 12:00:00.000000Z], 5, :second)
    assert merged.complete_through == merged.latest_receipt_time
    assert merged.sample_count == 5
    assert merged.payload.observation_count == 5
    assert merged.payload.first_sample_id == "a"
    assert merged.payload.last_sample_id == "b"
  end

  test "concurrent writers to one row lose no observation" do
    mission = "mission-coalescer-#{System.unique_integer([:positive])}"

    1..200
    |> Task.async_stream(
      fn n -> Coalescer.observe(attrs(mission, n, "s#{n}")) end,
      max_concurrency: 32
    )
    |> Stream.run()

    merged = pending(attrs(mission, 0, "x"))
    assert merged.sample_count == 200
    assert merged.payload.observation_count == 200

    assert merged.latest_receipt_time ==
             DateTime.add(~U[2026-06-17 12:00:00.000000Z], 200, :second)

    assert merged.retention_starts_at == DateTime.add(~U[2026-06-17 12:00:00.000000Z], 1, :second)
  end

  test "rows of different keys stay separate" do
    mission = "mission-coalescer-#{System.unique_integer([:positive])}"
    other = put_in(attrs(mission, 1, "a"), [:source_binding_id], "other-binding")

    assert :ok = Coalescer.observe(attrs(mission, 1, "a"))
    assert :ok = Coalescer.observe(other)

    assert pending(attrs(mission, 1, "a")).sample_count == 1
    assert pending(other).sample_count == 1
  end

  describe "flush" do
    # These write to the database, so they need a sandbox owner of their own.
    setup do
      pid = Sandbox.start_owner!(Cadence.Repo, shared: false)
      on_exit(fn -> Sandbox.stop_owner(pid) end)
      :ok
    end

    test "with nothing pending for the scope it opens no transaction" do
      mission = "mission-coalescer-#{System.unique_integer([:positive])}"
      # No sandbox access is granted to this process in the test below, so a transaction would
      # raise: an empty flush must not touch the repo at all.
      assert :ok = Task.await(Task.async(fn -> Coalescer.flush_mission(mission) end))
      assert :ok = Task.await(Task.async(fn -> Coalescer.flush_key("no-such-key") end))
    end

    @tag :capture_log
    test "a window comes back when the write raises" do
      mission = "mission-coalescer-#{System.unique_integer([:positive])}"
      dead = dead_bus()
      bad = attrs(mission, 7, "a", 2)
      assert :ok = Coalescer.observe(bad, dead)

      assert {:error, _reason} = Coalescer.flush_mission(mission)

      restored = pending(bad, dead)
      assert restored.sample_count == 2
      assert restored.payload.first_sample_id == "a"
      assert restored.payload.observation_count == 2
    end

    @tag :capture_log
    test "a restored window merges ahead of one observed meanwhile" do
      mission = "mission-coalescer-#{System.unique_integer([:positive])}"
      dead = dead_bus()
      bad = attrs(mission, 7, "first", 2)
      assert :ok = Coalescer.observe(bad, dead)
      assert {:error, _reason} = Coalescer.flush_mission(mission)
      assert :ok = Coalescer.observe(attrs(mission, 9, "second", 3), dead)

      merged = pending(bad, dead)
      assert merged.sample_count == 5
      assert merged.payload.first_sample_id == "first"
      assert merged.payload.last_sample_id == "second"
    end
  end
end
