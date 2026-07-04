defmodule CadenceWeb.OpsDashboardShowLive.LateDataPolicyTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicy
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyActionOutcome
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyParams
  alias Phoenix.LiveView.Socket

  test "record_decision requires explicit confirmation before invoking commands" do
    socket =
      LateDataPolicy.record_decision(
        socket(),
        %{
          "late_data_policy" => %{
            "decision" => "accept",
            "execution_mode" => "event_only",
            "dashboard_limit_mode" => "current"
          }
        },
        record_decision: fn _params, _scope, _mission -> flunk("command should not run") end
      )

    assert socket.assigns.flash["error"] ==
             "Confirm the late-data policy decision before applying it."

    assert %LateDataPolicyActionOutcome{
             action: :late_data_policy,
             status: :blocked,
             kind: :error,
             reason: "confirmation_required",
             decision: "accept",
             execution_mode: "event_only",
             dashboard_limit_mode: "current",
             message: "Confirm the late-data policy decision before applying it."
           } = socket.assigns.data_link_action_outcome
  end

  test "record_decision passes typed params to commands and records structured errors" do
    test_pid = self()

    socket =
      LateDataPolicy.record_decision(
        socket(),
        %{
          "late_data_policy" => %{
            "decision" => "accept",
            "execution_mode" => "sample_execution",
            "dashboard_limit_mode" => "compare",
            "confirmed" => "confirmed"
          }
        },
        record_decision: fn params, scope, mission ->
          send(test_pid, {:record_decision, params, scope.organization_id, mission.mission_id})
          {:error, {:missing_field, :point_id}}
        end
      )

    assert_received {:record_decision,
                     %LateDataPolicyParams{
                       decision: "accept",
                       execution_mode: "sample_execution",
                       dashboard_limit_mode: "compare",
                       confirmed: "confirmed"
                     }, "org-1", "mission-1"}

    assert socket.assigns.flash["error"] ==
             "Failed to apply late-data policy: {:missing_field, :point_id}"

    assert %LateDataPolicyActionOutcome{
             action: :late_data_policy,
             status: :error,
             kind: :error,
             reason: "late_data_policy_failed",
             dashboard_limit_mode: "compare",
             error: {:missing_field, :point_id},
             message: "Failed to apply late-data policy: {:missing_field, :point_id}"
           } = socket.assigns.data_link_action_outcome
  end

  defp socket do
    %Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        current_scope: %{organization_id: "org-1", user: %{id: "operator-1"}},
        current_mission: %{mission_id: "mission-1"}
      }
    }
  end
end
