defmodule CadenceWeb.OpsDashboardShowLive.RevisionDecisionActionTest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.OpsDashboardShowLive.RevisionDecision
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionActionOutcome
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionParams
  alias Phoenix.LiveView.Socket

  test "applying a revision decision requires explicit confirmation" do
    socket =
      RevisionDecision.apply_decision(
        socket(),
        %{"decision" => "mark_conflict"},
        apply_decision: fn _params, _scope, _mission -> flunk("command should not run") end
      )

    assert socket.assigns.flash["error"] ==
             "Confirm the telemetry revision decision before applying it."

    assert %RevisionDecisionActionOutcome{
             status: :blocked,
             reason: "confirmation_required",
             decision: "mark_conflict"
           } = socket.assigns.data_link_action_outcome
  end

  test "successful revision decisions scope preserved outcomes to the result data context" do
    socket =
      RevisionDecision.apply_decision(
        socket(),
        %{
          "revision_decision" => %{
            "observation_identity_id" => "identity-1",
            "decision" => "mark_conflict",
            "dashboard_time_mode" => "replay_run",
            "dashboard_replay_run_id" => "replay-1",
            "dashboard_data_view" => "all_revisions",
            "dashboard_limit_mode" => "compare",
            "confirmed" => "confirmed"
          }
        },
        apply_decision: fn _params, _scope, _mission ->
          {:ok, %{observation_identity_id: "identity-1"},
           %{
             decision_event_id: "decision-event-result",
             observation_identity_id: "identity-1",
             realm: :flight,
             data_source_id: "questdb-flight",
             binding_id: "flight-binding"
           }}
        end,
        patch: fn socket, query -> Phoenix.Component.assign(socket, :patched_query, query) end
      )

    assert %RevisionDecisionActionOutcome{
             status: :ok,
             reason: "revision_decision_applied",
             decision: "mark_conflict",
             dashboard_time_mode: "replay_run",
             dashboard_replay_run_id: "replay-1",
             dashboard_data_view: "all_revisions",
             dashboard_limit_mode: "compare",
             result_event_id: "decision-event-result",
             target_event_id: "decision-event-result",
             target_observation_identity_id: "identity-1"
           } = socket.assigns.data_link_action_outcome

    assert socket.assigns.data_link_action_outcome_query == %{
             "selected_target" => "telemetry_revision_decision_event",
             "selected_id" => "decision-event-result",
             "realm" => "flight",
             "data_source_id" => "questdb-flight",
             "source_binding_id" => "flight-binding",
             "time_mode" => "replay_run",
             "replay_run_id" => "replay-1",
             "selected_data_view" => "all_revisions",
             "limit_mode" => "compare"
           }

    assert Map.take(socket.assigns.patched_query, [
             "panel",
             "selected_target",
             "selected_id",
             "realm",
             "data_source_id",
             "source_binding_id",
             "time_mode",
             "replay_run_id",
             "selected_data_view",
             "limit_mode"
           ]) == %{
             "panel" => "data_link",
             "selected_target" => "telemetry_revision_decision_event",
             "selected_id" => "decision-event-result",
             "realm" => "flight",
             "data_source_id" => "questdb-flight",
             "source_binding_id" => "flight-binding",
             "time_mode" => "replay_run",
             "replay_run_id" => "replay-1",
             "selected_data_view" => "all_revisions",
             "limit_mode" => "compare"
           }
  end

  test "applying a revision decision records typed failure outcome" do
    socket =
      RevisionDecision.apply_decision(
        socket(),
        %{
          "revision_decision" => %{
            "observation_identity_id" => "identity-1",
            "decision" => "mark_conflict",
            "confirmed" => "confirmed"
          }
        },
        apply_decision: fn params, _scope, _mission ->
          assert %RevisionDecisionParams{
                   observation_identity_id: "identity-1",
                   decision: "mark_conflict"
                 } = params

          {:error, :not_found}
        end
      )

    assert socket.assigns.flash["error"] ==
             "Failed to apply telemetry revision decision: :not_found"

    assert %RevisionDecisionActionOutcome{
             status: :error,
             reason: "revision_decision_failed",
             decision: "mark_conflict",
             target_observation_identity_id: "identity-1",
             error: :not_found
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
