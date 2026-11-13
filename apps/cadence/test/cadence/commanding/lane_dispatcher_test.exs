defmodule Cadence.Commanding.LaneDispatcherTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Commanding.LaneDispatcher

  test "drain releases every immediately eligible command before reporting an empty lane" do
    test_pid = self()

    dispatch_fun =
      dispatch_sequence([
        {:ok, %{command_request_id: "command-1"}},
        {:ok, %{command_request_id: "command-2"}},
        {:error, :command_queue_lane_empty}
      ])

    lane_dispatcher =
      start_lane_dispatcher!(
        dispatch_fun: fn organization_id, mission_id, queue_lane_key, released_by, opts ->
          send(test_pid, {:dispatch_attempt, organization_id, mission_id, queue_lane_key})
          dispatch_fun.(organization_id, mission_id, queue_lane_key, released_by, opts)
        end
      )

    monitor = Process.monitor(lane_dispatcher)

    assert {:ok, %{released_count: 2, status: :empty, next_not_before: nil}} =
             LaneDispatcher.drain(lane_dispatcher)

    assert_receive {:dispatch_attempt, _organization_id, _mission_id, _queue_lane_key}
    assert_receive {:dispatch_attempt, _organization_id, _mission_id, _queue_lane_key}
    assert_receive {:dispatch_attempt, _organization_id, _mission_id, _queue_lane_key}
    refute_received {:dispatch_attempt, _organization_id, _mission_id, _queue_lane_key}
    assert_receive {:DOWN, ^monitor, :process, ^lane_dispatcher, :normal}
  end

  test "drain reports future work as quiescent and cancels its timer before the next drain" do
    now = ~U[2026-08-18 12:00:00Z]
    next_not_before = DateTime.add(now, 60, :second)

    dispatch_fun =
      dispatch_sequence([
        {:error, {:command_queue_lane_waiting_for_not_before, "queue-entry-1", next_not_before}},
        {:error, :command_queue_lane_empty}
      ])

    lane_dispatcher =
      start_lane_dispatcher!(
        dispatch_fun: dispatch_fun,
        reference_time_fun: fn -> now end
      )

    assert {:ok,
            %{
              released_count: 0,
              status: :waiting_for_not_before,
              next_not_before: ^next_not_before
            }} = LaneDispatcher.drain(lane_dispatcher)

    assert Process.alive?(lane_dispatcher)
    monitor = Process.monitor(lane_dispatcher)

    assert {:ok, %{released_count: 0, status: :empty, next_not_before: nil}} =
             LaneDispatcher.drain(lane_dispatcher)

    assert_receive {:DOWN, ^monitor, :process, ^lane_dispatcher, :normal}
  end

  test "drain reports partial progress with the underlying dispatch failure" do
    dispatch_fun =
      dispatch_sequence([
        {:ok, %{command_request_id: "command-1"}},
        {:error, :release_store_unavailable}
      ])

    lane_dispatcher = start_lane_dispatcher!(dispatch_fun: dispatch_fun)

    assert {:error, %{released_count: 1, reason: :release_store_unavailable}} =
             LaneDispatcher.drain(lane_dispatcher)

    assert Process.alive?(lane_dispatcher)
  end

  test "a recovering uplink session is a short wait, logged once at info, not a failure" do
    recovering = {:error, {:uplink_session_blocked, :protocol_recovery_required}}
    test_pid = self()

    dispatch_fun =
      dispatch_sequence([
        recovering,
        recovering,
        {:ok, %{command_request_id: "command-1"}},
        {:error, :command_queue_lane_empty}
      ])

    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)

    log =
      ExUnit.CaptureLog.capture_log([level: :info], fn ->
        lane_dispatcher =
          start_lane_dispatcher!(
            dispatch_fun: fn org, mission, lane, released_by, opts ->
              send(test_pid, :dispatch_attempt)
              dispatch_fun.(org, mission, lane, released_by, opts)
            end
          )

        monitor = Process.monitor(lane_dispatcher)

        assert {:ok, %{status: :waiting_for_release_target}} =
                 LaneDispatcher.drain(lane_dispatcher)

        # Retried at the 500 ms cadence (not the 60 s safety poll), then released.
        for _ <- 1..4, do: assert_receive(:dispatch_attempt, 2_000)
        assert_receive {:DOWN, ^monitor, :process, ^lane_dispatcher, :normal}, 2_000
      end)

    assert length(Regex.scan(~r/uplink session recovering its protocol state/, log)) == 1
  end

  test "an uplink session that never recovers falls back to the safety poll and warns once" do
    test_pid = self()

    lane_dispatcher =
      start_lane_dispatcher!(
        session_recovery_wait_ms: 700,
        dispatch_fun: fn _org, _mission, _lane, _released_by, _opts ->
          send(test_pid, :dispatch_attempt)
          {:error, {:uplink_session_blocked, :protocol_recovery_required}}
        end
      )

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, %{status: :waiting_for_release_target}} =
                 LaneDispatcher.drain(lane_dispatcher)

        # 0, 500 and 1,000 ms; past the 700 ms bound it waits for the 60 s safety poll.
        for _ <- 1..3, do: assert_receive(:dispatch_attempt, 2_000)
        refute_receive :dispatch_attempt, 1_000
      end)

    assert length(Regex.scan(~r/uplink session still recovering after/, log)) == 1
  end

  defp start_lane_dispatcher!(opts) do
    suffix = System.unique_integer([:positive]) |> Integer.to_string()

    child_spec =
      Supervisor.child_spec(
        {LaneDispatcher,
         Keyword.merge(opts,
           organization_id: "org-lane-drain-#{suffix}",
           mission_id: "mission-lane-drain-#{suffix}",
           queue_lane_key: "lane-drain-#{suffix}",
           name: nil,
           run_on_boot?: false
         )},
        restart: :temporary
      )

    start_supervised!(child_spec)
  end

  defp dispatch_sequence(results) do
    sequence = start_supervised!({Agent, fn -> results end})

    fn _organization_id, _mission_id, _queue_lane_key, _released_by, _opts ->
      Agent.get_and_update(sequence, fn
        [result | remaining] -> {result, remaining}
        [] -> raise "lane dispatcher attempted work after reaching quiescence"
      end)
    end
  end
end
