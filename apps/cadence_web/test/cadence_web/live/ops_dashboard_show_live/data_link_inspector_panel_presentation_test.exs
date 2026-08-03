defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentationTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DashboardAction, Document}
  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionOutcome

  test "build prepares panel attrs, actions, and action outcome presentation" do
    presentation =
      DataLinkInspectorPanelPresentation.build(
        %{
          status_text: "resolved",
          target: :telemetry_point,
          target_id: "HK.counter",
          link_id: "telemetry_point:HK.counter:request-1",
          target_text: "telemetry point",
          source: :frame,
          rows: [],
          context_rows: [
            %{label: "Data realm", value: "flight"},
            %{label: "Data view", value: "all_revisions"},
            %{label: "Data source", value: "questdb-flight"},
            %{label: "Source binding", value: "binding-flight"},
            %{label: "Time mode", value: "replay_run"},
            %{label: "Time axis", value: "generation_time"},
            %{label: "Replay run", value: "replay-run-1"}
          ],
          related_links: [],
          actions: [telemetry_explore_action()]
        },
        "mission-1",
        %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        HistoricalWorkflowActionOutcome.new(
          action: :retry_job,
          status: :ok,
          kind: :info,
          reason: :retry_job_queued,
          job_id: "job-1",
          message: "Historical workflow job retry queued."
        )
      )

    assert presentation.panel_attrs == %{
             target: "telemetry_point",
             target_id: "HK.counter",
             status: "resolved",
             selected_link: "telemetry_point:HK.counter:request-1",
             selected_realm: "flight",
             selected_data_view: "all_revisions",
             selected_data_source_id: "questdb-flight",
             selected_source_binding_id: "binding-flight",
             selected_time_mode: "replay_run",
             selected_time_axis: "generation_time",
             selected_replay_run_id: "replay-run-1"
           }

    assert [action] = presentation.data_link_actions
    assert action.action_id == "dashboard-data-link-explore"
    assert action.kind == :navigate
    assert action.source == :data_link_panel
    assert action.route =~ "/missions/mission-1/ops/explore"
    assert action.route =~ "source_dashboard_id=dashboard-1"

    assert presentation.action_outcome.action == "retry_job"
    assert presentation.action_outcome.status == "ok"
    assert presentation.action_outcome.metadata["job_id"] == "job-1"
  end

  test "panel_attrs tolerates non-map inputs" do
    assert DataLinkInspectorPanelPresentation.panel_attrs(nil, nil) == %{
             target: "",
             target_id: "",
             status: "",
             selected_link: "",
             selected_realm: "",
             selected_data_view: "",
             selected_data_source_id: "",
             selected_source_binding_id: "",
             selected_time_mode: "",
             selected_time_axis: "",
             selected_replay_run_id: ""
           }
  end

  test "normalizes template attribute helper values" do
    assert DataLinkInspectorPanelPresentation.relationship_kind_text(:retry_event) ==
             "retry_event"

    assert DataLinkInspectorPanelPresentation.relationship_kind_text("source_event") ==
             "source_event"

    refute DataLinkInspectorPanelPresentation.relationship_kind_text(%{})

    assert DataLinkInspectorPanelPresentation.bool_attr(true) == "true"
    assert DataLinkInspectorPanelPresentation.bool_attr(false) == "false"

    assert DataLinkInspectorPanelPresentation.present_text?("job-1")
    refute DataLinkInspectorPanelPresentation.present_text?("")
    refute DataLinkInspectorPanelPresentation.present_text?(nil)
  end

  defp telemetry_explore_action do
    %DashboardAction{
      action_id: "explore",
      label: "Explore telemetry",
      target: :telemetry_explore,
      kind: :invoke,
      query: %{
        "point_id" => "HK.counter",
        "sample_id" => "sample-1"
      },
      source: :frame
    }
  end
end
