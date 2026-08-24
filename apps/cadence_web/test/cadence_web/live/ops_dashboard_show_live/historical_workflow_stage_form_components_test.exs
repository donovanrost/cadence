defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStageFormComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStageFormComponents

  test "stage_transition_form renders submit contract, hidden context, and stage actions" do
    html =
      render_component(&HistoricalWorkflowStageFormComponents.stage_transition_form/1,
        form: workflow_form(),
        workflow_context: workflow_context(),
        workflow_controls: %{
          stage_actions: [
            %{
              stage: "approved",
              id: "approve",
              label: "Approve",
              icon: "hero-check-circle",
              class: "btn-success btn-outline",
              disabled?: false,
              eligible?: true,
              reason: nil,
              preview: "Approve workflow run."
            },
            %{
              stage: "completed",
              id: "complete",
              label: "Complete",
              icon: "hero-flag",
              class: "btn-primary btn-outline",
              disabled?: true,
              eligible?: false,
              reason: "not_started",
              preview: "Complete after start."
            }
          ]
        }
      )

    vue =
      LiveVue.Test.get_vue(html,
        id: "historical-workflow-stage-form-component"
      )

    assert vue.component == "HistoricalWorkflowStageForm"
    assert vue.id == "historical-workflow-stage-form-component"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = Map.fetch!(vue.props, "presentation")
    assert presentation == expected_presentation()

    # One-to-one preservation of every original server-rendered assertion.
    assert presentation["root"]["attrs"]["phx-submit"] ==
             "record_historical_workflow_stage"

    assert hidden_value(presentation, "dashboard-historical-workflow-event-id") == "event-1"

    assert hidden_value(
             presentation,
             "dashboard-historical-workflow-correction-source-event-id"
           ) == "correction-event-1"

    assert hidden_value(presentation, "dashboard-historical-workflow-dashboard-id") ==
             "dashboard-1"

    assert hidden_value(presentation, "dashboard-historical-workflow-request-group-id") ==
             "request-group-1"

    assert presentation["confirmation"]["input_attrs"]["value"] == "confirmed"

    approved = action(presentation, "dashboard-historical-workflow-approved")
    assert approved["attrs"]["value"] == "approved"
    assert approved["attrs"]["data-workflow-action-eligible"] == "true"

    completed = action(presentation, "dashboard-historical-workflow-completed")
    assert completed["attrs"]["value"] == "completed"
    assert completed["attrs"]["disabled"] == ""
    assert completed["attrs"]["data-workflow-action-reason"] == "not_started"
  end

  defp expected_presentation do
    %{
      "root" => %{
        "attrs" => %{
          "id" => "dashboard-historical-workflow-form",
          "phx-submit" => "record_historical_workflow_stage",
          "class" => "space-y-3"
        }
      },
      "hidden_fields" => expected_hidden_fields(),
      "reason" =>
        expected_compact_input(
          "reason",
          "Reason",
          "operator transition",
          placeholder: "operator transition"
        ),
      "source_fields" => %{
        "attrs" => %{"class" => "grid grid-cols-1 gap-2"},
        "fields" => [
          expected_compact_input(
            "source_from",
            "Source From",
            "2026-06-22T10:00:00Z"
          ),
          expected_compact_input(
            "source_to",
            "Source To",
            "2026-06-22T11:00:00Z"
          )
        ]
      },
      "confirmation" => %{
        "attrs" => %{
          "id" => "dashboard-historical-workflow-confirm-row",
          "class" =>
            "flex items-start gap-2 rounded border border-base-300/70 bg-base-100/60 p-2 text-xs"
        },
        "input_attrs" => %{
          "id" => "dashboard-historical-workflow-confirm",
          "type" => "checkbox",
          "name" => "historical_workflow[confirmed]",
          "value" => "confirmed",
          "required" => "",
          "class" => "checkbox checkbox-xs mt-0.5"
        },
        "label" => %{
          "attrs" => %{"class" => "text-base-content/80"},
          "text" => "Confirm workflow transition"
        }
      },
      "actions" => %{
        "attrs" => %{"class" => "grid grid-cols-2 gap-2"},
        "items" => [
          %{
            "attrs" => %{
              "id" => "dashboard-historical-workflow-approved",
              "type" => "submit",
              "name" => "historical_workflow[stage]",
              "value" => "approved",
              "class" => "btn btn-xs justify-start btn-success btn-outline",
              "data-historical-workflow-action" => "approved",
              "data-workflow-action-id" => "approve",
              "data-workflow-action-eligible" => "true",
              "data-workflow-action-preview" => "Approve workflow run."
            },
            "icon" => %{
              "attrs" => %{"class" => "hero-check-circle h-3.5 w-3.5"}
            },
            "label" => "Approve"
          },
          %{
            "attrs" => %{
              "id" => "dashboard-historical-workflow-completed",
              "type" => "submit",
              "name" => "historical_workflow[stage]",
              "value" => "completed",
              "disabled" => "",
              "class" => "btn btn-xs justify-start btn-disabled",
              "data-historical-workflow-action" => "completed",
              "data-workflow-action-id" => "complete",
              "data-workflow-action-eligible" => "false",
              "data-workflow-action-reason" => "not_started",
              "data-workflow-action-preview" => "Complete after start."
            },
            "icon" => %{"attrs" => %{"class" => "hero-flag h-3.5 w-3.5"}},
            "label" => "Complete"
          }
        ]
      }
    }
  end

  defp expected_hidden_fields do
    [
      {"dashboard-historical-workflow-event-id", "event_id", "event-1"},
      {"dashboard-historical-workflow-correction-source-event-id",
       "correction_source_event_id", "correction-event-1"},
      {"dashboard-historical-workflow-value", "workflow", "backfill"},
      {"dashboard-historical-workflow-run-id", "run_id", "run-1"},
      {"dashboard-historical-workflow-realm", "realm", "flight"},
      {"dashboard-historical-workflow-data-source-id", "data_source_id",
       "questdb-flight"},
      {"dashboard-historical-workflow-source-binding-id", "source_binding_id",
       "binding-flight"},
      {"dashboard-historical-workflow-observable-id", "observable_id", "HK.counter"},
      {"dashboard-historical-workflow-point-id", "point_id", "HK.counter"},
      {"dashboard-historical-workflow-dashboard-id", "dashboard_id", "dashboard-1"},
      {"dashboard-historical-workflow-dashboard-version", "dashboard_version", "7"},
      {"dashboard-historical-workflow-dashboard-time-mode", "dashboard_time_mode",
       "replay_run"},
      {"dashboard-historical-workflow-dashboard-replay-run-id", "dashboard_replay_run_id",
       "replay-1"},
      {"dashboard-historical-workflow-dashboard-data-view", "dashboard_data_view",
       "all_revisions"},
      {"dashboard-historical-workflow-dashboard-limit-mode", "dashboard_limit_mode",
       "observed"},
      {"dashboard-historical-workflow-request-group-id", "request_group_id",
       "request-group-1"},
      {"dashboard-historical-workflow-request-mode", "request_mode", "operator"},
      {"dashboard-historical-workflow-comparison-review-request-event-id",
       "comparison_review_request_event_id", ""},
      {"dashboard-historical-workflow-comparison-review-request-kind",
       "comparison_review_request_kind", ""},
      {"dashboard-historical-workflow-comparison-review-open-count",
       "comparison_review_open_count", ""},
      {"dashboard-historical-workflow-comparison-review-open-placement-ids",
       "comparison_review_open_placement_ids", ""},
      {"dashboard-historical-workflow-comparison-review-workflow-kind",
       "comparison_review_workflow_kind", ""},
      {"dashboard-historical-workflow-comparison-review-workflow-action",
       "comparison_review_workflow_action", ""},
      {"dashboard-historical-workflow-comparison-review-workflow-selection-kind",
       "comparison_review_workflow_selection_kind", ""},
      {"dashboard-historical-workflow-comparison-review-workflow-selection-count",
       "comparison_review_workflow_selection_count", ""},
      {"dashboard-historical-workflow-comparison-review-primary-data-view",
       "comparison_review_primary_data_view", ""},
      {"dashboard-historical-workflow-comparison-review-compare-data-view",
       "comparison_review_compare_data_view", ""},
      {"dashboard-historical-workflow-comparison-review-scope-kind",
       "comparison_review_scope_kind", ""},
      {"dashboard-historical-workflow-comparison-review-scope-ids",
       "comparison_review_scope_ids", ""},
      {"dashboard-historical-workflow-comparison-review-contact-ids",
       "comparison_review_contact_ids", ""},
      {"dashboard-historical-workflow-comparison-review-resource-ids",
       "comparison_review_resource_ids", ""},
      {"dashboard-historical-workflow-comparison-review-transport-ids",
       "comparison_review_transport_ids", ""},
      {"dashboard-historical-workflow-comparison-review-source-endpoint-ids",
       "comparison_review_source_endpoint_ids", ""},
      {"dashboard-historical-workflow-comparison-review-ground-station-ids",
       "comparison_review_ground_station_ids", ""},
      {"dashboard-historical-workflow-comparison-review-scope-link-ids",
       "comparison_review_scope_link_ids", ""}
    ]
    |> Enum.map(fn {id, field, value} ->
      %{
        "attrs" => %{
          "id" => id,
          "type" => "hidden",
          "name" => "historical_workflow[#{field}]",
          "value" => value
        }
      }
    end)
  end

  defp expected_compact_input(field, label, value, options \\ []) do
    input_attrs = %{
      "id" => "historical_workflow_#{field}",
      "name" => "historical_workflow[#{field}]",
      "type" => "text",
      "value" => value,
      "class" => "w-full input"
    }

    input_attrs =
      case Keyword.fetch(options, :placeholder) do
        {:ok, placeholder} -> Map.put(input_attrs, "placeholder", placeholder)
        :error -> input_attrs
      end

    %{
      "wrapper_attrs" => %{"class" => "fieldset"},
      "label" => %{
        "attrs" => %{"class" => "hud-label block mb-1.5"},
        "text" => label
      },
      "input_attrs" => input_attrs,
      "errors" => []
    }
  end

  defp hidden_value(presentation, id) do
    presentation["hidden_fields"]
    |> Enum.find(&(&1["attrs"]["id"] == id))
    |> get_in(["attrs", "value"])
  end

  defp action(presentation, id) do
    Enum.find(presentation["actions"]["items"], &(&1["attrs"]["id"] == id))
  end

  defp workflow_form do
    %{
      "event_id" => "event-1",
      "correction_source_event_id" => "correction-event-1",
      "workflow" => "backfill",
      "run_id" => "run-1",
      "realm" => "flight",
      "data_source_id" => "questdb-flight",
      "source_binding_id" => "binding-flight",
      "observable_id" => "HK.counter",
      "point_id" => "HK.counter",
      "dashboard_id" => "dashboard-1",
      "dashboard_version" => "7",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-1",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed",
      "request_group_id" => "request-group-1",
      "request_mode" => "operator",
      "reason" => "operator transition",
      "source_from" => "2026-06-22T10:00:00Z",
      "source_to" => "2026-06-22T11:00:00Z",
      "confirmed" => ""
    }
    |> to_form(as: :historical_workflow)
  end

  defp workflow_context do
    %{
      event_id: "event-1",
      correction_source_event_id: "correction-event-1",
      workflow: "backfill",
      run_id: "run-1",
      realm: "flight",
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight",
      observable_id: "HK.counter",
      point_id: "HK.counter",
      dashboard_id: "dashboard-1",
      dashboard_version: "7",
      dashboard_time_mode: "replay_run",
      dashboard_replay_run_id: "replay-1",
      dashboard_data_view: "all_revisions",
      dashboard_limit_mode: "observed",
      request_group_id: "request-group-1",
      request_mode: "operator",
      reason: "operator transition"
    }
  end
end
