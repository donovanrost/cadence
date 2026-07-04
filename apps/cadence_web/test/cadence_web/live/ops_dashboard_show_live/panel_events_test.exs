defmodule CadenceWeb.OpsDashboardShowLive.PanelEventsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.PanelEvents
  alias Phoenix.LiveView.Socket

  test "open_rename opens the rename panel" do
    socket =
      socket(%{
        panel: nil,
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_review_placement_id: "placement-1"
      })
      |> PanelEvents.open_rename()

    assert socket.assigns.panel == :rename
    assert socket.assigns.dashboard_activity_filter == nil
    assert socket.assigns.dashboard_activity_event_id == nil
    assert socket.assigns.dashboard_review_placement_id == nil
  end

  test "open_versions opens versions and refreshes publish validation" do
    socket =
      socket(%{
        panel: nil,
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_review_placement_id: "placement-1"
      })
      |> PanelEvents.open_versions(
        assign_publish_validation: fn socket ->
          assign(socket, :dashboard_publish_validation, %{valid?: true})
        end
      )

    assert socket.assigns.panel == :versions
    assert socket.assigns.dashboard_activity_filter == nil
    assert socket.assigns.dashboard_activity_event_id == nil
    assert socket.assigns.dashboard_review_placement_id == nil
    assert socket.assigns.dashboard_publish_validation == %{valid?: true}
  end

  test "refresh_publish_readiness keeps versions focus and refreshes publish validation" do
    socket =
      socket(%{
        panel: :versions,
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_activity_event_id: "event-1",
        dashboard_review_placement_id: "placement-1"
      })
      |> PanelEvents.refresh_publish_readiness(
        refresh_publish_validation: fn socket, _opts ->
          assign(socket, :dashboard_publish_validation, %{valid?: true, refreshed?: true})
        end
      )

    assert socket.assigns.panel == :versions
    assert socket.assigns.dashboard_activity_filter == :open_comparison_reviews
    assert socket.assigns.dashboard_activity_event_id == "event-1"
    assert socket.assigns.dashboard_review_placement_id == "placement-1"
    assert socket.assigns.dashboard_publish_validation == %{valid?: true, refreshed?: true}
  end

  test "open_review_activity opens versions focused on open comparison reviews" do
    socket =
      socket(%{panel: nil})
      |> PanelEvents.open_review_activity(
        assign_publish_validation: fn socket ->
          assign(socket, :dashboard_publish_validation, %{valid?: true})
        end
      )

    assert socket.assigns.panel == :versions
    assert socket.assigns.dashboard_activity_filter == :open_comparison_reviews
    assert socket.assigns.dashboard_activity_event_id == nil
    assert socket.assigns.dashboard_publish_validation == %{valid?: true}
  end

  test "open_activity_filter opens versions with a normalized activity filter" do
    socket =
      socket(%{panel: nil})
      |> PanelEvents.open_activity_filter("health_snapshots",
        assign_publish_validation: fn socket ->
          assign(socket, :dashboard_publish_validation, %{valid?: true})
        end,
        patch: fn socket, query ->
          assign(socket, :patched_query, query)
        end
      )

    assert socket.assigns.panel == :versions
    assert socket.assigns.dashboard_activity_filter == :health_snapshots
    assert socket.assigns.dashboard_activity_event_id == nil
    assert socket.assigns.dashboard_review_placement_id == nil
    assert socket.assigns.dashboard_publish_validation == %{valid?: true}

    assert socket.assigns.patched_query == %{
             "panel" => "versions",
             "activity_filter" => "health_snapshots",
             "activity_event" => nil,
             "selected_placement" => nil
           }
  end

  test "open_activity_filter clears unsupported activity filters" do
    socket =
      socket(%{panel: nil, dashboard_activity_filter: :open_comparison_reviews})
      |> PanelEvents.open_activity_filter("unknown",
        assign_publish_validation: fn socket -> socket end,
        patch: fn socket, query ->
          assign(socket, :patched_query, query)
        end
      )

    assert socket.assigns.panel == :versions
    assert socket.assigns.dashboard_activity_filter == nil
    assert socket.assigns.dashboard_activity_event_id == nil
    assert socket.assigns.dashboard_review_placement_id == nil

    assert socket.assigns.patched_query == %{
             "panel" => "versions",
             "activity_filter" => "",
             "activity_event" => nil,
             "selected_placement" => nil
           }
  end

  test "select_activity_event selects an activity row and patches a durable query" do
    socket =
      socket(%{panel: :versions, dashboard_activity_filter: :health_snapshots})
      |> PanelEvents.select_activity_event("dashboard-lifecycle-event-health",
        assign_publish_validation: fn socket ->
          assign(socket, :dashboard_publish_validation, %{valid?: true})
        end,
        patch: fn socket, query ->
          assign(socket, :patched_query, query)
        end
      )

    assert socket.assigns.panel == :versions
    assert socket.assigns.dashboard_activity_filter == :health_snapshots
    assert socket.assigns.dashboard_activity_event_id == "dashboard-lifecycle-event-health"
    assert socket.assigns.dashboard_review_placement_id == nil
    assert socket.assigns.dashboard_publish_validation == %{valid?: true}

    assert socket.assigns.patched_query == %{
             "panel" => "versions",
             "activity_filter" => "health_snapshots",
             "activity_event" => "dashboard-lifecycle-event-health",
             "selected_placement" => nil
           }
  end

  test "select_review_placement opens review activity and patches review placement query" do
    socket =
      socket(%{panel: nil})
      |> PanelEvents.select_review_placement("placement-1",
        assign_publish_validation: fn socket ->
          assign(socket, :dashboard_publish_validation, %{valid?: true})
        end,
        patch: fn socket, query ->
          assign(socket, :patched_query, query)
        end
      )

    assert socket.assigns.panel == :versions
    assert socket.assigns.dashboard_activity_filter == :open_comparison_reviews
    assert socket.assigns.dashboard_activity_event_id == nil
    assert socket.assigns.dashboard_review_placement_id == "placement-1"
    assert socket.assigns.dashboard_publish_validation == %{valid?: true}

    assert socket.assigns.patched_query == %{
             "panel" => "versions",
             "activity_filter" => "open_comparison_reviews",
             "activity_event" => nil,
             "selected_placement" => "placement-1"
           }
  end

  test "open_diagnostics opens the diagnostics panel" do
    socket =
      socket(%{
        panel: nil,
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_review_placement_id: "placement-1"
      })
      |> PanelEvents.open_diagnostics()

    assert socket.assigns.panel == :diagnostics
    assert socket.assigns.dashboard_activity_filter == nil
    assert socket.assigns.dashboard_activity_event_id == nil
    assert socket.assigns.dashboard_review_placement_id == nil
  end

  test "close closes ordinary panels without clearing evidence query" do
    socket =
      socket(%{
        panel: :versions,
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_review_placement_id: "placement-1",
        dashboard_evidence_query: %{"selected_evidence_kind" => "source"},
        data_link_action_outcome: %{action: :late_data_policy},
        data_link_action_outcome_query: %{"selected_id" => "event-1"}
      })
      |> PanelEvents.close()

    assert socket.assigns.panel == nil
    assert socket.assigns.dashboard_activity_filter == nil
    assert socket.assigns.dashboard_activity_event_id == nil
    assert socket.assigns.dashboard_review_placement_id == nil
    assert socket.assigns.dashboard_evidence_query == %{"selected_evidence_kind" => "source"}
    assert socket.assigns.data_link_action_outcome == nil
    assert socket.assigns.data_link_action_outcome_query == nil
  end

  test "close clears evidence panel state and route query" do
    socket =
      socket(%{
        panel: {:evidence, %{kind: "source"}},
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_review_placement_id: "placement-1",
        dashboard_evidence_query: %{"selected_evidence_kind" => "source"}
      })
      |> PanelEvents.close(
        patch: fn socket, query ->
          assign(socket, :patched_query, query)
        end
      )

    assert socket.assigns.panel == nil
    assert socket.assigns.dashboard_activity_filter == nil
    assert socket.assigns.dashboard_activity_event_id == nil
    assert socket.assigns.dashboard_review_placement_id == nil
    assert socket.assigns.dashboard_evidence_query == nil
    assert socket.assigns.patched_query["panel"] == nil
    assert socket.assigns.patched_query["selected_evidence_kind"] == nil
  end

  defp socket(assigns) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            panel: nil,
            dashboard_activity_filter: nil,
            dashboard_activity_event_id: nil,
            dashboard_review_placement_id: nil,
            dashboard_evidence_query: nil,
            dashboard_publish_validation: nil,
            data_link_action_outcome: nil,
            data_link_action_outcome_query: nil
          },
          assigns
        )
    }
  end
end
