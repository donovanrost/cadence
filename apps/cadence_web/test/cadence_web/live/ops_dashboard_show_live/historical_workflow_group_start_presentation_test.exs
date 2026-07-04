defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStartPresentationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStartPresentation

  test "build derives eligible start orchestration with review context" do
    presentation =
      HistoricalWorkflowGroupStartPresentation.build(
        %{comparison_review_open_count: "3"},
        %{
          group_stage_actions: [
            %{stage: "approved", eligible?: true, eligible_count: 3},
            %{
              stage: "started",
              eligible?: true,
              eligible_count: 3,
              reason: "eligible_group_items",
              preview: "Record start transition for 3 eligible review items.",
              state_summary: "group request-group-1; progress 3/3; eligible 3 for started"
            }
          ]
        }
      )

    assert presentation.present
    assert presentation.next_action == "start_eligible_items"
    assert presentation.eligible_count == "3"
    assert presentation.eligible == "true"
    assert presentation.expected_jobs == "3"
    assert presentation.reason == "eligible_group_items"
    assert presentation.preview == "Record start transition for 3 eligible review items."
    assert presentation.state == "group request-group-1; progress 3/3; eligible 3 for started"

    assert presentation.guidance ==
             "3 review findings are attached. Record start transition for 3 eligible review items."
  end

  test "build derives wait-for-eligibility guidance" do
    presentation =
      HistoricalWorkflowGroupStartPresentation.build(
        %{},
        %{
          group_stage_actions: [
            %{
              stage: "started",
              eligible?: false,
              eligible_count: 0,
              reason: "no_eligible_group_items",
              available_when: "Approve eligible items first."
            }
          ]
        }
      )

    assert presentation.present
    assert presentation.next_action == "wait_for_eligibility"
    assert presentation.eligible_count == "0"
    assert presentation.eligible == "false"
    assert presentation.expected_jobs == "0"
    assert presentation.available_when == "Approve eligible items first."

    assert presentation.guidance ==
             "No items are startable yet; approve eligible items before dispatching jobs."
  end

  test "build derives inspect guidance for blocked start actions" do
    presentation =
      HistoricalWorkflowGroupStartPresentation.build(
        %{comparison_review_open_count: "2"},
        %{
          group_stage_actions: [
            %{
              stage: "started",
              eligible?: false,
              eligible_count: "1",
              reason: "blocked_by_policy"
            }
          ]
        }
      )

    assert presentation.present
    assert presentation.next_action == "inspect_group_state"
    assert presentation.eligible_count == "1"

    assert presentation.guidance ==
             "2 review findings are attached. Inspect group state before dispatching jobs for this workflow group."
  end

  test "build returns empty presentation without a start action" do
    assert HistoricalWorkflowGroupStartPresentation.build(nil, nil) ==
             %HistoricalWorkflowGroupStartPresentation{}

    assert HistoricalWorkflowGroupStartPresentation.build(%{}, %{group_stage_actions: []}) ==
             %HistoricalWorkflowGroupStartPresentation{}
  end
end
