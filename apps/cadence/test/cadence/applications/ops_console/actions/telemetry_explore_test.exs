defmodule Cadence.Applications.OpsConsole.Actions.TelemetryExploreTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.TelemetryExplore
  alias Cadence.Auth.Scope

  @organization_id "org-ops-telemetry-actions"
  @mission_id "mission-ops-telemetry-actions"

  setup do
    %{organization: organization} = persist_mission_scope(@organization_id, @mission_id)

    user =
      User.new(%{
        user_id: "ops-telemetry-actions-user",
        email: "ops-telemetry-actions@example.test",
        display_name: "Ops Telemetry Actions"
      })

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: organization.organization_id,
        role: :member
      })

    %{
      scope:
        Scope.new(%{
          user: user,
          organization_id: organization.organization_id,
          organization: organization,
          organization_membership: membership
        })
    }
  end

  test "declares the exact navigation and authoring bindings" do
    assert TelemetryExplore.bindings() == [
             {"telemetry_explore", "apply_filters"},
             {"telemetry_explore", "apply_question"},
             {"telemetry_explore", "add_to_dashboard"}
           ]
  end

  test "applies typed filters and questions through the mission route", %{scope: scope} do
    assert {:ok, %{"navigation" => filter_path}} =
             execute(scope, "apply_filters", filter_params())

    assert filter_path =~ "/missions/#{@mission_id}/ops/explore?"
    assert filter_path =~ "point_id=point-1"

    assert {:ok, %{"navigation" => question_path}} =
             execute(scope, "apply_question", %{
               "question" => "recent_anomalies",
               "source_dashboard_id" => ""
             })

    assert question_path =~ "/missions/#{@mission_id}/ops/explore?"
    assert question_path =~ "question=recent_anomalies"
  end

  test "rejects malformed filter and dashboard authoring inputs", %{scope: scope} do
    assert {:error, :malformed_action_input} =
             execute(scope, "apply_filters", Map.delete(filter_params(), "limit"))

    assert {:error, :invalid_widget_type} =
             execute(
               scope,
               "add_to_dashboard",
               %{
                 "dashboard_id" => "dashboard-1",
                 "widget_type" => "unsupported",
                 "title" => "Telemetry",
                 "point_id" => "point-1"
               }
               |> Map.merge(filter_params())
             )
  end

  defp execute(scope, action_id, params) do
    TelemetryExplore.execute(
      scope,
      HostContext.mission(@mission_id),
      "telemetry_explore",
      %ActionRequest{
        application_key: "ops_console",
        application_version: 1,
        action_id: action_id,
        surface_id: "telemetry_explore",
        surface_version: 1,
        params: params
      }
    )
  end

  defp filter_params do
    %{
      "point_id" => "point-1",
      "spacecraft_id" => "spacecraft-1",
      "scope_kind" => "",
      "scope_id" => "",
      "time_mode" => "latest",
      "time_axis" => "receipt",
      "from" => "",
      "to" => "",
      "replay_run_id" => "",
      "order" => "desc",
      "limit" => "100",
      "selection_view" => "canonical",
      "validity_state" => "valid",
      "realm" => "engineering",
      "logical_source" => "telemetry",
      "data_source_id" => "",
      "source_binding_id" => "",
      "source_dashboard_id" => "",
      "sample_id" => "",
      "selected_time" => "",
      "question" => "",
      "limit_mode" => "default"
    }
  end
end
