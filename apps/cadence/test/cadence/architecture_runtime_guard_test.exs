defmodule Cadence.ArchitectureRuntimeGuardTest do
  use Cadence.UnitCase, async: true

  @moduledoc false

  @runtime_owners [
    %{
      name: "contact scheduler",
      path: "lib/cadence/contacts/scheduler.ex",
      required_markers: [
        "@default_safety_poll_interval_ms",
        "await_settled",
        "notify_contact_changed",
        ":notification",
        "rebuild_projection",
        "{:mission_wakeup, mission_id, token}",
        ":safety_reconcile"
      ]
    },
    %{
      name: "command dispatcher",
      path: "lib/cadence/commanding/dispatcher.ex",
      required_markers: [
        "@default_safety_poll_interval_ms",
        "kick_lane",
        "LaneDispatcher.drain",
        "list_pending_queue_lanes",
        ":reconcile"
      ]
    },
    %{
      name: "command lane dispatcher",
      path: "lib/cadence/commanding/lane_dispatcher.ex",
      required_markers: [
        "@default_safety_poll_interval_ms",
        "drain",
        "dispatch_now",
        ":notification",
        "command_queue_lane_waiting_for_not_before",
        "{:dispatch, token}",
        ":timer_scheduled"
      ]
    },
    %{
      name: "command verifier scheduler",
      path: "lib/cadence/commanding/verifier_scheduler.ex",
      required_markers: [
        "@default_safety_poll_interval_ms",
        "notify_verifier_instances_changed",
        ":notification",
        "rebuild_projection",
        "{:timeout_wakeup, token}",
        ":safety_reconcile"
      ]
    },
    %{
      name: "mission runtime reconciler",
      path: "lib/cadence/control/mission_runtime_reconciler.ex",
      required_markers: [
        "@default_safety_poll_interval_ms",
        "await_settled",
        "handle_continue(:reconcile",
        ":safety_reconcile"
      ]
    },
    %{
      name: "jobs dispatcher",
      path: "lib/cadence/jobs/dispatcher.ex",
      required_markers: [
        "@default_safety_poll_interval_ms",
        "notify_available",
        ":dispatch_available",
        "{:DOWN, ref, :process",
        "{:safety_dispatch, token}",
        ":safety_dispatch_scheduled"
      ]
    }
  ]

  @config_guarded_keys [
    :background_jobs,
    :contact_scheduler,
    :command_dispatcher,
    :command_verifier_scheduler
  ]

  test "db-backed runtime owners use safety intervals instead of tight poll defaults" do
    for owner <- @runtime_owners do
      source = read_app_file!(owner.path)

      assert source =~ "safety_poll_interval_ms",
             "#{owner.name} should expose a safety interval, not a primary poll interval"

      refute source =~ "@default_poll_interval_ms",
             "#{owner.name} must not reintroduce a default polling loop"

      refute source =~ ~r/Keyword\.get\(\s*opts,\s*:poll_interval_ms,\s*\d/ms,
             "#{owner.name} must not default :poll_interval_ms directly to a tight numeric interval"

      refute source =~ ":poll_interval_ms",
             "#{owner.name} must not read compatibility :poll_interval_ms options"

      refute source =~ ":lane_poll_interval_ms",
             "#{owner.name} must not read compatibility :lane_poll_interval_ms options"
    end
  end

  test "db-backed runtime owners keep explicit signal, timer, and recovery markers" do
    for owner <- @runtime_owners do
      source = read_app_file!(owner.path)

      for marker <- owner.required_markers do
        assert source =~ marker,
               "#{owner.name} is missing expected runtime ownership marker #{inspect(marker)}"
      end
    end
  end

  test "application defaults configure slow safety scans, not primary polling loops" do
    config = read_repo_file!("config/config.exs")

    for config_key <- @config_guarded_keys do
      assert config =~ "#{config_key}:",
             "expected #{inspect(config_key)} to remain visible in application config"
    end

    assert config =~ "safety_poll_interval_ms: 60_000"
    refute config =~ ~r/(^|[^A-Za-z0-9_])poll_interval_ms:/m
  end

  defp read_app_file!(relative_path) do
    __DIR__
    |> Path.join("../../#{relative_path}")
    |> Path.expand()
    |> File.read!()
  end

  defp read_repo_file!(relative_path) do
    __DIR__
    |> Path.join("../../../../#{relative_path}")
    |> Path.expand()
    |> File.read!()
  end
end
