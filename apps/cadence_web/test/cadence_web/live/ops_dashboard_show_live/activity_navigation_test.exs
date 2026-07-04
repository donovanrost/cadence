defmodule CadenceWeb.OpsDashboardShowLive.ActivityNavigationTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures

  alias CadenceWeb.OpsDashboardShowLive.ActivityNavigation

  test "query builds the shared versions activity patch contract" do
    event = lifecycle_event("dashboard-lifecycle-event-health", :health_snapshot_captured)

    assert ActivityNavigation.query(:health_snapshots, event) == %{
             "panel" => "versions",
             "activity_filter" => "health_snapshots",
             "activity_event" => "dashboard-lifecycle-event-health",
             "selected_placement" => nil
           }
  end

  test "query normalizes unsupported filters and missing events" do
    assert ActivityNavigation.query("unknown") == %{
             "panel" => "versions",
             "activity_filter" => "",
             "activity_event" => nil,
             "selected_placement" => nil
           }
  end

  test "link preserves runtime query params and clears selected placement" do
    event = lifecycle_event("dashboard-lifecycle-event-review", :comparison_review_requested)

    link =
      ActivityNavigation.link(
        "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&selected_placement=placement-stale",
        :comparison_reviews,
        event
      )

    uri = URI.parse(link)
    query = URI.decode_query(uri.query)

    assert uri.path == "/missions/mission-1/ops/dashboards/dashboard-1"

    assert query == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions",
             "activity_filter" => "comparison_reviews",
             "activity_event" => "dashboard-lifecycle-event-review"
           }

    refute Map.has_key?(query, "selected_placement")
  end

  test "open comparison review link can focus an affected placement" do
    link =
      ActivityNavigation.open_comparison_review_link(
        "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&panel=data_link",
        "dashboard-lifecycle-review-1",
        selected_placement: "placement-voltage"
      )

    uri = URI.parse(link)
    query = URI.decode_query(uri.query)

    assert uri.path == "/missions/mission-1/ops/dashboards/dashboard-1"

    assert query == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions",
             "activity_filter" => "open_comparison_reviews",
             "activity_event" => "dashboard-lifecycle-review-1",
             "selected_placement" => "placement-voltage"
           }
  end

  test "link accepts string event ids and omits all-activity filter" do
    link =
      ActivityNavigation.link(
        "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission",
        :all,
        "dashboard-lifecycle-event-1"
      )

    query =
      link
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    assert query == %{
             "scope_kind" => "mission",
             "panel" => "versions",
             "activity_event" => "dashboard-lifecycle-event-1"
           }
  end
end
