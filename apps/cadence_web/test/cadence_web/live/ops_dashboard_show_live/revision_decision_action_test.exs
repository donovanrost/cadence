defmodule CadenceWeb.OpsDashboardShowLive.RevisionDecisionActionTest do
  use ExUnit.Case, async: true

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
