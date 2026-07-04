defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupRecoveryFormPresentationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupRecoveryFormPresentation

  test "build packages corrected replacement advancement submit contract" do
    presentation =
      HistoricalWorkflowGroupRecoveryFormPresentation.build(workflow_context(), %{
        replacement_action: %{
          present: true,
          id: "group-stage-approved",
          stage: "approved",
          eligible: "true",
          count: "1",
          reason: "eligible_group_items",
          preview: "Advance 1 corrected replacement request to approved.",
          correction_tasks:
            "HK.current run-003 replacement run-003-corrected stage requested next approve",
          disabled_bool: false,
          submit_reason: "dashboard_recovery_replacement_approved"
        },
        completion_action: %{present: false}
      })

    form = presentation.replacement_advancement

    assert form.present
    assert form.id == "dashboard-historical-workflow-group-recovery-advance-corrected-form"
    assert form.submit_event == "record_historical_workflow_group_stage"
    assert form.request_group_id == "request-group-1"
    assert form.stage == "approved"
    assert form.eligible == "true"
    assert form.count == "1"
    assert form.reason == "eligible_group_items"
    assert form.preview == "Advance 1 corrected replacement request to approved."
    assert form.action_id == "group-stage-approved"
    assert form.disabled_bool == false

    assert hidden_field(form, "historical_workflow_group[workflow]") == "backfill"
    assert hidden_field(form, "historical_workflow_group[request_group_id]") == "request-group-1"
    assert hidden_field(form, "historical_workflow_group[dashboard_version]") == "7"

    assert hidden_field(form, "historical_workflow_group[reason]") ==
             "dashboard_recovery_replacement_approved"

    assert hidden_field(form, "historical_workflow_group[group_transition_scope]") ==
             "replacement_corrections"

    assert hidden_field(form, "historical_workflow_group[group_correction_tasks]") ==
             "HK.current run-003 replacement run-003-corrected stage requested next approve"

    assert hidden_field(form, "historical_workflow_group[confirmed]") == "confirmed"
    assert presentation.completion.present == false
  end

  test "build packages group completion submit contract" do
    presentation =
      HistoricalWorkflowGroupRecoveryFormPresentation.build(workflow_context(), %{
        replacement_action: %{present: false},
        completion_action: %{
          present: true,
          id: "group-stage-completed",
          stage: "completed",
          eligible: "true",
          count: "1",
          reason: "eligible_group_items",
          preview: "Complete recovered group.",
          disabled_bool: false,
          submit_reason: "dashboard_recovery_group_completed"
        }
      })

    form = presentation.completion

    assert form.present
    assert form.id == "dashboard-historical-workflow-group-recovery-complete-form"
    assert form.submit_event == "record_historical_workflow_group_stage"
    assert form.request_group_id == "request-group-1"
    assert form.stage == "completed"
    assert form.eligible == "true"
    assert form.count == "1"
    assert form.reason == "eligible_group_items"
    assert form.preview == "Complete recovered group."
    assert form.action_id == "group-stage-completed"
    assert form.disabled_bool == false

    assert hidden_field(form, "historical_workflow_group[workflow]") == "backfill"

    assert hidden_field(form, "historical_workflow_group[reason]") ==
             "dashboard_recovery_group_completed"

    assert hidden_field(form, "historical_workflow_group[confirmed]") == "confirmed"

    refute Map.has_key?(
             hidden_fields(form),
             "historical_workflow_group[group_transition_scope]"
           )

    refute Map.has_key?(
             hidden_fields(form),
             "historical_workflow_group[group_correction_tasks]"
           )
  end

  test "build defaults absent contexts to empty forms" do
    assert HistoricalWorkflowGroupRecoveryFormPresentation.build(nil, nil) ==
             %HistoricalWorkflowGroupRecoveryFormPresentation{}

    presentation =
      HistoricalWorkflowGroupRecoveryFormPresentation.build(workflow_context(), %{
        replacement_action: %{present: false},
        completion_action: %{present: false}
      })

    assert presentation.replacement_advancement.present == false
    assert presentation.replacement_advancement.hidden_fields == []
    assert presentation.completion.present == false
    assert presentation.completion.hidden_fields == []
  end

  defp hidden_field(form, name), do: Map.fetch!(hidden_fields(form), name)

  defp hidden_fields(form) do
    Map.new(form.hidden_fields, &{&1.name, &1.value})
  end

  defp workflow_context do
    %{
      workflow: "backfill",
      request_group_id: "request-group-1",
      realm: "backfill",
      data_source_id: "managed_questdb",
      source_binding_id: "telemetry-history",
      dashboard_id: "dashboard-1",
      dashboard_version: "7",
      dashboard_time_mode: "archive",
      dashboard_replay_run_id: "replay-1",
      dashboard_data_view: "as_recorded",
      dashboard_limit_mode: "observed"
    }
  end
end
