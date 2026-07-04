defmodule CadenceWeb.OpsDashboardShowLive.RuntimeAdminDecisionLinkTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RuntimeAdminDecisionLink

  test "builds admin runtime decision links from recent invalidation rows" do
    link =
      RuntimeAdminDecisionLink.from_runtime_invalidation(%{
        dashboard_id: "dashboard-1",
        mission_id: "mission-1",
        boundary: "source_watermark_changed",
        context_reason: "replay_run_mismatch",
        replay_run_id: "replay-1",
        affected_placement_ids: "placement-1,placement-2",
        decision_event_id: "decision-1"
      })

    assert path(link) == "/admin/runtime"

    assert query(link) == %{
             "affected_placement_id" => "placement-1",
             "boundary" => "source_watermark_changed",
             "context_reason" => "replay_run_mismatch",
             "dashboard_id" => "dashboard-1",
             "decision" => "decision-1",
             "mission_id" => "mission-1",
             "replay_run_id" => "replay-1"
           }
  end

  test "builds admin runtime decision links from no-refresh blockers" do
    link =
      RuntimeAdminDecisionLink.from_no_refresh_summary(%{
        blocker: %{
          "dashboard_id" => "dashboard-1",
          "mission_id" => "mission-1",
          "boundary" => "historical_data_changed",
          "context_reason_filter" => "replay_run_mismatch",
          "replay_run_id" => "replay-1",
          "affected_placement_ids" => "placement-1",
          "decision_event_id" => "decision-1"
        }
      })

    assert path(link) == "/admin/runtime"

    assert query(link) == %{
             "affected_placement_id" => "placement-1",
             "boundary" => "historical_data_changed",
             "context_reason" => "replay_run_mismatch",
             "dashboard_id" => "dashboard-1",
             "decision" => "decision-1",
             "mission_id" => "mission-1",
             "replay_run_id" => "replay-1"
           }
  end

  test "omits empty values and refuses placeholder decision ids" do
    assert RuntimeAdminDecisionLink.from_runtime_invalidation(%{
             dashboard_id: "dashboard-1",
             decision_event_id: "-"
           }) == nil

    link =
      RuntimeAdminDecisionLink.from_runtime_invalidation(%{
        dashboard_id: "dashboard-1",
        mission_id: "",
        boundary: "-",
        context_reason: nil,
        replay_run_id: "replay-1",
        affected_placement_ids: "",
        decision_event_id: "decision-1"
      })

    assert query(link) == %{
             "dashboard_id" => "dashboard-1",
             "decision" => "decision-1",
             "replay_run_id" => "replay-1"
           }
  end

  defp path(link) do
    link
    |> URI.parse()
    |> Map.fetch!(:path)
  end

  defp query(link) do
    link
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end
end
