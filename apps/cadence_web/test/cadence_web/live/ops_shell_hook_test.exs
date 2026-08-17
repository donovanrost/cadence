defmodule CadenceWeb.OpsShellHookTest do
  use ExUnit.Case, async: false

  @moduletag :config

  alias CadenceWeb.OpsShellHook
  alias Phoenix.LiveView.Socket

  test "refresh_context updates the shell snapshot through canonical mission health" do
    observed_at = ~U[2026-08-01 12:00:00Z]

    socket =
      OpsShellHook.refresh_context(socket(),
        observed_at: fn -> observed_at end,
        mission_health_summary: fn organization_id, mission_id, [] ->
          assert organization_id == "org-1"
          assert mission_id == "mission-1"

          %{
            normalized_state_counts: %{red: 0, yellow: 1, blue: 0, green: 5},
            violating_points: 1
          }
        end,
        alarm_summary: fn _organization_id, mission_id, [] -> alarm_summary(mission_id) end,
        command_summary: fn _organization_id, mission_id, [] -> command_summary(mission_id) end
      )

    assert socket.assigns.ops_context.observed_at == observed_at
    assert socket.assigns.fleet_health.violating_points == 1

    assert Enum.map(socket.assigns.ops_context.modules, & &1.key) == [
             "alarms",
             "commands",
             "fleet_health"
           ]

    assert fleet_health =
             Enum.find(socket.assigns.ops_context.modules, &(&1.key == "fleet_health"))

    assert fleet_health.status == :warning
    assert fleet_health.freshness == :current
  end

  test "context refresh interval rejects invalid configuration" do
    previous = Application.get_env(:cadence_web, :ops_context_refresh_ms)

    try do
      Application.put_env(:cadence_web, :ops_context_refresh_ms, 2_500)
      assert OpsShellHook.context_refresh_ms() == 2_500

      Application.put_env(:cadence_web, :ops_context_refresh_ms, 0)
      assert OpsShellHook.context_refresh_ms() == 15_000
    after
      if is_nil(previous) do
        Application.delete_env(:cadence_web, :ops_context_refresh_ms)
      else
        Application.put_env(:cadence_web, :ops_context_refresh_ms, previous)
      end
    end
  end

  defp socket do
    %Socket{
      assigns: %{
        __changed__: %{},
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"}
      }
    }
  end

  defp alarm_summary(mission_id) do
    %{
      mission_id: mission_id,
      observed_at: ~U[2026-08-01 12:00:00Z],
      latest_transition_at: nil,
      freshness: :current,
      active_count: 0,
      critical_count: 0,
      warning_count: 0,
      info_count: 0,
      highest_severity: nil,
      status: :nominal
    }
  end

  defp command_summary(mission_id) do
    %{
      mission_id: mission_id,
      observed_at: ~U[2026-08-01 12:00:00Z],
      latest_transition_at: nil,
      freshness: :current,
      status: :nominal,
      total_count: 0,
      queued_count: 0,
      release_pending_count: 0,
      in_flight_count: 0,
      released_count: 0,
      failed_count: 0,
      indeterminate_count: 0,
      active_count: 0,
      rows: []
    }
  end
end
