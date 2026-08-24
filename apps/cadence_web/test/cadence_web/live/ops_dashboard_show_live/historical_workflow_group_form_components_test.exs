defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupFormComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupFormComponents

  @hidden_field_keys ~w(
    workflow request_group_id realm data_source_id source_binding_id dashboard_id
    dashboard_version dashboard_time_mode dashboard_replay_run_id dashboard_data_view
    dashboard_limit_mode comparison_review_request_event_id comparison_review_request_kind
    comparison_review_open_count comparison_review_open_placement_ids
    comparison_review_workflow_kind comparison_review_workflow_action
    comparison_review_workflow_selection_kind comparison_review_workflow_selection_count
    comparison_review_primary_data_view comparison_review_compare_data_view
    comparison_review_scope_kind comparison_review_scope_ids comparison_review_contact_ids
    comparison_review_resource_ids comparison_review_transport_ids
    comparison_review_source_endpoint_ids comparison_review_ground_station_ids
    comparison_review_scope_link_ids
  )

  test "group_transition_form renders submit contract, hidden context, and group actions" do
    html =
      render_component(&HistoricalWorkflowGroupFormComponents.group_transition_form/1,
        form: group_form(),
        workflow_context: workflow_context(),
        workflow_controls: %{group_actions: true, group_stage_actions: group_stage_actions()}
      )

    presentation = group_form_presentation(html)
    hidden_fields = Map.new(presentation["hidden_fields"], &{&1["key"], &1})

    eligible_actions =
      Map.new(presentation["eligible_items"]["actions"], &{&1["key"], &1})

    action_buttons = Map.new(presentation["actions"]["items"], &{&1["key"], &1})
    start_orchestration = presentation["start_orchestration"]

    assert presentation["root"]["attrs"]["phx-submit"] ==
             "record_historical_workflow_group_stage"

    assert hidden_fields["request_group_id"]["attrs"]["value"] == "request-group-1"
    assert hidden_fields["dashboard_id"]["attrs"]["value"] == "dashboard-1"
    assert hidden_fields["dashboard_limit_mode"]["attrs"]["value"] == "observed"
    assert presentation["confirmation"]["field"]["attrs"]["value"] == "confirmed"

    assert presentation["eligible_items"]["attrs"][
             "data-historical-workflow-group-eligible-request-group"
           ] == "request-group-1"

    assert eligible_actions["approved"]["attrs"][
             "data-historical-workflow-group-eligible-count"
           ] == "3"

    assert eligible_actions["approved"]["attrs"][
             "data-historical-workflow-group-eligible-state"
           ] == "true"

    assert eligible_actions["approved"]["attrs"]["data-workflow-action-correction-tasks"] ==
             "HK.current run-3 replacement run-3-corrected stage requested next approve"

    assert eligible_actions["completed"]["attrs"][
             "data-historical-workflow-group-eligible-count"
           ] == "0"

    assert eligible_actions["completed"]["attrs"][
             "data-historical-workflow-group-eligible-reason"
           ] == "not_started"

    assert start_orchestration["attrs"][
             "data-historical-workflow-group-start-next-action"
           ] == "start_eligible_items"

    assert start_orchestration["attrs"]["data-historical-workflow-group-start-eligible"] ==
             "3"

    assert start_orchestration["attrs"][
             "data-historical-workflow-group-start-expected-jobs"
           ] == "3"

    assert start_orchestration["attrs"][
             "data-historical-workflow-group-start-review-request"
           ] == "review-request-1"

    assert start_orchestration["attrs"][
             "data-historical-workflow-group-start-review-placements"
           ] == "placement-1,placement-2,placement-3"

    assert hidden_fields["comparison_review_scope_ids"]["attrs"]["value"] ==
             "transport-alpha,transport-beta"

    assert hidden_fields["comparison_review_contact_ids"]["attrs"]["value"] ==
             "contact-alpha,contact-beta"

    assert start_orchestration["attrs"][
             "data-historical-workflow-group-start-review-scope-ids"
           ] == "transport-alpha,transport-beta"

    assert start_orchestration["attrs"][
             "data-historical-workflow-group-start-review-contact-ids"
           ] == "contact-alpha,contact-beta"

    assert start_orchestration["attrs"]["data-historical-workflow-group-start-reason"] ==
             "eligible_group_items"

    assert String.contains?(
             start_orchestration["guidance"]["text"],
             "3 review findings are attached."
           )

    assert action_buttons["approved"]["attrs"]["value"] == "approved"

    assert action_buttons["approved"]["attrs"][
             "data-historical-workflow-group-action-eligible"
           ] == "3"

    assert action_buttons["approved"]["attrs"]["data-workflow-action-eligible"] == "true"

    assert action_buttons["approved"]["attrs"]["data-workflow-action-correction-tasks"] ==
             "HK.current run-3 replacement run-3-corrected stage requested next approve"

    assert action_buttons["completed"]["attrs"]["value"] == "completed"
    assert action_buttons["completed"]["attrs"]["disabled"] == ""

    assert action_buttons["completed"]["attrs"]["data-workflow-action-reason"] ==
             "not_started"

    assert presentation == %{
             "root" => %{
               "id" => "dashboard-historical-workflow-group-form",
               "class" => "space-y-3 rounded border border-primary/30 bg-primary/5 p-2",
               "attrs" => %{
                 "phx-submit" => "record_historical_workflow_group_stage"
               }
             },
             "hidden_fields" => expected_hidden_fields(workflow_context()),
             "header" => %{
               "class" => "flex items-center justify-between gap-2",
               "title" => %{"class" => "hud-label", "text" => "Group Actions"},
               "count" => %{
                 "class" => "badge badge-xs badge-primary",
                 "text" => "3 items"
               }
             },
             "eligible_items" => expected_eligible_items(),
             "start_orchestration" => expected_start_orchestration(),
             "reason" => %{
               "wrapper_class" => "fieldset",
               "label" => %{
                 "class" => "hud-label block mb-1.5",
                 "text" => "Reason"
               },
               "control" => %{
                 "class" => "w-full input",
                 "attrs" => %{
                   "id" => "historical_workflow_group_reason",
                   "name" => "historical_workflow_group[reason]",
                   "type" => "text",
                   "value" => "operator group transition",
                   "placeholder" => "operator group transition"
                 }
               },
               "errors" => []
             },
             "confirmation" => %{
               "id" => "dashboard-historical-workflow-group-confirm-row",
               "class" =>
                 "flex items-start gap-2 rounded border border-primary/30 bg-base-100/70 p-2 text-xs",
               "field" => %{
                 "class" => "checkbox checkbox-xs mt-0.5",
                 "attrs" => %{
                   "id" => "dashboard-historical-workflow-group-confirm",
                   "type" => "checkbox",
                   "name" => "historical_workflow_group[confirmed]",
                   "value" => "confirmed",
                   "required" => ""
                 }
               },
               "label" => %{
                 "class" => "text-base-content/80",
                 "text" => "Confirm workflow transition for eligible items in this request group"
               }
             },
             "actions" => %{
               "class" => "grid grid-cols-2 gap-2",
               "items" => expected_action_buttons()
             }
           }
  end

  test "group_transition_form does not render when group actions are unavailable" do
    html =
      render_component(&HistoricalWorkflowGroupFormComponents.group_transition_form/1,
        form: group_form(),
        workflow_context: workflow_context(),
        workflow_controls: %{group_actions: false, group_stage_actions: []}
      )

    document = LazyHTML.from_fragment(html)

    assert document
           |> LazyHTML.query("#historical-workflow-group-form-component")
           |> Enum.empty?()

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-group-form")
           |> Enum.empty?()
  end

  test "group_transition_form omits start orchestration when no start action is available" do
    html =
      render_component(&HistoricalWorkflowGroupFormComponents.group_transition_form/1,
        form: group_form(),
        workflow_context: workflow_context(),
        workflow_controls: %{
          group_actions: true,
          group_stage_actions: Enum.take(group_stage_actions(), 2)
        }
      )

    presentation = group_form_presentation(html)

    assert presentation["start_orchestration"] == nil
    assert Enum.map(presentation["actions"]["items"], & &1["key"]) == ~w(approved completed)
  end

  defp group_form_presentation(html) do
    document = LazyHTML.from_fragment(html)

    assert document
           |> LazyHTML.query("#historical-workflow-group-form-component")
           |> Enum.count() == 1

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-group-form")
           |> Enum.empty?()

    vue =
      LiveVue.Test.get_vue(html,
        id: "historical-workflow-group-form-component"
      )

    assert vue.component == "HistoricalWorkflowGroupForm"
    assert vue.id == "historical-workflow-group-form-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    Map.fetch!(vue.props, "presentation")
  end

  defp expected_hidden_fields(context) do
    Enum.map(@hidden_field_keys, fn key ->
      atom_key = String.to_existing_atom(key)
      value = Map.get(context, atom_key) || ""

      %{
        "key" => key,
        "attrs" => %{
          "id" => "dashboard-historical-workflow-group-#{String.replace(key, "_", "-")}",
          "type" => "hidden",
          "name" => "historical_workflow_group[#{key}]",
          "value" => value
        }
      }
    end)
  end

  defp expected_eligible_items do
    %{
      "id" => "dashboard-historical-workflow-group-eligible-items",
      "class" => "space-y-1 rounded border border-base-300/60 bg-base-100/70 p-2",
      "attrs" => %{
        "data-historical-workflow-group-eligible-request-group" => "request-group-1",
        "data-historical-workflow-group-eligible-size" => "3"
      },
      "header" => %{
        "class" => "flex items-center justify-between gap-2",
        "title" => %{"class" => "hud-label", "text" => "Eligible Items"},
        "count" => %{"class" => "font-mono text-base-content/60", "text" => "3"}
      },
      "list_class" => "space-y-1",
      "actions" => [
        %{
          "key" => "approved",
          "attrs" => %{
            "class" => "rounded border border-base-300/50 bg-base-200/40 px-2 py-1",
            "data-historical-workflow-group-eligible-action" => "approved",
            "data-historical-workflow-group-eligible-count" => "3",
            "data-historical-workflow-group-eligible-state" => "true",
            "data-workflow-action-correction-tasks" =>
              "HK.current run-3 replacement run-3-corrected stage requested next approve"
          },
          "header" => %{
            "class" => "flex items-center justify-between gap-2",
            "label" => %{"class" => "font-mono text-base-content", "text" => "Approve"},
            "count" => %{
              "class" => "badge badge-xs badge-outline font-mono",
              "text" => "3"
            }
          },
          "preview" => %{
            "class" => "mt-1 text-base-content/75",
            "text" => "Approve eligible items."
          },
          "state_summary" => nil,
          "available_when" => nil
        },
        %{
          "key" => "completed",
          "attrs" => %{
            "class" => "rounded border border-base-300/50 bg-base-200/40 px-2 py-1",
            "data-historical-workflow-group-eligible-action" => "completed",
            "data-historical-workflow-group-eligible-count" => "0",
            "data-historical-workflow-group-eligible-state" => "false",
            "data-historical-workflow-group-eligible-reason" => "not_started"
          },
          "header" => %{
            "class" => "flex items-center justify-between gap-2",
            "label" => %{"class" => "font-mono text-base-content", "text" => "Complete"},
            "count" => %{
              "class" => "badge badge-xs badge-outline font-mono",
              "text" => "0"
            }
          },
          "preview" => %{
            "class" => "mt-1 text-base-content/75",
            "text" => "Complete after start."
          },
          "state_summary" => nil,
          "available_when" => %{
            "class" => "mt-1 text-base-content/60",
            "text" => "Start eligible items before completion."
          }
        },
        %{
          "key" => "started",
          "attrs" => %{
            "class" => "rounded border border-base-300/50 bg-base-200/40 px-2 py-1",
            "data-historical-workflow-group-eligible-action" => "started",
            "data-historical-workflow-group-eligible-count" => "3",
            "data-historical-workflow-group-eligible-state" => "true",
            "data-historical-workflow-group-eligible-reason" => "eligible_group_items"
          },
          "header" => %{
            "class" => "flex items-center justify-between gap-2",
            "label" => %{"class" => "font-mono text-base-content", "text" => "Start"},
            "count" => %{
              "class" => "badge badge-xs badge-outline font-mono",
              "text" => "3"
            }
          },
          "preview" => %{
            "class" => "mt-1 text-base-content/75",
            "text" => "Record start transition for 3 eligible review items."
          },
          "state_summary" => %{
            "class" => "mt-1 font-mono text-base-content/60",
            "text" => "group request-group-1; progress 3/3; eligible 3 for started"
          },
          "available_when" => %{
            "class" => "mt-1 text-base-content/60",
            "text" => "Available while group items remain startable."
          }
        }
      ]
    }
  end

  defp expected_start_orchestration do
    %{
      "id" => "dashboard-historical-workflow-group-start-orchestration",
      "class" => "space-y-2 rounded border border-info/40 bg-info/10 p-2",
      "attrs" => %{
        "data-historical-workflow-group-start-request-group" => "request-group-1",
        "data-historical-workflow-group-start-next-action" => "start_eligible_items",
        "data-historical-workflow-group-start-eligible" => "3",
        "data-historical-workflow-group-start-eligible-state" => "true",
        "data-historical-workflow-group-start-reason" => "eligible_group_items",
        "data-historical-workflow-group-start-preview" =>
          "Record start transition for 3 eligible review items.",
        "data-historical-workflow-group-start-state" =>
          "group request-group-1; progress 3/3; eligible 3 for started",
        "data-historical-workflow-group-start-available-when" =>
          "Available while group items remain startable.",
        "data-historical-workflow-group-start-expected-jobs" => "3",
        "data-historical-workflow-group-start-review-request" => "review-request-1",
        "data-historical-workflow-group-start-review-kind" => "comparison_open_findings_review",
        "data-historical-workflow-group-start-review-open-count" => "3",
        "data-historical-workflow-group-start-review-placements" =>
          "placement-1,placement-2,placement-3",
        "data-historical-workflow-group-start-review-scope-kind" => "transport",
        "data-historical-workflow-group-start-review-scope-ids" =>
          "transport-alpha,transport-beta",
        "data-historical-workflow-group-start-review-contact-ids" => "contact-alpha,contact-beta",
        "data-historical-workflow-group-start-review-resource-ids" => "transport-alpha",
        "data-historical-workflow-group-start-review-transport-ids" => "transport-alpha",
        "data-historical-workflow-group-start-review-source-endpoint-ids" => "endpoint-alpha",
        "data-historical-workflow-group-start-review-ground-station-ids" => "dss-14",
        "data-historical-workflow-group-start-review-scope-link-ids" => "link-alpha"
      },
      "header" => %{
        "class" => "flex items-center justify-between gap-2",
        "title" => %{"class" => "hud-label", "text" => "Start Orchestration"},
        "count" => %{
          "class" => "badge badge-xs badge-info font-mono",
          "text" => "3 jobs"
        }
      },
      "guidance" => %{
        "class" => "text-base-content/75",
        "text" =>
          "3 review findings are attached. Record start transition for 3 eligible review items."
      },
      "details" => %{
        "class" => "grid grid-cols-[6rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs",
        "eligible" => %{
          "label" => %{"class" => "text-base-content/60", "text" => "Eligible"},
          "value" => %{"class" => "font-mono", "text" => "3"}
        },
        "review" => %{
          "label" => %{"class" => "text-base-content/60", "text" => "Review"},
          "value" => %{"class" => "font-mono break-all", "text" => "review-request-1"}
        },
        "state" => %{
          "label" => %{"class" => "text-base-content/60", "text" => "State"},
          "value" => %{
            "class" => "font-mono break-all",
            "text" => "group request-group-1; progress 3/3; eligible 3 for started"
          }
        }
      },
      "available_when" => %{
        "class" => "text-base-content/60",
        "text" => "Available while group items remain startable."
      }
    }
  end

  defp expected_action_buttons do
    [
      %{
        "key" => "approved",
        "attrs" => %{
          "id" => "dashboard-historical-workflow-group-approved",
          "type" => "submit",
          "name" => "historical_workflow_group[stage]",
          "value" => "approved",
          "class" => "btn btn-xs justify-between gap-2 btn-success btn-outline",
          "data-historical-workflow-group-action" => "approved",
          "data-historical-workflow-group-action-eligible" => "3",
          "data-workflow-action-id" => "group-approve",
          "data-workflow-action-eligible" => "true",
          "data-workflow-action-preview" => "Approve eligible items.",
          "data-workflow-action-correction-tasks" =>
            "HK.current run-3 replacement run-3-corrected stage requested next approve"
        },
        "label" => %{
          "class" => "flex min-w-0 items-center gap-1",
          "icon" => %{"name" => "hero-check-circle", "class" => "h-3.5 w-3.5"},
          "text" => "Approve"
        },
        "count" => %{"class" => "font-mono", "text" => "3"}
      },
      %{
        "key" => "completed",
        "attrs" => %{
          "id" => "dashboard-historical-workflow-group-completed",
          "type" => "submit",
          "name" => "historical_workflow_group[stage]",
          "value" => "completed",
          "disabled" => "",
          "class" => "btn btn-xs justify-between gap-2 btn-disabled",
          "data-historical-workflow-group-action" => "completed",
          "data-historical-workflow-group-action-eligible" => "0",
          "data-workflow-action-id" => "group-complete",
          "data-workflow-action-eligible" => "false",
          "data-workflow-action-reason" => "not_started",
          "data-workflow-action-preview" => "Complete after start."
        },
        "label" => %{
          "class" => "flex min-w-0 items-center gap-1",
          "icon" => %{"name" => "hero-flag", "class" => "h-3.5 w-3.5"},
          "text" => "Complete"
        },
        "count" => %{"class" => "font-mono", "text" => "0"}
      },
      %{
        "key" => "started",
        "attrs" => %{
          "id" => "dashboard-historical-workflow-group-started",
          "type" => "submit",
          "name" => "historical_workflow_group[stage]",
          "value" => "started",
          "class" => "btn btn-xs justify-between gap-2 btn-info btn-outline",
          "data-historical-workflow-group-action" => "started",
          "data-historical-workflow-group-action-eligible" => "3",
          "data-workflow-action-id" => "group-start",
          "data-workflow-action-eligible" => "true",
          "data-workflow-action-reason" => "eligible_group_items",
          "data-workflow-action-preview" => "Record start transition for 3 eligible review items."
        },
        "label" => %{
          "class" => "flex min-w-0 items-center gap-1",
          "icon" => %{"name" => "hero-play", "class" => "h-3.5 w-3.5"},
          "text" => "Start"
        },
        "count" => %{"class" => "font-mono", "text" => "3"}
      }
    ]
  end

  defp group_stage_actions do
    [
      %{
        stage: "approved",
        id: "group-approve",
        label: "Approve",
        icon: "hero-check-circle",
        class: "btn-success btn-outline",
        disabled?: false,
        eligible?: true,
        eligible_count: 3,
        reason: nil,
        preview: "Approve eligible items.",
        correction_tasks:
          "HK.current run-3 replacement run-3-corrected stage requested next approve"
      },
      %{
        stage: "completed",
        id: "group-complete",
        label: "Complete",
        icon: "hero-flag",
        class: "btn-primary btn-outline",
        disabled?: true,
        eligible?: false,
        eligible_count: 0,
        reason: "not_started",
        preview: "Complete after start.",
        available_when: "Start eligible items before completion."
      },
      %{
        stage: "started",
        id: "group-start",
        label: "Start",
        icon: "hero-play",
        class: "btn-info btn-outline",
        disabled?: false,
        eligible?: true,
        eligible_count: 3,
        reason: "eligible_group_items",
        preview: "Record start transition for 3 eligible review items.",
        state_summary: "group request-group-1; progress 3/3; eligible 3 for started",
        available_when: "Available while group items remain startable."
      }
    ]
  end

  defp group_form do
    %{
      "workflow" => "backfill",
      "request_group_id" => "request-group-1",
      "realm" => "flight",
      "data_source_id" => "questdb-flight",
      "source_binding_id" => "binding-flight",
      "dashboard_id" => "dashboard-1",
      "dashboard_version" => "7",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-1",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed",
      "reason" => "operator group transition",
      "confirmed" => ""
    }
    |> to_form(as: :historical_workflow_group)
  end

  defp workflow_context do
    %{
      workflow: "backfill",
      request_group_id: "request-group-1",
      realm: "flight",
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight",
      dashboard_id: "dashboard-1",
      dashboard_version: "7",
      dashboard_time_mode: "replay_run",
      dashboard_replay_run_id: "replay-1",
      dashboard_data_view: "all_revisions",
      dashboard_limit_mode: "observed",
      request_item_count: "3",
      comparison_review_request_event_id: "review-request-1",
      comparison_review_request_kind: "comparison_open_findings_review",
      comparison_review_open_count: "3",
      comparison_review_open_placement_ids: "placement-1,placement-2,placement-3",
      comparison_review_scope_kind: "transport",
      comparison_review_scope_ids: "transport-alpha,transport-beta",
      comparison_review_contact_ids: "contact-alpha,contact-beta",
      comparison_review_resource_ids: "transport-alpha",
      comparison_review_transport_ids: "transport-alpha",
      comparison_review_source_endpoint_ids: "endpoint-alpha",
      comparison_review_ground_station_ids: "dss-14",
      comparison_review_scope_link_ids: "link-alpha",
      reason: "operator group transition"
    }
  end
end
